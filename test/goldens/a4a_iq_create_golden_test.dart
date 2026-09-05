import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';

import 'golden_harness.dart';

/// A-4a #11 개별질문 등록(네이티브 개방) — 공개형(잔액 충분) · 지정형(잔액 부족).
/// ★ 두 장 모두 충전 유도 문구·링크 0.
void main() {
  testWidgets('golden: a4a_iq_create_open', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      IqCreateScreen(
        prefillOverride: () async =>
            const IqCreatePrefill(balanceCents: 1200000), // 12,000캐시
      ),
      role: AppRole.student,
    );
    expect(find.text('내 캐시'), findsOneWidget);
    expect(find.textContaining('충전'), findsNothing);
    await expectScreenGolden(tester, 'a4a_iq_create_open');
  });

  testWidgets('golden: a4a_iq_create_insufficient', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      IqCreateScreen(
        mentorId: 'm1',
        mentorName: '김민서',
        prefillOverride: () async => const IqCreatePrefill(
          balanceCents: 150000, // 1,500캐시
          pricing: IqPricing(mentorId: 'm1', amountCents: 250000), // 2,500캐시
        ),
      ),
      role: AppRole.student,
    );
    expect(find.text('잔액이 부족해요'), findsOneWidget);
    expect(find.textContaining('충전'), findsNothing);
    await expectScreenGolden(tester, 'a4a_iq_create_insufficient');
  });
}
