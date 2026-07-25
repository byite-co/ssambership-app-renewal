import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/ink/ink_document.dart';
import '../../../core/refresh/data_refresh_bus.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/app_card.dart';
import '../../../design/widgets/primary_button.dart';
import '../../../design/widgets/secondary_button.dart';
import '../../../shared/format/formatters.dart';
import '../../../core/scan/picked_image.dart';
import '../../../core/scan/scan_source_picker.dart';
import '../../question_room/data/mentor_lookup_repository.dart';
import '../../question_room/ui/widgets/scan_source_sheet.dart';
import '../../scan_annotation/scan_annotation_screen.dart';
import '../data/individual_question_repository.dart';
import '../data/iq_annotation_repository.dart';
import '../data/iq_attachment_policy.dart';
import '../data/iq_attachment_saver.dart';
import '../data/iq_attachment_upload_core.dart';
import '../data/iq_attachment_url_resolver.dart';
import '../data/iq_attachments_repository.dart';
import '../data/models/individual_question_models.dart';
import 'widgets/iq_widgets.dart';
import '../../../shared/errors/app_error.dart';
import '../../../shared/errors/friendly_error.dart';

/// 상세 화면 데이터 묶음(질문 + 메시지 + 첨부 + 멘토 표시명).
class IqDetailData {
  const IqDetailData({
    required this.question,
    required this.messages,
    required this.attachments,
    this.mentorName,
  });

  final IndividualQuestion question;
  final List<IqMessage> messages;
  final List<IqAttachment> attachments;

  /// 학생 화면용 멘토 표시명(공개 RPC). 없으면 '멘토'.
  final String? mentorName;
}

/// 개별질문 상세 — 학생·멘토 공용. 역할·상태에 따라 액션이 달라진다.
/// - 학생: 답변 도착 → [해결 완료(정산)] / 답변 전 → [질문 취소(환불)]
/// - 멘토: 답변중(수락·지정) → 답변 작성
/// 변경이 있었으면 pop(true) 로 알린다(호출부 새로고침).
class IqDetailScreen extends StatefulWidget {
  const IqDetailScreen({
    super.key,
    required this.questionId,
    this.loaderOverride,
    this.roleOverride,
    this.annotationsOverride,
    this.annotateLauncherOverride,
    this.urlResolverOverride,
    this.repositoryOverride,
    this.attachmentsOverride,
    this.sourcePickerOverride,
    this.fileSaverOverride,
  });

  final String questionId;

  /// 테스트용 데이터 주입. null 이면 실제 레포 사용.
  final Future<IqDetailData> Function()? loaderOverride;

  /// 테스트용 역할 주입. null 이면 AuthService 의 현재 역할.
  final AppRole? roleOverride;

  /// 테스트용 첨삭 레포 주입(S18). null 이면 Supabase 기본.
  final IqAnnotationRepository? annotationsOverride;

  /// 테스트용 첨삭 화면 진입 오버라이드(S18) — 실 화면 push 회피.
  /// true 반환 = 새 첨부 전송됨(목록 새로고침).
  final Future<bool?> Function(IqAnnotateRequest request)?
      annotateLauncherOverride;

  /// 테스트용 서명 URL 리졸버 주입(P3-6). null 이면 Supabase 기본.
  final IqAttachmentUrlResolver? urlResolverOverride;

  /// 테스트용 레포 주입(환불/정산 계약 검증). null 이면 Supabase 기본.
  final IndividualQuestionRepository? repositoryOverride;

  /// 테스트용 첨부 업로드 포트 주입(§6). null 이면 Supabase 기본.
  final IqAttachmentsPort? attachmentsOverride;

  /// 테스트용 첨부 선택 소스 주입(§6 — 카메라/갤러리/파일). null 이면 실기기.
  final ScanSourcePort? sourcePickerOverride;

  /// 테스트용 저장 포트 주입(§6 — SAF 저장). null 이면 SAF 구현.
  final IqAttachmentSaverPort? fileSaverOverride;

  @override
  State<IqDetailScreen> createState() => _IqDetailScreenState();
}

/// 첨삭 화면 진입 요청(S18) — 배경 원본 + (있으면) 이어 그릴 스트로크.
class IqAnnotateRequest {
  const IqAnnotateRequest({
    required this.questionId,
    required this.sourceAttachmentId,
    required this.background,
    this.initial,
  });

  final String questionId;

  /// 첨삭 대상 원본 첨부 id — ink.json 경로의 키.
  final String sourceAttachmentId;

  /// 배경 원본 바이트.
  final Uint8List background;

  /// 이어 그리기 선택 시 복원할 기존 스트로크. null 이면 새로 시작.
  final InkDocument? initial;
}

class _IqDetailScreenState extends State<IqDetailScreen> {
  IndividualQuestionRepository get _repo =>
      widget.repositoryOverride ?? const IndividualQuestionRepository();
  IqAttachmentsPort get _attachments =>
      widget.attachmentsOverride ?? const SupabaseIqAttachmentsRepository();
  ScanSourcePort get _sourcePicker =>
      widget.sourcePickerOverride ?? const DeviceScanSourcePicker();
  IqAttachmentSaverPort get _fileSaver =>
      widget.fileSaverOverride ?? const SafIqAttachmentSaver();
  final MentorLookupRepository _mentorLookup = const MentorLookupRepository();
  final TextEditingController _answerController = TextEditingController();

  /// §6: 멘토 답변 첨부 대기열(업로드 실패분 재시도용 상태 포함).
  final List<_PendingIqUpload> _pendingUploads = <_PendingIqUpload>[];

  /// 서명 URL 리졸버(P3-6) — 화면 인스턴스 단위 캐시. 사용자 id 를 캐시 키에
  /// 포함하므로 계정이 바뀌어도 이전 사용자 URL 을 재사용하지 않는다.
  late final IqAttachmentUrlResolver _urlResolver =
      widget.urlResolverOverride ?? IqAttachmentUrlResolver.supabase();

  late Future<IqDetailData> _future;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<IqDetailData> _load() async {
    if (widget.loaderOverride != null) return widget.loaderOverride!();
    final IndividualQuestion? q = await _repo.fetch(widget.questionId);
    if (q == null) {
      throw Exception('질문을 찾을 수 없어요.');
    }
    final List<IqMessage> messages = await _repo.listMessages(q.id);
    final List<IqAttachment> attachments = await _repo.listAttachments(q.id);
    String? mentorName;
    final String? mentorId = q.mentorId;
    if (mentorId != null && _role == AppRole.student) {
      try {
        mentorName = (await _mentorLookup.fetch(mentorId))?.displayName;
      } catch (_) {
        mentorName = null; // 이름 조회 실패는 치명적이지 않다.
      }
    }
    return IqDetailData(
      question: q,
      messages: messages,
      attachments: attachments,
      mentorName: mentorName,
    );
  }

  // ★ 화살표 클로저(`=> _future = _load()`)는 Future 를 반환해 setState 의
  //   디버그 assert 에 걸린다(해결완료·환불·첨삭 후 새로고침이 전부 이 경로).
  // ★ 스테일 응답 방어: 새 Future 로 '교체'만 한다 — FutureBuilder 는 최신
  //   Future 의 결과만 반영하므로 이전 로드가 늦게 끝나도 화면을 덮지 않는다
  //   (수동 세대 토큰 불필요).
  void _refresh() {
    if (!mounted) return; // await 뒤 호출 경로 대비(P3-4).
    final Future<IqDetailData> next = _load();
    setState(() {
      _future = next;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String content, String okLabel) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    // P3-4: 확인 다이얼로그(await) 뒤에 진입한다 — dispose 후 setState 금지.
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      _refresh(); // 내부에서 mounted 를 확인한다.
    } catch (e) {
      _snack(iqFailureMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _release() async {
    final bool ok = await _confirm(
      '해결 완료할까요?',
      '확정하면 안전 보관 중이던 캐시가 멘토에게 정산돼요.\n이후에는 되돌릴 수 없어요.',
      '해결 완료',
    );
    if (!ok || !mounted) return;
    await _runAction(() async {
      await _repo.release(widget.questionId);
      // §4: 정산은 지갑·원장에 영향 — 교차 표면(마이페이지) 무효화 신호.
      DataRefreshBus.bumpWallet();
      _snack('해결 완료했어요. 안전 보관 중이던 캐시가 멘토에게 정산됐어요.');
    });
  }

  Future<void> _refund() async {
    final bool ok = await _confirm(
      '질문을 취소할까요?',
      '취소하면 안전 보관 중인 캐시가 지갑으로 돌아와요.',
      '질문 취소',
    );
    if (!ok || !mounted) return;
    await _runAction(() async {
      // P0-5: 공개 wrapper(refund_individual_question)만 호출. 로컬 선반영 없음 —
      // 성공/멱등(already_refunded)만 성공 취급, 그 외 ok=false 는 실패로 던진다.
      final IqEscrowResult r = await _repo.refund(widget.questionId);
      final bool alreadyRefunded = r.code.contains('already_refunded');
      if (!r.ok && !alreadyRefunded) {
        throw AppError(iqFailureMessage(r.code));
      }
      // §4: 환불 성공(멱등 포함) → 잔액·원장 교차 표면 무효화 신호.
      //    IQ 상세·목록은 _changed/_refresh 로, 지갑 표면은 이 신호로 재조회한다.
      DataRefreshBus.bumpWallet();
      _snack(alreadyRefunded ? '이미 환불된 질문이에요.' : '질문을 취소했어요. 캐시가 지갑으로 돌아왔어요.');
    });
  }

  /// 멘토 '첨삭하기'(S18) — 원본 바이트 + 기존 ink.json 을 준비해 첨삭 화면으로.
  /// 같은 원본의 기존 첨삭이 있으면 이어 그리기/새로 시작을 먼저 고른다.
  /// 완료 시 새 첨부가 하나 더 생긴다(원본 불변·덮어쓰기 금지, §11 기본안).
  Future<void> _annotateAttachment(IqAttachment attachment) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      final IqAnnotationRepository annotations =
          widget.annotationsOverride ?? IqAnnotationRepository.supabase();
      final Uint8List background =
          await annotations.downloadAttachment(attachment.storagePath);
      InkDocument? initial = await annotations.loadAnnotation(
        questionId: widget.questionId,
        sourceAttachmentId: attachment.id,
      );
      if (!mounted) return;
      if (initial != null) {
        final bool? resume = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('이전 첨삭이 있어요'),
            content: const Text('이 이미지에 남겨 둔 첨삭을 불러와 이어 그릴 수 있어요.\n'
                '완료하면 원본은 그대로 두고 새 첨삭본이 추가돼요.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('새로 시작'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('불러오기'),
              ),
            ],
          ),
        );
        if (resume == null || !mounted) return; // 뒤로가기 = 진입 취소.
        if (!resume) initial = null;
      }
      final IqAnnotateRequest request = IqAnnotateRequest(
        questionId: widget.questionId,
        sourceAttachmentId: attachment.id,
        background: background,
        initial: initial,
      );
      final bool? sent = await (widget.annotateLauncherOverride ??
          _pushAnnotationScreen)(request);
      if (sent == true && mounted) {
        _changed = true;
        _refresh();
        _snack('첨삭본을 새 첨부로 등록했어요. 원본은 그대로 있어요.');
      }
    } catch (e) {
      _snack('첨삭을 시작하지 못했어요. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 실제 첨삭 화면 push(테스트에서는 launcher 오버라이드로 대체).
  /// 기본 펜은 빨강 프리셋(§6-2).
  Future<bool?> _pushAnnotationScreen(IqAnnotateRequest request) {
    final IqAnnotationRepository annotations =
        widget.annotationsOverride ?? IqAnnotationRepository.supabase();
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ScanAnnotationScreen(
          background: request.background,
          initial: request.initial,
          title: '첨삭하기',
          initialPenColor: Colors.red,
          target: IqAnnotationTarget(
            repository: annotations,
            questionId: request.questionId,
            sourceAttachmentId: request.sourceAttachmentId,
          ),
        ),
      ),
    );
  }

  Future<void> _submitAnswer() async {
    final String body = _answerController.text.trim();
    if (body.isEmpty) {
      _snack('답변 내용을 입력해 주세요.');
      return;
    }
    final bool ok = await _confirm(
      '답변을 등록할까요?',
      '등록하면 학생에게 답변 도착으로 표시돼요.\n학생이 해결 완료를 누르면 정산 예정 금액으로 잡혀요.',
      '답변 등록',
    );
    if (!ok || !mounted) return;
    await _runAction(() async {
      await _repo.answer(widget.questionId, body);
      _answerController.clear();
      _snack('답변을 등록했어요.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('개별질문')),
        body: FutureBuilder<IqDetailData>(
          future: _future,
          builder: (BuildContext context, AsyncSnapshot<IqDetailData> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError || snap.data == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      '질문을 불러오지 못했어요.\n${friendlyError(snap.error ?? '')}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: ColorTokens.danger)),
                ),
              );
            }
            return _body(snap.data!);
          },
        ),
      ),
    );
  }

  AppRole get _role => widget.roleOverride ?? AuthService.instance.currentRole;

  Widget _body(IqDetailData data) {
    final IndividualQuestion q = data.question;
    final bool isStudent = _role == AppRole.student;
    final bool isMentor = _role == AppRole.mentor;
    final String? remaining = formatIqExpiryRemaining(q.expiresAt, q.status);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, 12, AppSpacing.screenH, 24),
      children: <Widget>[
        // 헤더: 유형·상태·가격·마감.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 컴플라이언스: 헤더에서 금액 표시 제거(유형·상태만).
              Row(
                children: <Widget>[
                  AppBadge(label: iqTypeLabel(q.type), tinted: true),
                  const SizedBox(width: 6),
                  IqStatusPill(status: q.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(q.title.isEmpty ? '(제목 없음)' : q.title,
                  style: AppTypography.title),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  if (isStudent)
                    Text(data.mentorName ?? '멘토', style: AppTypography.caption),
                  if (q.createdAt != null) ...<Widget>[
                    if (isStudent) const SizedBox(width: 8),
                    Text(Formatters.relativeKorean(q.createdAt!),
                        style: AppTypography.caption),
                  ],
                  if (remaining != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(remaining, style: AppTypography.caption),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 질문 본문.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('질문', style: AppTypography.caption),
              const SizedBox(height: 8),
              Text(q.body, style: AppTypography.body),
            ],
          ),
        ),
        if (data.attachments.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _AttachmentsCard(
            attachments: data.attachments,
            urlResolver: _urlResolver,
            // 첨삭 진입은 멘토만(§3). 학생의 전송 전 필기는 작성 화면 쪽.
            onAnnotate: isMentor && !_busy ? _annotateAttachment : null,
            // §6: 당사자 저장(다운로드) — RLS 가 당사자 외 접근을 차단한다.
            onSave: _saveAttachment,
          ),
        ],
        if (data.messages.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('답변', style: AppTypography.caption),
                for (final IqMessage m in data.messages) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(m.body, style: AppTypography.body),
                  if (m.createdAt != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(Formatters.relativeKorean(m.createdAt!),
                        style: AppTypography.caption),
                  ],
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        // 상태 안내 + 액션.
        if (isStudent) ..._studentActions(q),
        if (isMentor) ..._mentorActions(q),
      ],
    );
  }

  List<Widget> _studentActions(IndividualQuestion q) {
    final List<Widget> out = <Widget>[];
    if (iqAwaitingAnswer(q.status)) {
      out.add(const Text(
        '질문이 전달됐어요. 안전 보관 중인 캐시는 해결 완료를 누르기 전까지 보관돼요.',
        style: AppTypography.caption,
      ));
      out.add(const SizedBox(height: 10));
    }
    if (iqCanStudentRelease(q.status)) {
      out.add(PrimaryButton(
        label: '해결 완료 (멘토에게 정산)',
        onPressed: _busy ? null : _release,
      ));
      out.add(const SizedBox(height: 8));
    }
    if (iqCanStudentRefund(q.status)) {
      out.add(SecondaryButton(
        label: '질문 취소 (캐시 환불)',
        onPressed: _busy ? null : _refund,
      ));
    }
    if (q.status == IndividualQuestionStatus.released) {
      out.add(const Text(
        '해결 완료했어요. 안전 보관 중이던 캐시가 멘토에게 정산됐어요.',
        style: AppTypography.caption,
      ));
    }
    return out;
  }

  /// §6: 첨부 선택(카메라/갤러리/파일) → 정책 검증 → 즉시 업로드.
  /// 취소(null)는 조용히 종료, 검증 실패는 업로드 0 으로 안내만.
  Future<void> _pickAndUploadAttachment(String questionId) async {
    final ScanSource? source = await showScanSourceSheet(context);
    if (source == null || !mounted) return; // 선택 취소 안전
    final PickedImage? picked;
    try {
      picked = await _sourcePicker.pick(source);
    } catch (_) {
      _snack('파일을 불러오지 못했어요. 다시 시도해 주세요.');
      return;
    }
    if (picked == null || !mounted) return; // 선택 취소 안전
    final String? invalid = validateIqAttachmentFile(picked);
    if (invalid != null) {
      _snack(invalid); // 서버 계약 밖 — 업로드·등록 0
      return;
    }
    final _PendingIqUpload pending = _PendingIqUpload(picked);
    setState(() => _pendingUploads.add(pending));
    await _uploadPending(questionId, pending);
  }

  /// 단건 업로드(항목별 single-flight — 재시도 중복 0).
  Future<void> _uploadPending(String questionId, _PendingIqUpload p) async {
    if (p.uploading) return;
    setState(() {
      p.uploading = true;
      p.error = null;
    });
    try {
      await _attachments.upload(
        questionId: questionId,
        image: p.file,
        // 직전 시도에서 고아로 남은 경로가 있으면 재업로드 없이 등록만 재시도.
        existingObjectPath: p.retryObjectPath,
      );
      if (!mounted) return;
      setState(() => _pendingUploads.remove(p));
      _changed = true;
      _snack('첨부를 등록했어요.');
      _refresh(); // 첨부 목록 서버 재조회
    } on IqAttachmentRegisterFailure catch (f) {
      if (!mounted) return;
      setState(() {
        // 보상삭제 성공 → 처음부터(null), 실패(고아) → 같은 경로 재사용.
        p.retryObjectPath = f.retryObjectPath;
        p.error = f.message;
      });
    } on IqAttachmentAmbiguousResult catch (a) {
      if (!mounted) return;
      setState(() {
        // AMBIGUOUS_SERVER_RESULT — 자동삭제 0·성공 표시 0·임시 삽입 0.
        // 재시도는 같은 경로로 SELECT 선행 수렴을 다시 밟는다(RPC 선행 금지).
        p.retryObjectPath = a.retryObjectPath;
        p.error = a.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => p.error = friendlyError(e));
    } finally {
      if (mounted) setState(() => p.uploading = false);
    }
  }

  /// §6: 당사자 저장 — RLS 다운로드 + SAF 저장 대화상자(권한 요청 없음).
  Future<void> _saveAttachment(IqAttachment a) async {
    try {
      final bool saved = await _fileSaver.save(
        storagePath: a.storagePath,
        fileName: a.fileName ?? 'attachment',
      );
      if (saved) _snack('파일을 저장했어요.');
    } catch (_) {
      _snack('파일 저장에 실패했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  List<Widget> _mentorActions(IndividualQuestion q) {
    if (!iqCanMentorAnswer(q.status)) {
      if (q.status == IndividualQuestionStatus.answered) {
        return const <Widget>[
          Text('답변을 등록했어요. 학생이 해결 완료하면 정산 예정으로 잡혀요.',
              style: AppTypography.caption),
        ];
      }
      if (q.status == IndividualQuestionStatus.released) {
        return const <Widget>[
          Text('정산이 완료된 질문이에요.', style: AppTypography.caption),
        ];
      }
      return const <Widget>[];
    }
    return <Widget>[
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('답변 작성', style: AppTypography.caption),
            const SizedBox(height: 8),
            TextField(
              controller: _answerController,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: '학생이 이해할 수 있게 풀이 과정을 함께 적어 주세요.',
                border: OutlineInputBorder(),
              ),
            ),
            // §6: 답변 첨부(이미지·카메라·파일) — 선택 즉시 업로드,
            // 실패분은 아래 목록에 남아 재시도(중복 업로드 0).
            for (final _PendingIqUpload p in _pendingUploads) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(
                    p.error == null
                        ? Icons.attach_file
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: p.error == null
                        ? ColorTokens.secondary
                        : ColorTokens.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${p.file.fileName} (${_formatBytes(p.file.bytes.length)})',
                          style: AppTypography.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (p.error != null)
                          Text(p.error!,
                              style: AppTypography.caption
                                  .copyWith(color: ColorTokens.danger)),
                      ],
                    ),
                  ),
                  if (p.uploading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (p.error != null)
                    TextButton(
                      onPressed: () => _uploadPending(q.id, p),
                      child: const Text('재시도'),
                    ),
                  if (!p.uploading)
                    IconButton(
                      tooltip: '제거',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () =>
                          setState(() => _pendingUploads.remove(p)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            SecondaryButton(
              label: '파일 첨부',
              icon: Icons.attach_file,
              onPressed: _busy ? null : () => _pickAndUploadAttachment(q.id),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: '답변 등록',
              onPressed: _busy ? null : _submitAnswer,
            ),
          ],
        ),
      ),
    ];
  }
}

/// §6: 멘토 답변 첨부 대기 항목(업로드 상태·재시도 경로).
class _PendingIqUpload {
  _PendingIqUpload(this.file);

  final PickedImage file;
  bool uploading = false;
  String? error;

  /// 등록 실패 + 보상삭제 실패(고아) 시의 재시도 경로 — 재업로드 생략용.
  String? retryObjectPath;
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${bytes}B';
}

/// 첨부 카드 — 이미지는 서명 URL 로 인라인 표시, 그 외 파일은 이름만.
/// [onAnnotate] 가 있으면(멘토) 이미지 첨부마다 '첨삭하기'를 노출한다(S18).
/// [onSave] 가 있으면 항목마다 '저장'(당사자 다운로드 → SAF)을 노출한다(§6).
///
/// ★ P3-6: Future 는 storage_path 별로 상태에 메모한다 — build 마다 새
///   Future 를 만들던 이전 방식은 리빌드마다 서명 URL 을 재요청했다.
///   리졸버 캐시(만료 전 재사용)와 이중으로 재요청을 막는다.
class _AttachmentsCard extends StatefulWidget {
  const _AttachmentsCard({
    required this.attachments,
    required this.urlResolver,
    this.onAnnotate,
    this.onSave,
  });

  final List<IqAttachment> attachments;
  final IqAttachmentUrlResolver urlResolver;
  final void Function(IqAttachment attachment)? onAnnotate;

  /// §6: 항목 저장(당사자 다운로드 → SAF). null 이면 버튼 미노출.
  final void Function(IqAttachment attachment)? onSave;

  @override
  State<_AttachmentsCard> createState() => _AttachmentsCardState();
}

class _AttachmentsCardState extends State<_AttachmentsCard> {
  /// storage_path → 진행 중/완료 Future 메모(리빌드 시 재사용).
  final Map<String, Future<String>> _urlFutures = <String, Future<String>>{};

  bool _isImage(IqAttachment a) =>
      (a.mimeType ?? '').toLowerCase().startsWith('image/');

  /// 서명 URL 조회 — async 래핑으로 동기 throw(클라이언트 부재 등)도
  /// FutureBuilder 의 에러 분기로 흘린다(빌드 크래시 방지).
  /// 실패한 Future 는 메모에서 비운다 — 다음 리빌드/새로고침이 재시도한다
  /// (실패를 남겨 두면 재시도가 영영 막힌다).
  Future<String> _signedUrl(IqAttachment a) =>
      _urlFutures.putIfAbsent(a.storagePath, () {
        final Future<String> future =
            Future<String>(() => widget.urlResolver.signedUrl(a.storagePath));
        future.then<void>((_) {}, onError: (Object _) {
          if (identical(_urlFutures[a.storagePath], future)) {
            _urlFutures.remove(a.storagePath);
          }
        });
        return future;
      });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('첨부', style: AppTypography.caption),
          for (final IqAttachment a in widget.attachments) ...<Widget>[
            const SizedBox(height: 8),
            if (_isImage(a)) ...<Widget>[
              FutureBuilder<String>(
                future: _signedUrl(a),
                builder: (BuildContext context, AsyncSnapshot<String> snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError || snap.data == null) {
                    return const Text('이미지를 불러오지 못했어요.',
                        style: AppTypography.caption);
                  }
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => _IqAttachmentViewer(
                          url: snap.data!,
                          title: a.fileName ?? '첨부 이미지',
                          onAnnotate: widget.onAnnotate == null
                              ? null
                              : () => widget.onAnnotate!(a),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        snap.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Text(
                          '이미지를 불러오지 못했어요.',
                          style: AppTypography.caption,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (widget.onAnnotate != null || widget.onSave != null)
                Row(
                  children: <Widget>[
                    if (widget.onAnnotate != null)
                      TextButton.icon(
                        onPressed: () => widget.onAnnotate!(a),
                        icon: const Icon(Icons.draw_rounded, size: 18),
                        label: const Text('첨삭하기'),
                      ),
                    if (widget.onSave != null)
                      TextButton.icon(
                        onPressed: () => widget.onSave!(a),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('저장'),
                      ),
                  ],
                ),
            ] else
              Row(
                children: <Widget>[
                  const Icon(Icons.attach_file,
                      size: 18, color: ColorTokens.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      a.fileName ?? '첨부 파일',
                      style: AppTypography.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // §6: 구 '웹에서 확인' 폐기 — 앱에서 당사자 저장 지원.
                  if (widget.onSave != null)
                    TextButton.icon(
                      onPressed: () => widget.onSave!(a),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('저장'),
                    )
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// 첨부 전체화면 뷰어(줌·팬). [onAnnotate] 가 있으면(멘토, S18) '첨삭하기'를
/// 노출한다 — 뷰어를 닫고 상세 화면의 첨삭 흐름으로 넘긴다.
/// ★ 질문방 AttachmentViewerScreen 은 roomId/threadId 에 결합돼 있어
///   재사용하지 않는다(전송은 AnnotationTarget 포트가 담당).
class _IqAttachmentViewer extends StatelessWidget {
  const _IqAttachmentViewer({
    required this.url,
    required this.title,
    this.onAnnotate,
  });

  final String url;
  final String title;
  final VoidCallback? onAnnotate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (onAnnotate != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop(); // 뷰어를 닫고 첨삭 흐름으로.
                onAnnotate!();
              },
              icon: const Icon(Icons.draw_rounded, color: Colors.white),
              label: const Text('첨삭하기', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text(
              '이미지를 불러오지 못했어요.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
