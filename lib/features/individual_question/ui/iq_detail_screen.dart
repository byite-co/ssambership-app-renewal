import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/ink/ink_document.dart';
import '../../../core/refresh/data_refresh_bus.dart';
import '../../../core/scan/image_downscaler.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/conversation_ui/conversation_bubble.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/primary_button.dart';
import '../../../design/widgets/secondary_button.dart';
import '../../../shared/format/formatters.dart';
import '../../../core/scan/picked_image.dart';
import '../../../core/scan/scan_source_picker.dart';
import '../../question_room/data/mentor_lookup_repository.dart';
import '../../question_room/ui/widgets/scan_source_sheet.dart';
import '../../scan_annotation/annotation_target.dart';
import '../../scan_annotation/scan_annotation_screen.dart';
import '../data/individual_question_repository.dart';
import '../data/iq_annotation_repository.dart';
import '../data/iq_attachment_grouping.dart';
import '../data/iq_attachment_policy.dart';
import '../data/iq_attachment_saver.dart';
import '../data/iq_attachment_upload_core.dart';
import '../data/iq_attachment_url_resolver.dart';
import '../data/iq_attachments_repository.dart';
import '../data/iq_error_mapper.dart';
import '../data/iq_messages_controller.dart';
import '../data/iq_realtime.dart';
import '../data/models/individual_question_models.dart';
import 'widgets/iq_widgets.dart';
import '../../../shared/errors/app_error.dart';
import '../../../shared/widgets/screen_visibility.dart';
import '../../../shared/errors/friendly_error.dart';

/// 상세 화면 데이터 묶음(질문 + 메시지 + 첨부 + 멘토 표시명).
///
/// 첨부는 [groups] 로 **한 번만** 귀속 그룹화된다(매 build 검색 금지) —
/// message_id 연결 그룹 / 최초 질문(학생 작성·미연결) / 멘토 작성·미연결 /
/// 작성자 미확인 레거시(중립).
class IqDetailData {
  IqDetailData({
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

  /// 첨부 귀속 그룹(1회 계산·이후 재사용).
  late final IqAttachmentGroups groups = IqAttachmentGroups.build(
    attachments: attachments,
    messages: messages,
    studentId: question.studentId,
    mentorId: question.mentorId,
  );
}

/// 개별질문 상세 — 학생·멘토 공용. **화면 전체가 대화방이다**(vc11 정본 UX).
///
/// 구조: [컴팩트 헤더] → [Expanded 대화 타임라인] → [하단 고정 액션/작성 영역].
/// 최초 질문(제목·본문·학생 첨부)이 타임라인의 첫 학생 항목으로 들어가고, 이후
/// IqMessage 가 작성순으로 이어진다. **각 메시지의 첨부는 그 메시지 말풍선에
/// 붙는다**(message_id 귀속 — 전체 첨부를 질문 말풍선에 합치지 않는다).
/// 계약: test/individual_question/iq_fullscreen_chat_test.dart ·
///       iq_media_attribution_test.dart.
///
/// 역할·상태별 액션은 하단 영역에 고정된다:
/// - 학생: 답변 도착 → [해결 완료(정산)] / 답변 전 → [질문 취소(환불)]
/// - 멘토: 답변중(수락·지정) → 답변 작성 / 답변 도착 → 추가 답글
/// 신규 첨부는 대기열에 쌓였다가 **메시지 생성 후 반환된 message_id 로 등록**된다
/// (§2-2 — 최근접 조회·낙관적 임시 id·선등록 금지).
/// 변경이 있었으면 pop(true) 로 알린다(호출부 새로고침).
class IqDetailScreen extends StatefulWidget {
  const IqDetailScreen({
    super.key,
    required this.questionId,
    this.loaderOverride,
    this.roleOverride,
    this.annotationsOverride,
    this.annotateLauncherOverride,
    this.pendingAnnotateOverride,
    this.urlResolverOverride,
    this.repositoryOverride,
    this.attachmentsOverride,
    this.sourcePickerOverride,
    this.fileSaverOverride,
    this.currentUserId,
    this.realtimeFactoryOverride,
  });

  final String questionId;

  /// 내 사용자 id 오버라이드(테스트용). null 이면 Supabase 세션에서 얻는다.
  /// 좌우 거울상 정렬에만 쓰이며, 학생·멘토 작성자 판정에는 필요 없다
  /// (그건 질문 행의 당사자 id 로 결정된다).
  final String? currentUserId;

  /// 테스트용 데이터 주입. null 이면 실제 레포 사용.
  final Future<IqDetailData> Function()? loaderOverride;

  /// 테스트용 역할 주입. null 이면 AuthService 의 현재 역할.
  final AppRole? roleOverride;

  /// 테스트용 첨삭 레포 주입(S18). null 이면 Supabase 기본.
  final IqAnnotationRepository? annotationsOverride;

  /// 테스트용 첨삭 화면 진입 오버라이드(S18) — 실 화면 push 회피.
  /// 완료 결과(문서+평탄화 PNG)를 돌려주면 대기 첨부로 추가된다. null = 취소.
  final Future<AnnotationResult?> Function(IqAnnotateRequest request)?
      annotateLauncherOverride;

  /// 테스트용 '전송 전 필기' 화면 오버라이드 — 대기 첨부(로컬 이미지)에 주석.
  final Future<AnnotationResult?> Function(
      PickedImage background, InkDocument? initial)? pendingAnnotateOverride;

  /// 테스트용 서명 URL 리졸버 주입(P3-6). null 이면 Supabase 기본.
  final IqAttachmentUrlResolver? urlResolverOverride;

  /// 테스트용 레포 주입(환불/정산/메시지 계약 검증). null 이면 Supabase 기본.
  final IndividualQuestionRepository? repositoryOverride;

  /// 테스트용 첨부 업로드 포트 주입(§6). null 이면 Supabase 기본.
  final IqAttachmentsPort? attachmentsOverride;

  /// 테스트용 첨부 선택 소스 주입(§6 — 카메라/갤러리/파일). null 이면 실기기.
  final ScanSourcePort? sourcePickerOverride;

  /// 테스트용 저장 포트 주입(§6 — SAF 저장). null 이면 SAF 구현.
  final IqAttachmentSaverPort? fileSaverOverride;

  /// 테스트용 실시간 포트 팩토리 주입. null 이면 Supabase 구현
  /// (백엔드 미연결이면 조용히 no-op — 폴백 재조회만 동작).
  final IqRealtimePort Function(String questionId)? realtimeFactoryOverride;

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

class _IqDetailScreenState extends State<IqDetailScreen>
    with WidgetsBindingObserver, ResumeVisibilityGate {
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

  /// 당사자 공용 대화 컴포저(iq_append_message — 학생 후속·멘토 추가 답글).
  /// 본문이 비면 전송 버튼을 비활성화한다(첨부만 보내는 전송은 없다 — 첨부는
  /// 메시지 생성 후 그 message_id 로 등록된다).
  final TextEditingController _chatController = TextEditingController();
  bool _chatCanSend = false;

  /// 대화 타임라인 스크롤(수명은 이 State 가 소유·정리한다).
  final ScrollController _timelineScroll = ScrollController();

  /// 대화 메시지 정본 뷰 — 서버 재조회(resetTo)와 실시간 수신(upsert)이 여기로
  /// 수렴한다(dedup-by-id — 중복 이벤트가 와도 중복 행 0).
  final IqMessagesController _messages = IqMessagesController();

  /// 실시간 채널(iq_{questionId}) — 보조 채널. 실패해도 화면은 기존 데이터 +
  /// 전송 후 재조회/수동 새로고침으로 계속 동작한다.
  IqRealtimePort? _realtime;

  /// 최신 대화로 내려보낼 필요가 있을 때만 참 — 최초 진입, 그리고 내가 방금
  /// 답변을 등록한 직후. 그 외 새로고침(첨삭·환불·정산)은 사용자가 보고 있던
  /// 스크롤 위치를 지키느라 건드리지 않는다(§7 예측 가능성).
  bool _scrollToLatestOnData = true;

  /// §6·§2-2: 첨부 대기열 — 선택·첨삭 결과가 여기 쌓였다가 메시지 전송 시
  /// 반환된 message_id 로 업로드·등록된다. 실패분은 messageId·고아 경로를
  /// 보존한 채 남아 재시도한다(메시지 재생성 0·중복 객체 0).
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
    _chatController.addListener(_onChatChanged);
    // §G: 실시간 보조 채널 + 복귀 재조회(실시간이 유일 소스가 되지 않게).
    _startRealtime();
    WidgetsBinding.instance.addObserver(this);
    AuthService.instance.addListener(_onAuthChanged);
  }

  @override
  void didUpdateWidget(IqDetailScreen old) {
    super.didUpdateWidget(old);
    // 질문 전환 — 이전 질문 채널을 반드시 정리하고 새 질문으로 재구독.
    if (old.questionId != widget.questionId) {
      _realtime?.dispose();
      _realtime = null;
      _messages.resetTo(const <IqMessage>[], notify: false);
      _pendingUploads.clear();
      _startRealtime();
      _refresh(scrollToLatest: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱 복귀 — 백그라운드 동안의 이벤트 공백을 전체 재조회로 메운다(N19 코얼레싱).
    if (state == AppLifecycleState.resumed) handleResumed();
  }

  // N12: 보일 때만 재조회(첨부 뷰어 등이 덮여 있으면 재노출 시 1회).
  @override
  void onResumeRefresh() {
    _coalescedRefresh();
  }

  /// 로그아웃/계정 전환 — 이전 사용자 채널을 정리한다(구독 누수·오배달 방지).
  void _onAuthChanged() {
    if (AuthService.instance.isSignedIn) return;
    _realtime?.dispose();
    _realtime = null;
  }

  void _onChatChanged() {
    final bool can = _chatController.text.trim().isNotEmpty;
    if (can != _chatCanSend && mounted) {
      setState(() => _chatCanSend = can);
    }
  }

  void _startRealtime() {
    final IqRealtimePort rt = (widget.realtimeFactoryOverride ??
        SupabaseIqRealtime.new)(widget.questionId);
    _realtime = rt;
    rt.start(
      // 새 메시지 → id 기준 upsert(중복 이벤트가 와도 중복 행 0). 서버 행이
      // 정본이라 재조회 결과와도 자연 수렴한다.
      onMessageInsert: (IqMessage m) {
        if (!mounted) return;
        _messages.upsertFromServer(m);
        // N36: 귀속 그룹은 로드 스냅샷에서 1회 계산이라 스스로 안 움직인다 —
        // 이 메시지 귀속인데 '연결 메시지 미확인'에 남은 첨부가 있으면
        // 재조회로 재귀속한다(N19 코얼레싱 경유 — 폭주 없음).
        final IqDetailData? d = _lastData;
        if (d != null &&
            d.groups.unresolvedMessage
                .any((IqAttachment a) => a.messageId == m.id)) {
          _coalescedRefresh();
        }
      },
      // 질문 행 변경(answered 전이 등) → 상태·액션 게이트 재조회(N19 코얼레싱).
      onQuestionUpdate: () {
        if (mounted) _coalescedRefresh();
      },
      // 첨부 행 생성 → 첨부 목록 서버 재조회(실시간 payload 를 정본으로 쓰지
      // 않는다 — 서명 URL·귀속 그룹·정렬은 재조회가 담당. 재조회는 그룹을
      // 통째로 다시 만들므로 중복 표시 0). N19 코얼레싱.
      onAttachmentInsert: () {
        if (mounted) _coalescedRefresh();
      },
      // 재연결 — 끊긴 사이 공백을 전체 재조회로 메운다(N19 코얼레싱).
      onReconnected: () {
        if (mounted) _coalescedRefresh();
      },
    );
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    _realtime?.dispose();
    _messages.dispose();
    _answerController.dispose();
    _chatController.dispose();
    _timelineScroll.dispose();
    super.dispose();
  }

  /// 마지막으로 로드된 스냅샷(N36 — 실시간 메시지 도착 시 미해결 첨부
  /// 재귀속 판정용). 표시는 여전히 FutureBuilder(_future)가 정본이다.
  IqDetailData? _lastData;

  Future<IqDetailData> _load() async {
    final IqDetailData data = await _loadRaw();
    // 서버 목록이 대화 정본 — 실시간 수신분과 id 로 합쳐진 뷰를 갱신한다.
    // (notify 는 FutureBuilder 리빌드가 대신한다 — build 중 재통지 방지.)
    _messages.resetTo(data.messages, notify: false);
    _lastData = data;
    return data;
  }

  Future<IqDetailData> _loadRaw() async {
    if (widget.loaderOverride != null) return widget.loaderOverride!();
    // C22: 질문·메시지·첨부는 전부 questionId 로 독립 조회 — 병렬로 묶는다
    // (RT 수신·재연결·앱 복귀마다 재실행되는 경로라 벽시계 절감 폭이 크다).
    final List<dynamic> loaded = await Future.wait(<Future<dynamic>>[
      _repo.fetch(widget.questionId),
      _repo.listMessages(widget.questionId),
      _repo.listAttachments(widget.questionId),
    ]);
    final IndividualQuestion? q = loaded[0] as IndividualQuestion?;
    if (q == null) {
      throw Exception('질문을 찾을 수 없어요.');
    }
    final List<IqMessage> messages = loaded[1] as List<IqMessage>;
    final List<IqAttachment> attachments = loaded[2] as List<IqAttachment>;
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
  void _refresh({bool scrollToLatest = false}) {
    if (!mounted) return; // await 뒤 호출 경로 대비(P3-4).
    if (scrollToLatest) _scrollToLatestOnData = true;
    final Future<IqDetailData> next = _load();
    setState(() {
      _future = next;
    });
  }

  // N19: 실시간 이벤트 버스트(질문 UPDATE + 첨부 INSERT 연쇄·재연결 등)마다
  // 3쿼리 전체 재조회가 중첩 발화하지 않게 — 진행 중 1 + 종료 후 후행 1 로
  // 수렴한다. 사용자 액션(해결완료·환불·전송 후) 재조회는 즉시성 우선이라
  // 기존 _refresh 그대로.
  bool _rtRefreshing = false;
  bool _rtRefreshQueued = false;

  void _coalescedRefresh() {
    if (!mounted) return;
    if (_rtRefreshing) {
      _rtRefreshQueued = true;
      return;
    }
    _rtRefreshing = true;
    final Future<IqDetailData> next = _load().whenComplete(() {
      _rtRefreshing = false;
      if (_rtRefreshQueued) {
        _rtRefreshQueued = false;
        _coalescedRefresh();
      }
    });
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

  Future<void> _runAction(
    Future<void> Function() action, {
    bool scrollToLatest = false,
  }) async {
    // P3-4: 확인 다이얼로그(await) 뒤에 진입한다 — dispose 후 setState 금지.
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      _refresh(scrollToLatest: scrollToLatest); // 내부에서 mounted 를 확인한다.
    } catch (e) {
      // 구조화 코드(iq_error_mapper) 우선 → 레거시 포함 매칭 폴백. 코드 비노출.
      _snack(iqActionFailureText(e));
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

  /// 멘토 '첨삭하기'(S18·§4-3) — 원본 바이트 + 기존 ink.json 을 준비해 첨삭
  /// 화면으로. 같은 원본의 기존 첨삭이 있으면 이어 그리기/새로 시작을 고른다.
  ///
  /// 완료 결과는 **즉시 등록하지 않는다** — ink.json 만 원본 첨부 id 경로에
  /// 저장(이어 그리기 유지)하고, 평탄화 PNG 는 멘토 작성 영역의 대기 첨부로
  /// 들어간다. 답변/추가 답글 전송 시 그 멘토 message_id 로 등록된다
  /// (원본 불변·미연결 첨부 생성 0).
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
                '완료하면 원본은 그대로 두고 새 첨삭본이 만들어져요.'),
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
      final AnnotationResult? result = await (widget.annotateLauncherOverride ??
          _pushAnnotationScreen)(request);
      if (result == null || !mounted) return; // 취소/빈 주석 — 변화 없음.

      // 이어 그리기 원본(ink.json) upsert — 첨부 행 없음·원본 불변.
      await annotations.saveDocument(
        questionId: widget.questionId,
        sourceAttachmentId: attachment.id,
        document: result.document,
      );

      // 평탄화 PNG → 대기 첨부(§6-4 크기 규약 통과). 전송 시 멘토 메시지에 연결.
      final String source = attachment.fileName ?? 'annotation';
      final int dot = source.lastIndexOf('.');
      final String base = dot <= 0 ? source : source.substring(0, dot);
      final PickedImage flattened = await downscaleIfOversized(PickedImage(
        bytes: result.flattenedPng,
        fileName: '$base-ink.png',
        mimeType: 'image/png',
      ));
      final String? invalid = validateIqAttachmentFile(flattened);
      if (invalid != null) {
        _snack(invalid);
        return;
      }
      if (!mounted) return;
      setState(() => _pendingUploads.add(_PendingIqUpload(flattened)));
      _snack('첨삭본을 첨부 대기 목록에 추가했어요. 답글을 보내면 함께 등록돼요.');
    } catch (e) {
      _snack('첨삭을 시작하지 못했어요. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 실제 첨삭 화면 push(테스트에서는 launcher 오버라이드로 대체).
  /// 기본 펜은 빨강 프리셋(§6-2). 완료 결과는 로컬 캡처로만 받는다(즉시 전송 0).
  Future<AnnotationResult?> _pushAnnotationScreen(
      IqAnnotateRequest request) async {
    final LocalAnnotationTarget target = LocalAnnotationTarget();
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ScanAnnotationScreen(
          background: request.background,
          initial: request.initial,
          title: '첨삭하기',
          initialPenColor: Colors.red,
          target: target,
        ),
      ),
    );
    return done == true ? target.result : null;
  }

  /// 전송 전 필기(학생·멘토 공용) — 대기 첨부(로컬 이미지)에 주석을 달고
  /// 평탄화본으로 교체한다(업로드 전 단계 — iq_create_screen 과 동일 규약).
  /// 재진입 시 보관해 둔 원본+스트로크로 이어 그린다.
  Future<void> _annotatePending(_PendingIqUpload p) async {
    if (_busy || p.uploading || !mounted) return;
    final PickedImage background = p.original ?? p.file;
    final AnnotationResult? result = await (widget.pendingAnnotateOverride ??
        _pushPendingAnnotationScreen)(background, p.inkDocument);
    if (result == null || !mounted) return;

    final int dot = background.fileName.lastIndexOf('.');
    final String base = dot <= 0
        ? background.fileName
        : background.fileName.substring(0, dot);
    final PickedImage flattened = await downscaleIfOversized(PickedImage(
      bytes: result.flattenedPng,
      fileName: '$base-ink.png',
      mimeType: 'image/png',
    ));
    final String? invalid = validateIqAttachmentFile(flattened);
    if (invalid != null) {
      _snack(invalid);
      return;
    }
    if (!mounted) return;
    setState(() {
      p.file = flattened; // 평탄화본이 슬롯 대체(원본은 이어 그리기용 보관).
      p.original = background;
      p.inkDocument = result.document;
    });
  }

  Future<AnnotationResult?> _pushPendingAnnotationScreen(
      PickedImage background, InkDocument? initial) async {
    final LocalAnnotationTarget target = LocalAnnotationTarget();
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ScanAnnotationScreen(
          background: background.bytes,
          initial: initial,
          target: target,
          title: '필기하기',
        ),
      ),
    );
    return done == true ? target.result : null;
  }

  /// 멘토 첫 답변 — `iq_append_message` 로 본문 등록과 answered 전이를
  /// **원자적으로** 완료하고, 반환된 message_id 로 대기 첨부를 등록한다(§2-2).
  /// 첨부 일부가 실패해도 메시지를 다시 만들지 않는다 — 실패분은 같은
  /// message_id·같은 고아 경로로 재시도한다.
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
    // 방금 등록한 내 답변은 타임라인 끝에 붙는다 — 이때만 끝으로 내려보낸다.
    await _runAction(scrollToLatest: true, () async {
      final IqAppendResult r =
          await _repo.appendMessage(widget.questionId, body);
      _answerController.clear();
      final int failed = await _flushPendingUploads(r.messageId);
      _snack(failed == 0
          ? '답변을 등록했어요.'
          : '답변을 등록했어요. 첨부 $failed건은 등록하지 못했어요 — 아래에서 다시 시도해 주세요.');
    });
  }

  /// 후속 메시지 전송(학생·멘토 공용, iq_append_message) — 성공 후 반환된
  /// message_id 로 대기 첨부를 등록하고 서버 재조회가 정본(로컬 선반영 없음).
  /// 실시간 INSERT 가 먼저 와도 재조회와 id 로 수렴한다(중복 행 0).
  Future<void> _sendChatMessage() async {
    final String body = _chatController.text.trim();
    if (body.isEmpty || _busy) return;
    await _runAction(scrollToLatest: true, () async {
      final IqAppendResult r =
          await _repo.appendMessage(widget.questionId, body);
      _chatController.clear();
      final int failed = await _flushPendingUploads(r.messageId);
      if (failed > 0) {
        _snack('첨부 $failed건은 등록하지 못했어요 — 아래에서 다시 시도해 주세요.');
      }
    });
  }

  /// 대기 첨부 전체를 [messageId] 로 업로드·등록한다. 반환 = 실패 건수.
  /// 이미 특정 메시지에 묶인 실패분(재시도 대기)은 그 message_id 를 유지한다 —
  /// 새 메시지로 옮겨 붙이지 않는다(귀속 불변).
  Future<int> _flushPendingUploads(String messageId) async {
    final List<_PendingIqUpload> targets =
        List<_PendingIqUpload>.of(_pendingUploads);
    int failed = 0;
    for (final _PendingIqUpload p in targets) {
      p.messageId ??= messageId;
      await _uploadPending(widget.questionId, p);
      if (_pendingUploads.contains(p)) failed++; // 성공 시 목록에서 제거된다.
    }
    return failed;
  }

  /// §6·§2-2: 첨부 선택(카메라/갤러리/파일) → 정책 검증 → **대기열 추가**.
  /// 업로드는 하지 않는다 — 메시지 전송이 반환한 message_id 로만 등록한다
  /// (message_id = null 선등록 금지). 취소(null)는 조용히 종료.
  Future<void> _pickPendingAttachment() async {
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
      _snack(invalid); // 서버 계약 밖 — 대기열 추가 0
      return;
    }
    final _PendingIqUpload pending = _PendingIqUpload(picked);
    setState(() => _pendingUploads.add(pending));
  }

  /// 단건 업로드(항목별 single-flight — 재시도 중복 0). 메시지에 묶인 뒤에만
  /// 호출된다([_PendingIqUpload.messageId] 필수 — 미연결 등록 금지).
  Future<void> _uploadPending(String questionId, _PendingIqUpload p) async {
    if (p.uploading) return;
    final String? messageId = p.messageId;
    if (messageId == null) return; // 메시지 생성 전 — 등록 경로 없음(방어).
    setState(() {
      p.uploading = true;
      p.error = null;
    });
    try {
      await _attachments.upload(
        questionId: questionId,
        image: p.file,
        // §2-2: 메시지 생성이 돌려준 id 정본 — 최근접 조회·임시 id 금지.
        messageId: messageId,
        // 직전 시도에서 고아로 남은 경로가 있으면 재업로드 없이 등록만 재시도.
        existingObjectPath: p.retryObjectPath,
      );
      if (!mounted) return;
      setState(() => _pendingUploads.remove(p));
      _changed = true;
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        // 첨부 대기열은 화면 수명 로컬 상태다 — 나가면 사라진다. 특히 메시지는
        // 이미 전송됐는데 첨부만 실패해 재시도 대기 중인 항목이 있으면, 조용히
        // 유실되지 않게 확인을 받는다(§4-3 재시도 계약의 UX 이면).
        if (_pendingUploads.isEmpty) {
          Navigator.of(context).pop(_changed);
          return;
        }
        _confirmLeaveWithPending();
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
            final IqDetailData data = snap.data!;
            _scheduleScrollToLatest(data);
            return _body(data);
          },
        ),
      ),
    );
  }

  /// 대기 첨부가 있는 채로 나가려 할 때의 확인 — 전송된 메시지는 유지되고
  /// 보내지 않은/실패한 첨부만 사라진다는 사실을 명시한다.
  Future<void> _confirmLeaveWithPending() async {
    final bool ok = await _confirm(
      '보내지 않은 첨부가 있어요',
      '화면을 나가면 대기 중인 첨부는 사라져요.\n이미 보낸 메시지는 그대로 남아요.',
      '나가기',
    );
    if (ok && mounted) Navigator.of(context).pop(_changed);
  }

  AppRole get _role => widget.roleOverride ?? AuthService.instance.currentRole;

  /// 뷰어 uid. Supabase 미초기화(위젯 테스트)면 null → 거울상 없이 전부 좌측.
  String? get _viewerId =>
      widget.currentUserId ?? SupabaseInit.clientOrNull?.auth.currentUser?.id;

  /// §7 초기 위치: 메시지가 있으면 최신 대화 근처에서 시작한다. 질문만 있으면
  /// 맨 위(질문)가 자연스러운 시작점이라 건드리지 않는다. build 중에는 플래그만
  /// 내리고 실제 점프는 프레임 뒤로 미룬다.
  void _scheduleScrollToLatest(IqDetailData data) {
    if (!_scrollToLatestOnData || data.messages.isEmpty) return;
    _scrollToLatestOnData = false;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _jumpTimelineToEnd(retriesLeft: 4));
  }

  /// 끝으로 점프. ListView 의 children 지연 레이아웃 때문에 maxScrollExtent 가
  /// 추정치일 수 있어, 실제 끝에 닿을 때까지 몇 프레임 재시도한다(상한 고정 —
  /// 초기 진입 직후에만 도는 짧은 수렴 루프).
  void _jumpTimelineToEnd({required int retriesLeft}) {
    if (!mounted || !_timelineScroll.hasClients) return;
    final ScrollPosition p = _timelineScroll.position;
    if (p.pixels >= p.maxScrollExtent) return;
    _timelineScroll.jumpTo(p.maxScrollExtent);
    if (retriesLeft > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpTimelineToEnd(retriesLeft: retriesLeft - 1));
    }
  }

  /// 화면 전체 = 대화방: [컴팩트 헤더] → [Expanded 타임라인] → [하단 고정 영역].
  Widget _body(IqDetailData data) {
    final IndividualQuestion q = data.question;
    final bool isStudent = _role == AppRole.student;
    final bool isMentor = _role == AppRole.mentor;

    // 하단 고정 영역 내용(상태 안내 + 액션/컴포저). 역할·상태 게이트는 기존
    // 의미 그대로 — 내용이 없으면 영역 자체를 렌더하지 않는다(빈 띠 금지).
    final List<Widget> bottom = <Widget>[
      if (isStudent) ..._studentActions(q),
      if (isMentor) ..._mentorActions(q),
    ];

    return Column(
      children: <Widget>[
        _conversationHeader(data),
        Expanded(
          // 타임라인은 [_messages](재조회 + 실시간 upsert 수렴 뷰)를 그린다 —
          // 실시간 수신이 전체 FutureBuilder 재구축 없이 목록만 갱신한다.
          child: ListenableBuilder(
            listenable: _messages,
            builder: (BuildContext context, Widget? _) {
              final IqAttachmentGroups groups = data.groups;
              return ListView(
                controller: _timelineScroll,
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH, 12, AppSpacing.screenH, 12),
                children: <Widget>[
                  _questionBubble(data),
                  // 작성자 미확인 레거시 첨부 — 중립 그룹(학생·멘토 어느 쪽에도
                  // 귀속하지 않는다 — §2-1 백필·추측 금지).
                  if (groups.legacyUnknown.isNotEmpty)
                    _legacyUnknownBubble(groups.legacyUnknown),
                  for (final IqMessage m in _messages.items)
                    _iqMessageBubble(data, m),
                  // 멘토 작성·미연결 첨부(구버전 앱 등록분) — 멘토 방향 그룹.
                  if (groups.unlinkedMentor.isNotEmpty)
                    _unlinkedMentorBubble(data, groups.unlinkedMentor),
                  // message_id 는 있으나 현재 목록에서 메시지를 확인하지 못한
                  // 첨부 — fail-closed 중립(재조회로 확인되면 메시지 그룹 수렴).
                  if (groups.unresolvedMessage.isNotEmpty)
                    _unresolvedMessageBubble(groups.unresolvedMessage),
                ],
              );
            },
          ),
        ),
        if (bottom.isNotEmpty) _bottomArea(bottom),
      ],
    );
  }

  /// 컴팩트 대화방 헤더 — 유형·상태·마감, 제목 한 줄, 멘토명·작성시각.
  /// 카드가 아니라 얇은 띠다(대화 영역을 잠식하지 않는다). 제목이 길면 여기서는
  /// 말줄임하고, 전문은 타임라인 첫 질문 말풍선에서 항상 읽을 수 있다.
  Widget _conversationHeader(IqDetailData data) {
    final IndividualQuestion q = data.question;
    final bool isStudent = _role == AppRole.student;
    final String? remaining = formatIqExpiryRemaining(q.expiresAt, q.status);
    final List<String> meta = <String>[
      if (isStudent) data.mentorName ?? '멘토',
      if (q.createdAt != null) Formatters.relativeKorean(q.createdAt!),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, 10, AppSpacing.screenH, 10),
      decoration: const BoxDecoration(
        color: ColorTokens.page,
        border: Border(bottom: BorderSide(color: ColorTokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 컴플라이언스: 헤더에 금액 비표시(유형·상태만) — 카드 시절과 동일.
              AppBadge(label: iqTypeLabel(q.type), tinted: true),
              const SizedBox(width: 6),
              IqStatusPill(status: q.status),
              if (remaining != null) ...<Widget>[
                const Spacer(),
                Text(remaining, style: AppTypography.caption),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            q.title.isEmpty ? '(제목 없음)' : q.title,
            style: AppTypography.cardTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (meta.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(meta.join(' · '), style: AppTypography.caption),
          ],
        ],
      ),
    );
  }

  /// 멘토 첨삭 진입 게이트 — **항상 false(2026-08 폐쇄)**.
  ///
  /// 첨삭 기능이 제품에서 닫혀 있는 동안 진입 버튼('첨삭하기')을 노출하지
  /// 않는다 — 버튼만 남고 기능이 막힌 반쪽 상태 금지(iOS 멘토 실기기 실측).
  /// 재개 시 이 게이트만 원복하면 된다. 원래 조건(§4-1): 담당 멘토 + 활성
  /// 상태(iqCanMentorAnnotate) + 학생 작성 첨부만. S18 기계 부품
  /// (_annotateAttachment·IqAnnotationRepository·오버라이드 주입점)은 유지.
  bool _canAnnotateGroup(IndividualQuestion q, IqMessageAuthor groupAuthor) =>
      false;

  /// 원본 질문 = 타임라인의 첫 대화 항목. 제목·본문·작성시각·**학생 첨부**가 한
  /// 말풍선 그룹이다(별도 질문 카드·첨부 섹션 금지).
  ///
  /// 작성자는 질문 행의 student_id 로 판정한다 — 빈 값은 절대 매칭하지 않고
  /// '작성자 미확인' 중립으로 남긴다(메시지와 같은 규칙). 좌우 거울상·강조는
  /// 뷰어 uid 가 있을 때만.
  ///
  /// 첨부는 귀속 그룹의 [IqAttachmentGroups.initialQuestion](학생 작성·미연결)
  /// 만 붙는다 — 멘토 첨부·메시지 연결 첨부·작성자 미확인 레거시는 각자의
  /// 위치에서 렌더된다(전체 합치기 금지).
  Widget _questionBubble(IqDetailData data) {
    final IndividualQuestion q = data.question;
    final List<IqAttachment> attachments = data.groups.initialQuestion;
    final IqMessageAuthor author = iqMessageAuthorOf(
      authorId: q.studentId,
      studentId: q.studentId,
      mentorId: q.mentorId,
    );
    final bool? mine =
        iqMessageIsMine(authorId: q.studentId, viewerId: _viewerId);

    return ConversationBubble(
      body: q.body,
      titleLabel: q.title.trim().isEmpty ? null : q.title,
      align: mine == true ? ConversationAlign.end : ConversationAlign.start,
      tone: mine == true ? ConversationTone.accent : ConversationTone.neutral,
      authorLabel: iqMessageAuthorLabel(author),
      timeLabel:
          q.createdAt == null ? null : Formatters.relativeKorean(q.createdAt!),
      attachments: attachments.isEmpty
          ? const <Widget>[]
          : <Widget>[
              _IqAttachmentGroup(
                attachments: attachments,
                urlResolver: _urlResolver,
                // 첨삭 진입은 멘토만(§3) — 학생 작성 첨부 + 활성 상태
                // (assigned/claimed/**answered** — 해결 완료 전까지, §4-1).
                onAnnotate:
                    _canAnnotateGroup(q, IqMessageAuthor.student)
                        ? _annotateAttachment
                        : null,
                // §6: 당사자 저장(다운로드) — RLS 가 당사자 외 접근을 차단한다.
                onSave: _saveAttachment,
              ),
            ],
    );
  }

  /// 메시지 1건 → 대화 말풍선 + **그 메시지에 연결된 첨부**(message_id 귀속).
  ///
  /// 작성자 방향(학생/멘토)은 질문 행의 당사자 id 로 판정한다 — 뷰어 신원이
  /// 없어도 성립한다. 좌우 거울상은 뷰어 uid 가 있을 때만 적용하고, 모르면
  /// 좌측 중립으로 둔다(내 메시지로 오인시키지 않는다). 첨부 방향·라벨은
  /// 메시지 작성자를 그대로 따른다(§2-1).
  Widget _iqMessageBubble(IqDetailData data, IqMessage m) {
    final IndividualQuestion q = data.question;
    final List<IqAttachment> attachments = data.groups.forMessage(m.id);
    final IqMessageAuthor author = iqMessageAuthorOf(
      authorId: m.authorId,
      studentId: q.studentId,
      mentorId: q.mentorId,
    );
    final bool? mine =
        iqMessageIsMine(authorId: m.authorId, viewerId: _viewerId);

    return ConversationBubble(
      body: m.body,
      align: mine == true ? ConversationAlign.end : ConversationAlign.start,
      tone: mine == true ? ConversationTone.accent : ConversationTone.neutral,
      authorLabel: iqMessageAuthorLabel(author),
      timeLabel:
          m.createdAt == null ? null : Formatters.relativeKorean(m.createdAt!),
      attachments: attachments.isEmpty
          ? const <Widget>[]
          : <Widget>[
              _IqAttachmentGroup(
                attachments: attachments,
                urlResolver: _urlResolver,
                // 학생 메시지의 이미지에만 멘토 첨삭 진입(§4-1).
                onAnnotate: _canAnnotateGroup(q, author)
                    ? _annotateAttachment
                    : null,
                onSave: _saveAttachment,
              ),
            ],
    );
  }

  /// 작성자 미확인 레거시 첨부 — 중립 그룹(§2-1). 학생·멘토 말풍선에 넣지
  /// 않고, 첨삭 진입도 열지 않는다(작성자 추측 금지). 조회·저장은 유지.
  Widget _legacyUnknownBubble(List<IqAttachment> attachments) {
    return ConversationBubble(
      body: '',
      align: ConversationAlign.start,
      tone: ConversationTone.neutral,
      authorLabel: '이전 첨부 · 작성자 미확인',
      attachments: <Widget>[
        _IqAttachmentGroup(
          attachments: attachments,
          urlResolver: _urlResolver,
          onSave: _saveAttachment,
        ),
      ],
    );
  }

  /// 연결 메시지 미확인 첨부 — fail-closed 중립 그룹. 업로더 기록으로
  /// 재분류하지 않는다(재조회 후 귀속이 이동해 보이는 것을 막는다).
  /// 첨삭 진입도 열지 않는다. 조회·저장은 유지.
  Widget _unresolvedMessageBubble(List<IqAttachment> attachments) {
    return ConversationBubble(
      body: '',
      align: ConversationAlign.start,
      tone: ConversationTone.neutral,
      authorLabel: '첨부 · 연결 메시지 미확인',
      attachments: <Widget>[
        _IqAttachmentGroup(
          attachments: attachments,
          urlResolver: _urlResolver,
          onSave: _saveAttachment,
        ),
      ],
    );
  }

  /// 멘토 작성·미연결 첨부(구버전 앱이 message_id 없이 등록한 첨부·첨삭본) —
  /// 멘토 방향·멘토 라벨 그룹으로 표시한다(학생 말풍선 합치기 금지).
  Widget _unlinkedMentorBubble(IqDetailData data, List<IqAttachment> group) {
    final String? mentorId = data.question.mentorId;
    final bool? mine = mentorId == null
        ? null
        : iqMessageIsMine(authorId: mentorId, viewerId: _viewerId);
    return ConversationBubble(
      body: '',
      align: mine == true ? ConversationAlign.end : ConversationAlign.start,
      tone: mine == true ? ConversationTone.accent : ConversationTone.neutral,
      authorLabel: iqMessageAuthorLabel(IqMessageAuthor.mentor),
      attachments: <Widget>[
        _IqAttachmentGroup(
          attachments: group,
          urlResolver: _urlResolver,
          onSave: _saveAttachment,
        ),
      ],
    );
  }

  /// 하단 고정 영역 — 타임라인과 시각적으로 분리된 흰 띠 + 시스템 제스처
  /// 안전영역. 키보드는 Scaffold(resizeToAvoidBottomInset 기본값)가 밀어올린다.
  Widget _bottomArea(List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: ColorTokens.page,
        border: Border(top: BorderSide(color: ColorTokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH, 10, AppSpacing.screenH, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
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
    // §H: 학생 후속 메시지 컴포저(iq_append_message) — 종결 전 구간에만.
    // 첨부(사진 선택 + 전송 전 필기 §4-2)는 전송 시 학생 message_id 로 연결.
    if (iqCanStudentSendMessage(q.status)) {
      out.addAll(_pendingUploadRows(q.id));
      out.addAll(_chatComposer(hint: '멘토에게 추가로 궁금한 점을 남겨 보세요.'));
    }
    // 환불·만료·취소 종결 안내 — 하단 영역이 빈 띠로 남지 않게 한다.
    final String? notice = iqReadOnlyNotice(q.status);
    if (notice != null) {
      out.add(Text(notice, style: AppTypography.caption));
    }
    return out;
  }

  /// §H: 당사자 공용 대화 컴포저(iq_append_message). 본문이 비면 전송 비활성 —
  /// 첨부만 보내는 전송은 없다(첨부는 메시지 생성 후 그 message_id 로 등록).
  List<Widget> _chatComposer({required String hint}) {
    return <Widget>[
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          IconButton(
            tooltip: '파일 첨부',
            icon: const Icon(Icons.attach_file),
            onPressed: _busy ? null : _pickPendingAttachment,
          ),
          Expanded(
            child: TextField(
              controller: _chatController,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '보내기',
            icon: const Icon(Icons.send_rounded),
            onPressed: (_busy || !_chatCanSend) ? null : _sendChatMessage,
          ),
        ],
      ),
    ];
  }

  /// 첨부 대기열 행(§6·§2-2) — 파일명·상태·필기/재시도/제거 액션.
  /// 답변 컴포저와 대화 컴포저가 공유한다(첫 답변 실패분이 answered 전이 후에도
  /// 남아 같은 message_id 로 재시도할 수 있게).
  List<Widget> _pendingUploadRows(String questionId) {
    return <Widget>[
      for (final _PendingIqUpload p in _pendingUploads) ...<Widget>[
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Icon(
              p.error == null ? Icons.attach_file : Icons.error_outline_rounded,
              size: 18,
              color:
                  p.error == null ? ColorTokens.secondary : ColorTokens.danger,
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
            // 전송 전 필기(§4-2) — 이미지 대기 항목에만. 이미 메시지에 묶인
            // 실패분(재시도 대기)은 내용 교체 금지 — 같은 파일로만 재시도.
            if (!p.uploading && p.messageId == null && _isImagePending(p))
              IconButton(
                tooltip: '필기하기',
                icon: const Icon(Icons.draw_rounded, size: 18),
                onPressed: _busy ? null : () => _annotatePending(p),
              ),
            if (p.uploading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (p.error != null)
              TextButton(
                onPressed: () => _uploadPending(questionId, p),
                child: const Text('재시도'),
              ),
            if (!p.uploading)
              IconButton(
                tooltip: '제거',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _pendingUploads.remove(p)),
              ),
          ],
        ),
      ],
    ];
  }

  bool _isImagePending(_PendingIqUpload p) =>
      p.file.mimeType.toLowerCase().startsWith('image/');

  List<Widget> _mentorActions(IndividualQuestion q) {
    if (!iqCanMentorAnswer(q.status)) {
      if (q.status == IndividualQuestionStatus.answered) {
        return <Widget>[
          const Text('답변을 등록했어요. 학생이 해결 완료하면 정산 예정으로 잡혀요.',
              style: AppTypography.caption),
          // §H: 첫 답변 이후 추가 답글은 당사자 공용 경로(iq_append_message).
          // 첨부·첨삭본 대기열도 여기서 이어진다(answered 구간 첨삭 §4-1,
          // 첫 답변 첨부 실패분 재시도 포함).
          if (iqCanMentorSendFollowUp(q.status)) ...<Widget>[
            ..._pendingUploadRows(q.id),
            ..._chatComposer(hint: '학생 질문에 이어서 답글을 남겨 보세요.'),
          ],
        ];
      }
      if (q.status == IndividualQuestionStatus.released) {
        return const <Widget>[
          Text('정산이 완료된 질문이에요.', style: AppTypography.caption),
        ];
      }
      final String? notice = iqReadOnlyNotice(q.status);
      if (notice != null) {
        return <Widget>[Text(notice, style: AppTypography.caption)];
      }
      return const <Widget>[];
    }
    return <Widget>[
      const Text('답변 작성', style: AppTypography.caption),
      const SizedBox(height: 8),
      TextField(
        controller: _answerController,
        // 하단 고정 컴포저 — 짧은 뷰포트(가로 모드)에서도 타임라인이 남게
        // 낮게 시작하고, 길어지면 내부 스크롤로 늘어난다(카드 시절 4~10줄).
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          hintText: '학생이 이해할 수 있게 풀이 과정을 함께 적어 주세요.',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      // §6·§2-2: 답변 첨부(이미지·카메라·파일)와 첨삭본 — 대기열에 쌓였다가
      // 답변 등록이 돌려준 message_id 로 등록된다. 실패분은 아래 목록에 남아
      // 같은 message_id·같은 경로로 재시도(중복 업로드 0·메시지 재생성 0).
      ..._pendingUploadRows(q.id),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Expanded(
            child: SecondaryButton(
              label: '파일 첨부',
              icon: Icons.attach_file,
              onPressed: _busy ? null : _pickPendingAttachment,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PrimaryButton(
              label: '답변 등록',
              onPressed: _busy ? null : _submitAnswer,
            ),
          ),
        ],
      ),
    ];
  }
}

/// §6·§2-2: 첨부 대기 항목 — 업로드 상태·재시도 경로·귀속 메시지.
class _PendingIqUpload {
  _PendingIqUpload(this.file);

  /// 업로드할 파일(전송 전 필기 완료 시 평탄화본으로 교체된다).
  PickedImage file;

  /// 전송 전 필기(§4-2) 이어 그리기용 — 최초 원본과 직전 스트로크.
  PickedImage? original;
  InkDocument? inkDocument;

  bool uploading = false;
  String? error;

  /// 이 첨부가 귀속된 메시지 id — 메시지 전송(iq_append_message /
  /// 첫 답변)이 반환한 정본. 실패 재시도에서도 유지된다(재귀속·재생성 금지).
  String? messageId;

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

/// 첨부 그룹 — 귀속된 말풍선(질문·메시지·레거시 중립) 안에 세로로 쌓인다.
/// 이미지는 서명 URL 로 인라인 표시, 그 외 파일은 이름 행만. 조회·저장·첨삭
/// 의미와 게이트는 §6·S18 그대로다.
/// [onAnnotate] 가 있으면(멘토·활성 상태·학생 작성 그룹) 이미지마다 '첨삭하기'.
/// [onSave] 가 있으면 항목마다 '저장'(당사자 다운로드 → SAF) 노출.
///
/// ★ P3-6: Future 는 storage_path 별로 상태에 메모한다 — build 마다 새
///   Future 를 만들던 이전 방식은 리빌드마다 서명 URL 을 재요청했다.
///   리졸버 캐시(만료 전 재사용)와 이중으로 재요청을 막는다.
class _IqAttachmentGroup extends StatefulWidget {
  const _IqAttachmentGroup({
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
  State<_IqAttachmentGroup> createState() => _IqAttachmentGroupState();
}

class _IqAttachmentGroupState extends State<_IqAttachmentGroup> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final IqAttachment a in widget.attachments) ...<Widget>[
          if (a != widget.attachments.first) const SizedBox(height: 8),
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
              // 말풍선 폭(화면 72%) 안에서 좁은 기기는 줄바꿈한다(가로 오버플로 0).
              Wrap(
                spacing: 4,
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
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.attach_file,
                    size: 18, color: ColorTokens.secondary),
                const SizedBox(width: 8),
                Flexible(
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
    );
  }
}

/// 첨부 전체화면 뷰어(줌·팬). [onAnnotate] 가 있으면(멘토, S18) '첨삭하기'를
/// 노출한다 — 뷰어를 닫고 상세 화면의 첨삭 흐름으로 넘긴다.
/// ★ 질문방 AttachmentViewerScreen 은 roomId/threadId 에 결합돼 있어
///   재사용하지 않는다(전송은 대기열 + 메시지 경로가 담당).
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
