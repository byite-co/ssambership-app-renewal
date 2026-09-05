import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../core/scan/picked_image.dart';
import '../../../../core/scan/scan_source_picker.dart';
import '../../../../design/role_theme.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_spacing.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_blocks.dart';
import '../../../../design/widgets/app_primary_button.dart';
import '../../../../design/widgets/app_secondary_button.dart';
import '../../../../design/widgets/app_skeleton.dart';
import '../../../../design/widgets/chip_scroll.dart';
import '../../../../design/widgets/glass_bars.dart';
import '../../../../design/widgets/glass_inner.dart';
import '../../../../design/widgets/status_pill.dart';
import '../../../../shared/errors/friendly_error.dart';
import '../../../../shared/format/formatters.dart';
import '../../../mentor_console/data/document_validation.dart';
import '../../../mentor_console/data/mentor_console_models.dart';
import '../../../mentor_console/data/mentor_console_repository.dart';
import '../../../mentor_console/ui/mentor_document_field.dart';
import '../widgets/mypage_section.dart';

/// 멘토 마이페이지 셀프서비스 — 활동 상태(A-4b ④) + 학생증 사후 제출(⑦).
///
/// 본인 프로필(`mentor_profiles` 활동 컬럼·학생증 ref)을 한 번 읽어 두 섹션에 준다.
/// - 활동 상태: 활동 중 / 일시중지(기간·사유) / 종료 예정(날짜 14~90일). 일시중지는
///   **새 구독만 막고 지금 학생 질문은 계속 받는다**(DB-4 2-C 확인). 복귀하면 꺼둔
///   요금제도 모두 다시 켜진다(오너 결정 5-a — 시트에서 먼저 알린다).
/// - 학생증: 버킷 `student-id-images/{uid}/…` 업로드 후 `mentor_student_id_document_set_self`.
///   학력 인증의 "서류 없는 잠정 pending" 행은 안내만 하고 제출을 잠그지 않는다(DB-4 §7 H).
class MentorSelfServiceSections extends StatefulWidget {
  const MentorSelfServiceSections({
    super.key,
    this.port,
    this.scanPicker = const DeviceScanSourcePicker(),
    this.nowOverride,
  });

  /// 테스트 주입(기본: [AppScope] 의 mentorConsole).
  final MentorConsolePort? port;
  final ScanSourcePort scanPicker;

  /// 테스트 주입(기본: DateTime.now).
  final DateTime Function()? nowOverride;

  /// 일시중지 최대 일수(DB-4 201 `PAUSE_TOO_LONG` max_days).
  static const int maxPauseDays = 7;

  /// 종료 효력일 최소·최대(DB-4 201 — 웹 2주 공지 · 앱 확장 90일, 오너 결정 7-a).
  static const int minTerminationDays = 14;
  static const int maxTerminationDays = 90;

  @override
  State<MentorSelfServiceSections> createState() =>
      _MentorSelfServiceSectionsState();
}

class _Load {
  const _Load({required this.profile, required this.verifications});
  final MentorOwnProfile profile;
  final List<SchoolVerificationRecord> verifications;
}

class _MentorSelfServiceSectionsState extends State<MentorSelfServiceSections> {
  late final MentorConsolePort _port;
  late Future<_Load> _future;
  bool _busy = false;

  PickedImage? _picked;
  String? _problem;
  String? _docError;

  DateTime get _now => (widget.nowOverride ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _port = widget.port ?? AppScope.of(context).mentorConsole;
    _future = _load();
  }

  Future<_Load> _load() async {
    final MentorOwnProfile profile = await _port.loadOwnProfile();
    List<SchoolVerificationRecord> verifications =
        const <SchoolVerificationRecord>[];
    try {
      verifications = await _port.loadSchoolVerifications();
    } catch (_) {
      // 안내용 보조 조회 — 실패해도 활동 상태·학생증 제출은 그대로 쓴다.
    }
    return _Load(profile: profile, verifications: verifications);
  }

  void _reload() {
    if (!mounted) return;
    final Future<_Load> next = _load();
    setState(() {
      _future = next;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── 활동 상태 ────────────────────────────────────────────────────

  Future<void> _apply(MentorActivityRequest request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final MentorActivityResult r = await _port.setActivityStatus(request);
      if (!mounted) return;
      switch (r.activityStatus) {
        case 'paused':
          final DateTime? until = r.pauseUntil;
          _snack(until == null
              ? '잠시 쉬어요. 새 구독만 막히고 지금 학생 질문은 계속 받아요.'
              : '${Formatters.monthDay(until)}까지 쉬어요. 구독 ${r.subscriptionsExtended}건의 기간이 그만큼 늘어나요.');
        case 'active':
          _snack('활동을 다시 시작했어요. 요금제 ${r.plansReactivated}개를 켰어요.');
        case 'terminating':
          final DateTime? at = r.terminationEffectiveAt;
          _snack(at == null
              ? '활동 종료를 예약했어요.'
              : '${Formatters.monthDay(at)}에 활동이 종료돼요. 구독 학생 ${r.notifiedSubscribers}명에게 안내했어요.');
        default:
          _snack('활동 상태를 바꿨어요.');
      }
      _reload();
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPause() async {
    final _PauseChoice? choice = await GlassBottomSheet.show<_PauseChoice>(
      context,
      builder: (BuildContext sheet) => _PauseSheet(now: _now),
    );
    if (choice == null || !mounted) return;
    await _apply(MentorActivityRequest.pause(
      pauseUntil: _now.add(Duration(days: choice.days)),
      reason: choice.reason,
    ));
  }

  Future<void> _openResume() async {
    final bool? ok = await GlassBottomSheet.show<bool>(
      context,
      builder: (BuildContext sheet) => const _ConfirmSheet(
        title: '지금 복귀할까요?',
        body: '새 구독을 다시 받아요. 요금제 설정에서 꺼둔 요금제도 모두 다시 켜져요.',
        confirmLabel: '복귀하기',
        danger: false,
      ),
    );
    if (ok != true || !mounted) return;
    await _apply(const MentorActivityRequest.resume());
  }

  Future<void> _openTerminate() async {
    final DateTime now = _now;
    final DateTime first = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: MentorSelfServiceSections.minTerminationDays));
    final DateTime last = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: MentorSelfServiceSections.maxTerminationDays));
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: first,
      firstDate: first,
      lastDate: last,
      helpText: '종료 예정일 (${MentorSelfServiceSections.minTerminationDays}일 뒤부터)',
      confirmText: '선택',
      cancelText: '취소',
    );
    if (date == null || !mounted) return;
    final bool? ok = await GlassBottomSheet.show<bool>(
      context,
      builder: (BuildContext sheet) => _ConfirmSheet(
        title: '${Formatters.monthDay(date)}에 활동을 종료할까요?',
        body: '그날부터 신규 구독을 받지 않고 요금제가 모두 꺼져요. 구독 중인 학생에게 안내가 가고, 유예 기간 동안은 답변을 계속 부탁드려요. 종료 확정과 남은 기간 환불은 관리자가 처리해요.',
        confirmLabel: '종료 예약',
        danger: true,
      ),
    );
    if (ok != true || !mounted) return;
    await _apply(MentorActivityRequest.terminate(effectiveAt: date));
  }

  // ── 학생증 ───────────────────────────────────────────────────────

  Future<void> _pickDocument() async {
    final PickedImage? picked = await pickMentorDocument(
      context,
      widget.scanPicker,
      title: '학생증 올리기',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      _problem = mentorDocumentProblem(picked);
      _docError = null;
    });
  }

  Future<void> _submitDocument() async {
    final PickedImage? picked = _picked;
    if (picked == null || _busy) return;
    final VerifiedMentorDocument? document = verifyMentorDocument(picked);
    if (document == null) {
      setState(() => _problem = mentorDocumentProblem(picked));
      return;
    }
    setState(() {
      _busy = true;
      _docError = null;
    });
    try {
      await _port.submitStudentIdDocument(document);
      if (!mounted) return;
      _snack('학생증을 제출했어요.');
      setState(() {
        _picked = null;
        _problem = null;
      });
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _docError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Load>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<_Load> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.section),
            child: AppSkeleton(),
          );
        }
        final _Load? data = snap.data;
        if (snap.hasError || data == null) {
          return MyPageSection(
            icon: Icons.toggle_on_rounded,
            title: '활동 상태',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppCallout(
                  tone: AppCalloutTone.danger,
                  text: '활동 상태를 불러오지 못했어요. ${friendlyError(snap.error ?? '')}',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: _reload, child: const Text('다시 시도')),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MyPageSection(
              icon: Icons.toggle_on_rounded,
              title: '활동 상태',
              child: _activityBlock(data.profile),
            ),
            MyPageSection(
              icon: Icons.badge_outlined,
              title: '학생증',
              child: _studentIdBlock(data),
            ),
          ],
        );
      },
    );
  }

  Widget _activityBlock(MentorOwnProfile p) {
    final String state = mentorActivityState(p, now: _now);
    final Widget status;
    final List<Widget> actions = <Widget>[];
    switch (state) {
      case 'paused':
        status = _StateLine(
          pill: const StatusPill(label: '일시중지', tone: StatusTone.warning, showDot: true),
          text: p.pauseUntil == null
              ? '잠시 쉬는 중이에요. 새 구독만 막히고 지금 학생 질문은 계속 받아요.'
              : '${Formatters.monthDay(p.pauseUntil!)}까지 쉬어요. 새 구독만 막히고 지금 학생 질문은 계속 받아요.',
        );
        actions.add(AppSecondaryButton(
          label: '지금 복귀하기',
          icon: Icons.play_arrow_rounded,
          onPressed: _busy ? null : _openResume,
        ));
      case 'terminating':
        status = _StateLine(
          pill: const StatusPill(label: '종료 예정', tone: StatusTone.danger, showDot: true),
          text: p.terminationEffectiveAt == null
              ? '활동 종료가 예약돼 신규 구독을 받지 않아요. 유예 기간 동안 학생 응대를 부탁드려요.'
              : '${Formatters.monthDay(p.terminationEffectiveAt!)}에 종료돼요. 신규 구독을 받지 않고, 유예 기간 동안 학생 응대를 부탁드려요.',
        );
      case 'terminated':
        status = const _StateLine(
          pill: StatusPill(label: '종료됨', tone: StatusTone.neutral, showDot: true),
          text: '활동이 종료됐어요. 재개가 필요하면 관리자에게 문의해 주세요.',
        );
      default:
        status = const _StateLine(
          pill: StatusPill(label: '활동 중', tone: StatusTone.success, showDot: true),
          text: '새 구독을 받고 학생 질문에 답하고 있어요.',
        );
        actions
          ..add(AppSecondaryButton(
            label: '잠시 쉬기',
            icon: Icons.pause_rounded,
            onPressed: _busy ? null : _openPause,
          ))
          ..add(const SizedBox(height: 8))
          ..add(AppSecondaryButton(
            label: '활동 종료 예약',
            filled: false,
            danger: true,
            onPressed: _busy ? null : _openTerminate,
          ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        status,
        if (actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s12),
          ...actions,
        ],
      ],
    );
  }

  Widget _studentIdBlock(_Load data) {
    final MentorOwnProfile p = data.profile;
    final bool submitted = (p.studentIdImageUrl?.trim().isNotEmpty ?? false);
    SchoolVerificationRecord? latest;
    for (final SchoolVerificationRecord r in data.verifications) {
      if (latest == null || r.createdAt.isAfter(latest.createdAt)) latest = r;
    }
    final bool provisional = latest != null &&
        latest.status == ReviewStatus.pending &&
        !latest.hasDocument;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StateLine(
          pill: submitted
              ? const StatusPill(label: '제출됨', tone: StatusTone.success, showDot: true)
              : const StatusPill(label: '미제출', tone: StatusTone.neutral, showDot: true),
          text: submitted
              ? '학생증을 제출했어요. 바꾸려면 새 파일을 올려 주세요.'
              : '아직 학생증을 제출하지 않았어요. 재학 확인에 쓰여요.',
        ),
        if (provisional) ...<Widget>[
          const SizedBox(height: 10),
          const AppCallout(
            tone: AppCalloutTone.neutral,
            text: '학력 인증은 서류 없음 · 관리자 확정 대기 상태예요. 학생증 제출은 그와 별개로 지금 할 수 있어요.',
          ),
        ],
        const SizedBox(height: AppSpacing.s12),
        MentorDocumentField(
          picked: _picked,
          onPick: _pickDocument,
          onClear: () => setState(() {
            _picked = null;
            _problem = null;
            _docError = null;
          }),
          enabled: !_busy,
          problem: _problem,
        ),
        if (_docError != null) ...<Widget>[
          const SizedBox(height: 8),
          AppCallout(tone: AppCalloutTone.danger, text: _docError!),
        ],
        const SizedBox(height: 10),
        AppPrimaryButton(
          label: _busy ? '제출 중…' : '학생증 제출',
          onPressed: (!_busy && _picked != null && _problem == null)
              ? _submitDocument
              : null,
        ),
      ],
    );
  }
}

/// 웹 `mentorActivityState` 와 같은 판정 — paused 는 `pause_until` 경과 시 active.
String mentorActivityState(MentorOwnProfile p, {required DateTime now}) {
  final String raw = p.activityStatus?.trim().toLowerCase() ?? 'active';
  if (raw == 'paused') {
    final DateTime? until = p.pauseUntil;
    if (until != null && !until.isAfter(now)) return 'active';
    return 'paused';
  }
  if (raw == 'terminating' || raw == 'terminated') return raw;
  return 'active';
}

class _StateLine extends StatelessWidget {
  const _StateLine({required this.pill, required this.text});
  final Widget pill;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        pill,
        const SizedBox(height: 8),
        Text(text, style: AppTypography.body),
      ],
    );
  }
}

class _PauseChoice {
  const _PauseChoice({required this.days, required this.reason});
  final int days;
  final String reason;
}

/// 일시중지 시트 — 기간(1~7일) · 사유(일반 휴식/질병 등) · 안내.
class _PauseSheet extends StatefulWidget {
  const _PauseSheet({required this.now});
  final DateTime now;

  @override
  State<_PauseSheet> createState() => _PauseSheetState();
}

class _PauseSheetState extends State<_PauseSheet> {
  int _days = 3;
  String _reason = 'rest';

  @override
  Widget build(BuildContext context) {
    final DateTime until = widget.now.add(Duration(days: _days));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 6),
        const Text('얼마나 쉴까요?', style: AppTypography.section),
        const SizedBox(height: 4),
        const Text(
          '새 구독만 막히고 지금 학생 질문은 계속 받아요. 쉬는 만큼 구독 학생의 기간이 자동으로 늘어나요.',
          style: AppTypography.captionSecondary,
        ),
        const SizedBox(height: AppSpacing.s12),
        ChipScroll(
          labels: <String>[
            for (int d = 1; d <= MentorSelfServiceSections.maxPauseDays; d++) '$d일',
          ],
          selectedIndex: _days - 1,
          onSelected: (int i) => setState(() => _days = i + 1),
        ),
        const SizedBox(height: 6),
        Text('${Formatters.monthDay(until)}에 자동으로 복귀해요',
            style: AppTypography.captionSecondary),
        const SizedBox(height: AppSpacing.s12),
        _ReasonRow(
          label: '일반 휴식',
          caption: '6개월에 한 번 쓸 수 있어요',
          selected: _reason == 'rest',
          onTap: () => setState(() => _reason = 'rest'),
        ),
        const SizedBox(height: 8),
        _ReasonRow(
          label: '질병 등',
          caption: '관리자가 확인해요 · 횟수 제한 없음',
          selected: _reason == 'illness',
          onTap: () => setState(() => _reason = 'illness'),
        ),
        const SizedBox(height: AppSpacing.s16),
        AppPrimaryButton(
          label: '$_days일 쉬기',
          onPressed: () => Navigator.of(context)
              .pop(_PauseChoice(days: _days, reason: _reason)),
        ),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = RoleTheme.of(context).color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassInner(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ringColor: selected ? accent : null,
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: AppTypography.bodyStrong),
                  Text(caption, style: AppTypography.captionSecondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.danger,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 6),
        Text(title, style: AppTypography.section),
        const SizedBox(height: AppSpacing.s12),
        Text(body, style: AppTypography.body),
        const SizedBox(height: AppSpacing.s20),
        Row(
          children: <Widget>[
            Expanded(
              child: AppSecondaryButton(
                label: '닫기',
                filled: false,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppSecondaryButton(
                label: confirmLabel,
                danger: danger,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
