import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../design/tokens/color_tokens.dart';
import '../data/attachments/attachment_upload.dart';
import '../data/attachments/attachment_url_resolver.dart';
import '../data/attachments/device_image_picker.dart';
import '../data/attachments/trusted_attachment_url.dart';
import '../data/models/question_attachment.dart';
import '../data/models/question_message.dart';
import '../data/models/question_thread.dart';
import '../data/question_room_read_repository.dart';
import '../data/question_room_write_repository.dart';
import '../data/thread_messages_controller.dart';
import '../data/thread_realtime.dart';
import '../../scan_annotation/scan_annotation_screen.dart';
import 'attachment_viewer_screen.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/scan_source_sheet.dart';
import 'widgets/live_message_list.dart';
import 'widgets/thread_status_pill.dart';
import '../../../core/scan/image_downscaler.dart';
import '../../../core/scan/scan_source_picker.dart';
import '../../../core/scan/pdf_rasterizer.dart';
import '../../../core/scan/widgets/scan_pick_expander.dart';
import '../../../shared/errors/friendly_error.dart';

/// 채팅(3뎁스). 카카오톡식 말풍선(학생=우측/멘토=좌측) + 하단 입력창.
/// 메시지는 append 전용 — 수정/삭제 없음.
///
/// S6: Realtime 구독으로 새 메시지를 새로고침 없이 즉시 반영(폴백: 전송 후/수동 재조회).
///     첨부는 주입 포트로 이미지 선택→미리보기→업로드(저장소 준비 시 동작).
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.thread,
    required this.mentorName,
    this.imagePicker = const DeviceImagePicker(),
    this.scanPicker = const DeviceScanSourcePicker(),
    this.pdfRasterizer = const PdfxRasterizer(),
    this.uploader = const SupabaseAttachmentUploader(),
    this.realtimeFactory = _defaultRealtime,
  });

  final QuestionThread thread;
  final String mentorName;

  /// 갤러리 선택 포트(하위호환 주입 지점 — 시트에서 '갤러리' 선택 시 사용).
  final ImagePickerPort imagePicker;

  /// 스캔 소스 포트(S16: 촬영·파일). 테스트에서 fake 주입.
  final ScanSourcePort scanPicker;

  /// PDF 래스터라이저 포트(S19: 파일 소스 PDF → 페이지 선택). fake 주입 지점.
  final PdfRasterizerPort pdfRasterizer;

  /// 첨부 업로드 포트(기본: 저장소 미준비 — 인수인계).
  final AttachmentUploaderPort uploader;

  /// 스레드 실시간 포트 팩토리(기본: Supabase). 테스트에서 fake 주입.
  final ThreadRealtimePort Function(String threadId) realtimeFactory;

  static ThreadRealtimePort _defaultRealtime(String threadId) =>
      SupabaseThreadRealtime(threadId);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final QuestionRoomReadRepository _read = const QuestionRoomReadRepository();
  final QuestionRoomWriteRepository _write =
      const QuestionRoomWriteRepository();
  final TextEditingController _input = TextEditingController();

  late final ThreadRealtimePort _realtime;
  late ThreadStatus _status; // 실시간 상태 변경(멘토 답변 등)으로 갱신.
  ThreadMessagesController? _messages;
  bool _loading = true;
  Object? _loadError;
  bool _sending = false;
  PickedImage? _pending;

  /// 첨부 이미지 서명 URL 리졸버(만료 전 캐시 재사용).
  final AttachmentUrlResolver _resolver = AttachmentUrlResolver.supabase();
  List<QuestionAttachment> _attachments = <QuestionAttachment>[];

  String? get _uid => SupabaseInit.clientOrNull?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _status = widget.thread.status;
    _realtime = widget.realtimeFactory(widget.thread.id);
    _load();
  }

  /// 스레드 상태 변경(실시간) → 최신 상태 재조회해 상태칩 갱신.
  Future<void> _onThreadUpdate() async {
    try {
      final QuestionThread? t = await _read.threadById(widget.thread.id);
      if (t != null && mounted) setState(() => _status = t.status);
    } catch (_) {
      // 무시 — 상태칩은 다음 갱신에서 반영.
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _messages?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<QuestionMessage> msgs = await _read.messages(widget.thread.id);
      final List<QuestionAttachment> atts = await _loadAttachments();
      if (!mounted) return;
      setState(() {
        _messages = ThreadMessagesController(msgs);
        _attachments = atts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// 첨부 조회는 best-effort — 실패해도 대화는 막지 않는다(빈 목록 폴백).
  Future<List<QuestionAttachment>> _loadAttachments() async {
    try {
      return await _read.attachments(widget.thread.id);
    } catch (_) {
      return const <QuestionAttachment>[];
    }
  }

  /// 파일(비이미지) 첨부 탭 → 단기 서명 URL 발급 후 외부 앱으로 열기(첨부 v2 §2-6).
  /// 발급 URL 이 우리 스토리지 호스트가 아니면 열지 않는다(P3-7 임의 URL 차단).
  Future<void> _openFile(QuestionAttachment a) async {
    try {
      final String url = await _resolver.signedUrl(a.storagePath);
      final Uri uri = Uri.parse(url);
      if (!isTrustedAttachmentUri(uri)) {
        _showError('파일을 열 수 없어요. 잠시 후 다시 시도해 주세요.');
        return;
      }
      final bool ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _showError('파일을 열 수 없어요. 잠시 후 다시 시도해 주세요.');
    } catch (e) {
      _showError('파일을 여는 데 실패했어요. ${friendlyError(e)}');
    }
  }

  /// 첨부 행 실시간 insert 수신 → 첨부만 재조회(상대방 첨부 즉시 반영, 첨부 v2 결정 ③).
  Future<void> _reloadAttachments() async {
    final List<QuestionAttachment> atts = await _loadAttachments();
    if (mounted) setState(() => _attachments = atts);
  }

  /// 폴백 재조회(Realtime 미설정 시 수동 새로고침 = 상대 메시지·첨부 반영).
  Future<void> _refresh() async {
    final ThreadMessagesController? ctrl = _messages;
    if (ctrl == null) return;
    try {
      final List<QuestionMessage> msgs = await _read.messages(widget.thread.id);
      ctrl.resetTo(msgs);
    } catch (_) {
      // 조용히 무시 — 기존 목록 유지.
    }
    final List<QuestionAttachment> atts = await _loadAttachments();
    if (mounted) setState(() => _attachments = atts);
  }

  /// 이미지 첨부 탭 → 전체화면 뷰어. 주석이 전송되면 목록 새로고침.
  Future<void> _openImage(QuestionAttachment a) async {
    final bool? refreshed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => AttachmentViewerScreen(
          attachment: a,
          roomId: widget.thread.roomId,
          threadId: widget.thread.id,
          resolver: _resolver,
        ),
      ),
    );
    if (refreshed == true && mounted) await _refresh();
  }

  Future<void> _send() async {
    final String body = _input.text.trim();
    final PickedImage? pending = _pending;
    if ((body.isEmpty && pending == null) || _sending) return;
    setState(() => _sending = true);
    bool attachmentDone = pending == null; // 첨부 없으면 정리할 것도 없음.
    try {
      QuestionMessage? sent;
      if (body.isNotEmpty) {
        final AppendedMessage appended =
            await _write.appendMessage(threadId: widget.thread.id, body: body);
        sent = appended.message;
        _input.clear();
        _messages?.add(sent); // 낙관적 반영(실시간과 중복돼도 무시됨).
      }
      if (pending != null) {
        // 첨부 성공 시에만 pending 제거(P2-19). 실패하면 미리보기를 유지해
        // 본문 성공·첨부 실패가 '전체 성공'으로 보이지 않게 한다.
        attachmentDone = await _uploadPending(pending, messageId: sent?.id);
      }
    } catch (e) {
      _showError('전송에 실패했어요. ${friendlyError(e)}');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          if (attachmentDone) _pending = null;
        });
      }
    }
  }

  /// 대기 첨부 업로드. 성공(=pending 정리 가능)이면 true.
  /// 오류를 삼키지 않는다 — 실패 사유를 표시하고 false 를 돌려준다(P2-19).
  Future<bool> _uploadPending(PickedImage image, {String? messageId}) async {
    if (!widget.uploader.isReady) {
      // 저장소 미준비(버킷 없음) → 안내만(골격). 텍스트는 이미 전송됨.
      _showError('이미지 첨부는 준비 중이에요. (저장소 설정 인수인계)');
      return false;
    }
    try {
      await widget.uploader.upload(
        roomId: widget.thread.roomId,
        threadId: widget.thread.id,
        messageId: messageId,
        image: image,
      );
      await _refresh(); // 첨부 반영.
      return true;
    } catch (e) {
      _showError('이미지 첨부에 실패했어요. ${friendlyError(e)}');
      return false;
    }
  }

  /// 첨부(S16/S19): 소스 시트 → 선택 → (PDF 면 페이지 선택) → 검증 → 미리보기.
  /// 갤러리는 기존 imagePicker 포트(하위호환), 촬영·파일은 scanPicker 포트.
  /// PDF 분기는 expandScanPick(소스 계층)이 담당 — 이 화면은 모른다.
  Future<void> _attach() async {
    final ScanSource? source = await showScanSourceSheet(context);
    if (source == null || !mounted) return; // 시트 취소 — 무동작.
    try {
      final PickedImage? picked = source == ScanSource.gallery
          ? await widget.imagePicker.pickImage()
          : await widget.scanPicker.pick(source);
      if (!mounted) return;
      final List<PickedImage> images = await expandScanPick(
        context,
        picked: picked,
        rasterizer: widget.pdfRasterizer,
        maxCount: 1, // 대기 슬롯 1(전송 전 미리보기 1장).
      );
      if (images.isNotEmpty) await _acceptPicked(images.first);
    } catch (e) {
      // PDF 폴백 안내(AppError) 포함 — 원문 비노출 규약.
      _showError(friendlyError(e));
    }
  }

  /// 선택 결과 공통 처리: 5MB 초과 리사이즈(§6-4) → 검증 → 미리보기 세팅.
  Future<void> _acceptPicked(PickedImage picked) async {
    final PickedImage img = await downscaleIfOversized(picked);
    final String? invalid = validatePickedImage(img);
    if (invalid != null) {
      _showError(invalid);
      return;
    }
    if (mounted) setState(() => _pending = img);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 선택한(전송 전) 이미지에 주석 달기(S15). 완료 시 평탄화 PNG 가 새 첨부로
  /// 전송되므로, 원본 대기 이미지는 지운다(중복 전송 방지).
  Future<void> _annotatePending() async {
    final PickedImage? img = _pending;
    if (img == null) return;
    final bool? sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ScanAnnotationScreen(
          background: img.bytes,
          roomId: widget.thread.roomId,
          threadId: widget.thread.id,
        ),
      ),
    );
    if (sent != true || !mounted) return;
    setState(() => _pending = null);
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주석을 첨부로 보냈어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.thread.title?.trim().isNotEmpty == true
              ? widget.thread.title!.trim()
              : '질문',
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _refresh,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: ThreadStatusPill(status: _status)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _list()),
          ChatInputBar(
            controller: _input,
            hintText: '메시지 입력',
            sending: _sending,
            onSend: _send,
            onAttach: _attach,
            pendingImage: _pending,
            onRemovePending: () => setState(() => _pending = null),
            onAnnotate: _annotatePending,
          ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('대화를 불러오지 못했어요.\n${friendlyError(_loadError!)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ColorTokens.danger)),
        ),
      );
    }
    return LiveMessageList(
      controller: _messages!,
      realtime: _realtime,
      currentUid: _uid,
      emptyHint: '첫 메시지를 남겨보세요.',
      onThreadUpdate: _onThreadUpdate,
      attachments: _attachments,
      resolver: _resolver,
      onOpenImage: _openImage,
      onOpenFile: _openFile,
      onAttachmentInsert: _reloadAttachments,
    );
  }
}
