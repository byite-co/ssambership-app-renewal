import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/scan/picked_image.dart';
import '../../../core/scan/scan_source_picker.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
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

/// 학력 인증(A-4a #4) — `/profile/education-verification`. design-v3 §4-4.
///
/// 최신 행 기준 4상태(미제출 · 검토 중 · 완료 · 반려/재제출). 검토 중에는 웹과
/// 같이 재제출을 잠근다. 서류 없이 서버가 만든 잠정 행(멘토 승인 시 자동 생성)은
/// "서류 없음 · 관리자 확정 대기"로 구분해 보여준다.
/// 원본 열람(서명 URL)은 2026-07 결정대로 앱 비노출 — 상태·제출일만.
class EducationVerificationScreen extends StatefulWidget {
  const EducationVerificationScreen({
    super.key,
    this.portOverride,
    this.scanPicker = const DeviceScanSourcePicker(),
  });

  final MentorConsolePort? portOverride;
  final ScanSourcePort scanPicker;

  @override
  State<EducationVerificationScreen> createState() =>
      _EducationVerificationScreenState();
}

class _EducationVerificationScreenState
    extends State<EducationVerificationScreen> {
  late final MentorConsolePort _port;
  late Future<List<SchoolVerificationRecord>> _future;

  PickedImage? _picked;
  String? _problem;
  bool _submitting = false;
  String? _submitError;
  bool _showResubmitForm = false;

  @override
  void initState() {
    super.initState();
    _port = widget.portOverride ?? AppScope.of(context).mentorConsole;
    _future = _port.loadSchoolVerifications();
  }

  void _reload() {
    setState(() {
      _future = _port.loadSchoolVerifications();
    });
  }

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

  bool get _canSubmit =>
      !_submitting && _picked != null && _problem == null;

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
      await _port.submitSchoolVerification(document);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('서류를 제출했어요. 검토 결과는 알림으로 알려드릴게요.'),
        ),
      );
      setState(() {
        _picked = null;
        _problem = null;
        _showResubmitForm = false;
        _future = _port.loadSchoolVerifications();
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
      title: '학력 인증',
      body: FutureBuilder<List<SchoolVerificationRecord>>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<SchoolVerificationRecord>> snap,
        ) {
          if (snap.connectionState != ConnectionState.done) {
            return const V3LoadingView(cards: 2);
          }
          if (snap.hasError || snap.data == null) {
            return V3ErrorView(
              title: '인증 상태를 불러오지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _reload,
            );
          }
          return _body(context, snap.data!);
        },
      ),
    );
  }

  Widget _body(BuildContext context, List<SchoolVerificationRecord> records) {
    final SchoolVerificationRecord? latest =
        records.isEmpty ? null : records.first;
    final ReviewStatus status = latest?.status ?? ReviewStatus.unknown;
    final bool locked = latest != null && status == ReviewStatus.pending;
    final bool approved = latest != null && status == ReviewStatus.approved;
    final bool formVisible = !locked && (!approved || _showResubmitForm);

    return ListView(
      padding: V3Page.contentPadding(context),
      children: <Widget>[
        _StatusHero(latest: latest),
        const SizedBox(height: 12),
        if (locked) ...<Widget>[
          V3Callout(
            tone: V3CalloutTone.neutral,
            text: latest.hasDocument
                ? '검토가 끝나면 다른 서류로 다시 제출할 수 있어요.'
                : '서류 없이 관리자 확정을 기다리는 상태예요. 확정되면 결과가 여기에 반영돼요.',
          ),
        ] else if (approved && !_showResubmitForm) ...<Widget>[
          TextButton.icon(
            onPressed: () => setState(() => _showResubmitForm = true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('다른 서류로 다시 인증하기'),
          ),
        ],
        if (formVisible) ...<Widget>[
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  latest == null ? '서류를 올려 주세요' : '서류를 다시 올려 주세요',
                  style: AppTypography.section,
                ),
                const SizedBox(height: 4),
                Text(
                  '재학증명서 · 졸업증명서 · 합격증 중 하나면 돼요. 비공개 저장소에 보관되고 관리자 확인 후 인증돼요.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
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
                  label: _submitting
                      ? '제출 중…'
                      : (latest == null ? '서류 제출하기' : '다시 제출하기'),
                  icon: Icons.upload_rounded,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
        ],
        if (records.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.section),
          const V3SectionTitle('제출 기록'),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: <Widget>[
                for (final SchoolVerificationRecord r in records)
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

  final SchoolVerificationRecord? latest;

  @override
  Widget build(BuildContext context) {
    final SchoolVerificationRecord? r = latest;
    final String headline;
    final String sub;
    final V3CalloutTone tone;
    final IconData icon;
    if (r == null) {
      headline = '아직 인증하지 않았어요';
      sub = '인증한 멘토는 학생이 더 믿고 구독해요';
      tone = V3CalloutTone.neutral;
      icon = Icons.school_outlined;
    } else {
      switch (r.status) {
        case ReviewStatus.approved:
          headline = '인증이 완료됐어요';
          final List<String> values = <String>[
            if (r.verifiedUniversityName != null) r.verifiedUniversityName!,
            if (r.verifiedDepartmentName != null) r.verifiedDepartmentName!,
          ];
          final String when = r.reviewedAt == null
              ? ''
              : '${Formatters.koreanDate(r.reviewedAt!.toLocal())}에 승인됐어요';
          sub = <String>[
            if (values.isNotEmpty) values.join(' · '),
            if (when.isNotEmpty) when,
          ].join('\n');
          tone = V3CalloutTone.success;
          icon = Icons.verified_rounded;
        case ReviewStatus.pending:
          headline = '서류를 확인하고 있어요';
          sub = r.hasDocument
              ? '보통 영업일 2일 안에 끝나요. 결과는 알림으로 알려드릴게요.'
              : '서류 없음 · 관리자 확정 대기';
          tone = V3CalloutTone.warning;
          icon = Icons.hourglass_top_rounded;
        case ReviewStatus.rejected:
          headline = '서류가 반려됐어요';
          sub = r.rejectReason ?? '사유가 기록되지 않았어요. 서류를 다시 제출해 주세요.';
          tone = V3CalloutTone.danger;
          icon = Icons.cancel_outlined;
        case ReviewStatus.resubmitRequired:
          headline = '서류를 다시 보내 주세요';
          sub = r.rejectReason ?? '안내에 맞춰 서류를 다시 제출해 주세요.';
          tone = V3CalloutTone.warning;
          icon = Icons.replay_rounded;
        case ReviewStatus.superseded:
          headline = '이전 인증 기록이에요';
          sub = '새 서류를 제출하면 다시 검토돼요.';
          tone = V3CalloutTone.neutral;
          icon = Icons.history_rounded;
        case ReviewStatus.unknown:
          headline = '상태를 확인하고 있어요';
          sub = '상태 확인 필요 · 잠시 후 다시 열어 주세요.';
          tone = V3CalloutTone.warning;
          icon = Icons.help_outline_rounded;
      }
    }
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 32, color: _toneColor(context, tone)),
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

  static Color _toneColor(BuildContext context, V3CalloutTone tone) {
    switch (tone) {
      case V3CalloutTone.success:
        return RoleTheme.of(context).color;
      case V3CalloutTone.warning:
        return AppColors.warning;
      case V3CalloutTone.danger:
        return AppColors.danger;
      case V3CalloutTone.neutral:
        return AppColors.textSecondary;
    }
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final SchoolVerificationRecord record;

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
              record.hasDocument ? '서류 제출' : '서류 없음 · 자동 생성',
              style: AppTypography.body,
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
