import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';

import 'golden_harness.dart';

/// A-4b ⑧ 개별질문 등록(공개형) v2 — 앱바 과목 액션 → 과목 선택 시트.
void main() {
  testWidgets('golden: a4b_iq_create_subject', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      IqCreateScreen(
        prefillOverride: () async => const IqCreatePrefill(balanceCents: 1000000),
      ),
      role: AppRole.student,
    );
    await tester.tap(find.byKey(const ValueKey<String>('iq-subject-action')));
    await tester.pumpAndSettle();
    expect(find.text('과목을 골라 주세요'), findsOneWidget);
    expect(find.text('수학'), findsOneWidget);
    await expectScreenGolden(tester, 'a4b_iq_create_subject');
  });
}
