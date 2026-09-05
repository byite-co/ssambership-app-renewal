import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/scan/picked_image.dart';
import '../../../core/scan/scan_source_picker.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_input_field.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/glass_badge.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/format/formatters.dart';
import '../../../shared/widgets/v3_page.dart';
import '../data/document_validation.dart';
import '../data/mentor_console_models.dart';
import '../data/mentor_console_repository.dart';
import 'mentor_document_field.dart';
import 'review_status_ui.dart';

/// 학교명 상한(웹 폼 maxLength 미러).
const int kAcademicUniversityNameMax = 40;

/// 변경 사유 상한(웹 폼 maxLength 미러).
const int kAcademicChangeReasonMax = 100;

/// 학적 변경 요청(A-4a #5) — `/profile/academic-record-change`.
///
/// 학교명(필수·40자) + 사유(선택·100자) + 증명 서류(필수). 검토 중(pending)에는
/// 웹과 같이 새 요청을 잠근다. 승인 반영(프로필 학교명 갱신)은 관리자 몫이라
/// 여기서는 상태·기록만 보여준다.
class AcademicRecordChangeScreen extends StatefulWidget {
  const AcademicRecordChangeScreen({
    super.key,
    this.portOverride,
    this.scanPicker = const DeviceScanSourcePicker(),
  });

  final MentorConsolePort? portOverride;
  final ScanSourcePort scanPicker;

  @override
  State<AcademicRecordChangeScreen> createState() =>
      _AcademicRecordChangeScreenState();
}

class _AcademicRecordChangeScreenState
    extends State<AcademicRecordChangeScreen> {
  late final MentorConsolePort _port;
  late Future<List<AcademicRecordChangeRecord>> _future;

  final TextEditingController _university = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  PickedImage? _picked;
  String? _problem;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _port = widget.portOverride ?? AppScope.of(context).mentorConsole;
    _future = _port.loadAcademicRecordChanges();
    _university.addListener(_onEdit);
    _reason.addListener(_onEdit);
  }

  @override
  void dispose() {
    _university.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (_submitError != null) setState(() => _submitError = null);
    setState(() {});
  }

  void _reload() {
    setState(() {
      _future = _port.loadAcademicRecordChanges();
    });
  }

  String get _universityText => _university.text.trim();

  String? get _universityError {
    if (_universityText.length > kAcademicUniversityNameMax) {
      return '학교명은 $kAcademicUniversityNameMax자까지 입력할 수 있어요.';
    }
    return null;
  }

  String? get _reasonError {
    if (_reason.text.trim().length > kAcademicChangeReasonMax) {
      return '사유는 $kAcademicChangeReasonMax자까지 입력할 수 있어요.';
    }
    return null;
  }

  bool get _canSubmit =>
      !_submitting &&
      _universityText.isNotEmpty &&
      _universityError == null &&
      _reasonError == null &&
      _picked != null &&
      _problem == null;

  Future<void> _pick() async {
    final PickedImage? picked =
        await pickMentorDocument(context, widget.scanPicker);
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      _problem = mentorDocumentProblem(picked);
      _submitError = null;
    });
  }

  void _clear() => setState(() {
        _picked = null;
        _problem = null;
        _submitError = null;
      });

  Future<void> _submit() async {
    final PickedImage? picked = _picked;
    if (picked == null) return;
    final VerifiedMentorDocument? document = verifyMentorDocument(picked);
    if (document == null) {
      setState(() => _problem = mentorDocumentProblem(picked));
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final String reason = _reason.text.trim();
      await _port.submitAcademicRecordChange(
        requestedUniversityName: _universityText,
        changeReason: reason.isEmpty ? null : reason,
        document: document,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('학적 변경 요청을 제출했어요. 결과는 알림으로 알려드릴게요.'),
        ),
      );
      _university.clear();
      _reason.clear();
      setState(() {
        _picked = null;
        _problem = null;
        _future = _port.loadAcademicRecordChanges();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return V3Page(
      title: '학적 변경 요청',
      body: FutureBuilder<List<AcademicRecordChangeRecord>>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<AcademicRecordChangeRecord>> snap,
        ) {
          if (snap.connectionState != ConnectionState.done) {
            return const V3LoadingView(cards: 2);
          }
          if (snap.hasError || snap.data == null) {
            return V3ErrorView(
              title: '요청 상태를 불러오지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _reload,
            );
          }
          return _body(context, snap.data!);
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<AcademicRecordChangeRecord> records,
  ) {
    final AcademicRecordChangeRecord? latest =
        records.isEmpty ? null : records.first;
    final bool locked =
        latest != null && latest.status == ReviewStatus.pending;

    return ListView(
      padding: V3Page.contentPadding(context),
      children: <Widget>[
        _StatusHero(latest: latest),
        const SizedBox(height: 12),
        if (locked)
          const V3Callout(
            tone: V3CalloutTone.neutral,
            text: '검토가 끝나면 새 요청을 보낼 수 있어요. 결과는 알림으로 알려드릴게요.',
          )
        else
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('새 요청', style: AppTypography.section),
                const SizedBox(height: 4),
                Text(
                  '편입 · 졸업 · 전과 등으로 학교가 바뀌었다면 증명 서류와 함께 알려 주세요.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                V3Field(
                  label: '변경할 학교명',
                  help: '최대 $kAcademicUniversityNameMax자',
                  error: _universityError,
                  child: AppInputField(
                    controller: _university,
                    hintText: '예: 서울대학교',
                    enabled: !_submitting,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                V3Field(
                  label: '변경 사유 (선택)',
                  help: '최대 $kAcademicChangeReasonMax자',
                  error: _reasonError,
                  child: AppInputField(
                    controller: _reason,
                    hintText: '예: 편입 / 졸업 / 전과 등',
                    enabled: !_submitting,
                    minLines: 2,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                MentorDocumentField(
                  picked: _picked,
                  onPick: _pick,
                  onClear: _clear,
                  enabled: !_submitting,
                  problem: _problem,
                ),
                if (_submitError != null) ...<Widget>[
                  const SizedBox(height: 10),
                  V3Callout(tone: V3CalloutTone.danger, text: _submitError!),
                ],
                const SizedBox(height: AppSpacing.base),
                AppPrimaryButton(
                  label: _submitting ? '제출 중…' : '변경 요청 제출하기',
                  icon: Icons.send_rounded,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
        if (records.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.section),
          const V3SectionTitle('요청 기록'),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: <Widget>[
                for (final AcademicRecordChangeRecord r in records)
                  _RecordRow(record: r),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.latest});

  final AcademicRecordChangeRecord? latest;

  @override
  Widget build(BuildContext context) {
    final AcademicRecordChangeRecord? r = latest;
    final String headline;
    final String sub;
    final Color color;
    final IconData icon;
    if (r == null) {
      headline = '학적 변경을 요청할 수 있어요';
      sub = '승인되면 프로필의 학교명이 바뀌고 학력 인증이 다시 검토돼요';
      color = AppColors.textSecondary;
      icon = Icons.swap_horiz_rounded;
    } else {
      final String requested = r.requestedUniversityName ?? '요청한 학교';
      switch (r.status) {
        case ReviewStatus.pending:
          headline = '요청을 검토하고 있어요';
          sub = '$requested(으)로 변경 요청 · 보통 영업일 2일 안에 끝나요';
          color = AppColors.warning;
          icon = Icons.hourglass_top_rounded;
        case ReviewStatus.approved:
          final String approvedName = r.approvedUniversityName ?? requested;
          headline = '$approvedName(으)로 변경됐어요';
          sub = r.reviewedAt == null
              ? '프로필에 반영됐어요'
              : '${Formatters.koreanDate(r.reviewedAt!.toLocal())}에 승인됐어요';
          color = RoleTheme.of(context).color;
          icon = Icons.verified_rounded;
        case ReviewStatus.rejected:
          headline = '요청이 반려됐어요';
          sub = r.rejectReason ?? '사유가 기록되지 않았어요. 서류를 확인해 다시 요청해 주세요.';
          color = AppColors.danger;
          icon = Icons.cancel_outlined;
        case ReviewStatus.resubmitRequired:
          headline = '서류를 다시 보내 주세요';
          sub = r.rejectReason ?? '안내에 맞춰 서류를 다시 제출해 주세요.';
          color = AppColors.warning;
          icon = Icons.replay_rounded;
        case ReviewStatus.superseded:
          headline = '이전 요청 기록이에요';
          sub = '새 요청을 보내면 다시 검토돼요.';
          color = AppColors.textSecondary;
          icon = Icons.history_rounded;
        case ReviewStatus.unknown:
          headline = '상태를 확인하고 있어요';
          sub = '상태 확인 필요 · 잠시 후 다시 열어 주세요.';
          color = AppColors.warning;
          icon = Icons.help_outline_rounded;
      }
    }
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 32, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(headline, style: AppTypography.section),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final AcademicRecordChangeRecord record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          AppBadge(label: reviewStatusLabel(record.status)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              record.requestedUniversityName ?? '학교명 없음',
              style: AppTypography.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            Formatters.koreanDate(record.createdAt.toLocal()),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
