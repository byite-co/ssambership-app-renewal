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
import '../data/models/room.dart';
import '../data/question_room_read_repository.dart';
import '../data/question_room_write_repository.dart';
import '../data/room_counterparty.dart';
import '../data/room_safety_repository.dart';
import '../data/thread_messages_controller.dart';
import '../data/thread_realtime.dart';
import '../../scan_annotation/scan_annotation_screen.dart';
import 'attachment_viewer_screen.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/room_safety_actions.dart';
import 'widgets/room_safety_menu.dart';
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
    this.room,
    this.imagePicker = const DeviceImagePicker(),
    this.scanPicker = const DeviceScanSourcePicker(),
    this.pdfRasterizer = const PdfxRasterizer(),
    this.uploader = const SupabaseAttachmentUploader(),
    this.realtimeFactory = _defaultRealtime,
    this.safety = const SupabaseRoomSafetyRepository(),
    this.currentUserIdOverride,
    this.readRepository = const QuestionRoomReadRepository(),
  });

  final QuestionThread thread;
  final String mentorName;

  /// 방 참여자 정보(신고·차단 상대 도출의 **정본**). null 이면 안전 메뉴 비활성화.
  final Room? room;

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

  /// 신고·차단 포트(기본: Supabase). 테스트에서 fake 주입.
  final RoomSafetyPort safety;

  /// 현재 사용자 id 주입 seam(테스트 전용). null 이면 세션에서 읽는다.
  /// ★ 상대 도출은 이 값과 [room] 참여자 데이터로만 한다 — 화면 문자열/메시지 추정 금지.
  final String? currentUserIdOverride;

  /// 읽기 레포 주입 seam(테스트 전용 — N21 페이지 계약 검증).
  final QuestionRoomReadRepository readRepository;

  static ThreadRealtimePort _defaultRealtime(String threadId) =>
      SupabaseThreadRealtime(threadId);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// 차단된 방의 composer 자리에 보여줄 안내(읽기 전용 상태 설명).
const String _blockedNotice = '차단한 사용자예요. 새 메시지·첨부를 보낼 수 없어요.'
    ' 지난 대화는 그대로 볼 수 있고, 해제는 설정 > 차단 사용자 관리에서 할 수 있어요.';

class _ChatScreenState extends State<ChatScreen> {
  QuestionRoomReadRepository get _read => widget.readRepository;
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

  String? get _uid =>
      widget.currentUserIdOverride ??
      SupabaseInit.clientOrNull?.auth.currentUser?.id;

  /// 신고·차단 대상(방 참여자에서 도출). null 이면 안전 메뉴 비활성화.
  RoomCounterparty? _counterparty;

  /// 내가 상대를 차단했는가 — true 면 이 방은 읽기 전용(전송·첨부 금지).
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _status = widget.thread.status;
    _counterparty = RoomCounterparty.of(
      widget.room,
      currentUid: _uid,
      displayName: widget.mentorName,
    );
    _realtime = widget.realtimeFactory(widget.thread.id);
    _load();
    _loadBlockState();
  }

  /// 입장 시 차단 상태 확인 — 이미 차단한 방은 처음부터 읽기 전용으로 연다.
  /// 조회 실패는 흐름을 막지 않는다(기본 false = 기존 동작).
  Future<void> _loadBlockState() async {
    final RoomCounterparty? cp = _counterparty;
    if (cp == null) return;
    bool blocked = false;
    try {
      blocked = await widget.safety.isBlockedByMe(cp.userId);
    } catch (_) {
      blocked = false;
    }
    if (mounted && blocked) setState(() => _blocked = true);
  }

  Future<void> _onSafetyAction(RoomSafetyAction action) async {
    final RoomCounterparty? cp = _counterparty;
    if (cp == null) return; // 상대 미확인 — 실행하지 않는다.
    switch (action) {
      case RoomSafetyAction.report:
        await reportRoomCounterparty(context,
            counterparty: cp, safety: widget.safety);
      case RoomSafetyAction.block:
        final bool ok = await confirmAndBlockRoomCounterparty(context,
            counterparty: cp, safety: widget.safety);
        if (ok && mounted) {
          setState(() => _blocked = true); // composer 비활성 — 기존 대화는 유지.
          await _refresh(); // 차단 후 room state 새로고침.
        }
    }
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

  /// N21 완결: 메시지 1페이지 크기 — 무제한 전량 조회 제거.
  static const int _messagesPageSize = 200;

  /// 이전 페이지가 더 있을 수 있는지(마지막 페이지가 한도만큼 꽉 찼는지).
  bool _hasEarlierMessages = false;

  Future<void> _load() async {
    try {
      // N21: 메시지·첨부는 독립 조회 — 병렬(종전 순차 2왕복 벽시계 절감).
      // 메시지는 최근 페이지만 — 이전 대화는 상단 버튼으로 명시 확장.
      final List<dynamic> loaded = await Future.wait(<Future<dynamic>>[
        _read.recentMessages(widget.thread.id, limit: _messagesPageSize),
        _loadAttachments(),
      ]);
      final List<QuestionMessage> msgs = loaded[0] as List<QuestionMessage>;
      final List<QuestionAttachment> atts =
          loaded[1] as List<QuestionAttachment>;
      if (!mounted) return;
      setState(() {
        _hasEarlierMessages = msgs.length >= _messagesPageSize;
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

  /// '이전 대화 불러오기' — 현재 가장 오래된 메시지 이전 1페이지를 합친다.
  Future<void> _loadEarlierMessages() async {
    final ThreadMessagesController? ctrl = _messages;
    if (ctrl == null || ctrl.isEmpty) return;
    try {
      // N21: 복합 커서(created_at, id) — 동일 시각 경계에서도 누락·중복 0.
      final List<QuestionMessage> older = await _read.messagesBefore(
        widget.thread.id,
        cursor: MessageCursor.oldestOf(ctrl.items),
        limit: _messagesPageSize,
      );
      // 일괄 병합(notify 1회) — 행별 notify 는 앵커 보정을 깨뜨린다.
      ctrl.upsertAllFromServer(older);
      if (mounted) {
        setState(() => _hasEarlierMessages = older.length >= _messagesPageSize);
      }
    } catch (_) {
      // 실패 시 조용히 유지 — 버튼이 남아 재시도 가능.
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
    // N21: 메시지·첨부 재조회 병렬화(메시지 실패는 조용히 무시 — 기존 목록 유지).
    // 최근 페이지를 merge(upsert)로 합친다 — resetTo 는 이미 불러온 이전
    // 페이지를 버리므로 금지(메시지는 삭제 경로가 없어 merge 가 안전).
    final Future<void> msgsF = _read
        .recentMessages(widget.thread.id, limit: _messagesPageSize)
        .then((List<QuestionMessage> msgs) {
      ctrl.upsertAllFromServer(msgs); // 일괄 병합(notify ≤1회)
    }).catchError((Object _) {});
    final Future<List<QuestionAttachment>> attsF = _loadAttachments();
    await msgsF;
    final List<QuestionAttachment> atts = await attsF;
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
    if (_blocked) {
      _showError(_blockedNotice); // append/첨부 RPC 호출 0회.
      return;
    }
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
    if (_blocked) return false; // 업로드 호출 0회(방어 — 진입은 이미 막힌다).
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
      // N21: 본문은 전송 시 서버 반환 행으로 이미 반영 — 첨부만 재조회.
      await _reloadAttachments();
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
    if (_blocked) {
      _showError(_blockedNotice); // 첨부 선택·업로드 진입 차단.
      return;
    }
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
        maxCount: kPdfMaxPagesPerPick, // [QA-B5] 여러 페이지를 고를 수 있다.
      );
      if (images.isEmpty) return;
      // [QA-B5] 대기 슬롯은 1장 전제다. 첫 장은 종전대로 미리보기에 올려
      // 주석·제거·본문 동봉을 그대로 쓰고, 나머지는 **순차 자동 전송**한다
      // (오너 판단 2026-08-07). 슬롯 UI 를 다중으로 바꾸는 것보다 변경이 작고,
      // 사용자가 고른 페이지가 조용히 1장으로 잘리는 일이 없어진다.
      await _acceptPicked(images.first);
      if (images.length > 1) {
        await _sendExtraPagesSequentially(images.sublist(1));
      }
    } catch (e) {
      // PDF 폴백 안내(AppError) 포함 — 원문 비노출 규약.
      _showError(friendlyError(e));
    }
  }

  /// [QA-B5] 첫 장을 뺀 나머지 페이지를 한 장씩 이어서 전송한다.
  ///
  /// 한 장이라도 실패하면 **거기서 멈추고** 몇 장이 갔는지 알린다 — 조용히
  /// 일부만 보내고 성공처럼 보이게 하지 않는다. 이미 올라간 장은 되돌리지
  /// 않는다(첨부는 되돌릴 대상이 아니라 대화에 남는 사실이다).
  Future<void> _sendExtraPagesSequentially(List<PickedImage> pages) async {
    if (pages.isEmpty || _sending) return;
    setState(() => _sending = true);
    int done = 0;
    try {
      for (final PickedImage page in pages) {
        final PickedImage img = await downscaleIfOversized(page);
        final String? invalid = validatePickedImage(img);
        if (invalid != null) {
          _showError('$invalid (${done + 1}번째 페이지에서 멈췄어요)');
          break;
        }
        final bool ok = await _uploadPending(img);
        if (!ok) {
          _showError('$done장까지 보냈어요. 나머지는 다시 시도해 주세요.');
          break;
        }
        done += 1;
      }
    } catch (e) {
      _showError('$done장까지 보냈어요. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (done > 0 && mounted) {
      _showError('페이지 $done장을 보냈어요.');
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
            padding: const EdgeInsets.only(right: 4),
            child: Center(child: ThreadStatusPill(status: _status)),
          ),
          RoomSafetyMenu(
            counterparty: _counterparty,
            blocked: _blocked,
            onSelected: _onSafetyAction,
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
            pendingImage: _blocked ? null : _pending,
            onRemovePending: () => setState(() => _pending = null),
            onAnnotate: _annotatePending,
            enabled: !_blocked,
            disabledNotice: _blocked ? _blockedNotice : null,
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
      hasEarlier: _hasEarlierMessages,
      onLoadEarlier: _loadEarlierMessages,
    );
  }
}
