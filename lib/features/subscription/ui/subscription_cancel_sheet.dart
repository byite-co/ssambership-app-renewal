import 'package:flutter/material.dart';

import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_secondary_button.dart';
import '../../../design/widgets/glass_bars.dart';
import '../../../shared/format/formatters.dart';

/// 구독 해지 예약·취소 확인 시트(design-v3 §5-8 · A-4b §2-3).
///
/// 위험색은 확인 버튼에만. 남은 기간을 먼저 알린다. 결과 `true` = 확인.
class SubscriptionCancelSheet {
  SubscriptionCancelSheet._();

  /// 해지 예약 확인 — `다음 결제가 중단돼요. 9월 13일까지는 계속 쓸 수 있어요.`
  static Future<bool?> confirmSchedule(
    BuildContext context, {
    required String mentorName,
    String? planLabel,
    DateTime? periodEnd,
  }) {
    final String until = periodEnd == null
        ? '남은 기간에는'
        : '${Formatters.monthDay(periodEnd)}까지는';
    return _show(
      context,
      heading: planLabel == null ? mentorName : '$mentorName · $planLabel',
      title: '정말 해지할까요?',
      body: '다음 결제가 중단돼요. $until 계속 쓸 수 있어요.',
      note: '해지가 확정되면 이 멘토와의 질문방은 읽기만 할 수 있어요. 언제든 다시 구독할 수 있어요.',
      confirmLabel: '해지 예약',
      danger: true,
    );
  }

  /// 해지 예약 취소 확인 — 다음 결제가 다시 진행됨을 명시(오너 결정 4-a).
  static Future<bool?> confirmUndo(
    BuildContext context, {
    required String mentorName,
    String? planLabel,
    DateTime? periodEnd,
  }) {
    final String when =
        periodEnd == null ? '다음 결제일에' : '${Formatters.monthDay(periodEnd)}에';
    final String plan = planLabel == null ? '' : ' $planLabel 요금제로';
    return _show(
      context,
      heading: planLabel == null ? mentorName : '$mentorName · $planLabel',
      title: '해지 예약을 취소할까요?',
      body: '$when$plan 다음 결제가 캐시로 다시 진행돼요.',
      note: '취소하면 구독이 그대로 이어지고, 해지는 다시 예약할 수 있어요.',
      confirmLabel: '해지 취소',
      danger: false,
    );
  }

  static Future<bool?> _show(
    BuildContext context, {
    required String heading,
    required String title,
    required String body,
    required String note,
    required String confirmLabel,
    required bool danger,
  }) {
    return GlassBottomSheet.show<bool>(
      context,
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 6),
          Text(heading, style: AppTypography.captionSecondary),
          const SizedBox(height: 6),
          Text(title, style: AppTypography.section),
          const SizedBox(height: AppSpacing.s12),
          Text(body, style: AppTypography.body),
          const SizedBox(height: AppSpacing.s8),
          Text(note, style: AppTypography.captionSecondary),
          const SizedBox(height: AppSpacing.s20),
          Row(
            children: <Widget>[
              Expanded(
                child: AppSecondaryButton(
                  label: '닫기',
                  filled: false,
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppSecondaryButton(
                  label: confirmLabel,
                  danger: danger,
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
