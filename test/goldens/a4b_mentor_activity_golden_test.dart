import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mypage/ui/sections/mentor_self_service_section.dart';
import 'package:ssambership_app/shared/constants/app_constants.dart';

import '../support/fake_mentor_console.dart';
import '../support/fake_scan_port.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// A-4b ④⑦ — 멘토 마이페이지 활동 상태·학생증 섹션 위에 '잠시 쉬기' 시트.
void main() {
  testWidgets('golden: a4b_mentor_activity_pause_sheet', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text(AppConstants.myPageTitle)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: <Widget>[
            MentorSelfServiceSections(
              port: FakeMentorConsole(
                profile: const MentorOwnProfile(
                  userId: kMentorId,
                  verificationStatus: 'approved',
                  activityStatus: 'active',
                ),
                schoolVerifications: <SchoolVerificationRecord>[
                  SchoolVerificationRecord(
                    id: 'v1',
                    status: ReviewStatus.pending,
                    createdAt: DateTime(2026, 9, 1),
                  ),
                ],
              ),
              scanPicker: FakeScanPort(),
              nowOverride: () => DateTime(2026, 9, 5, 10),
            ),
          ],
        ),
      ),
      role: AppRole.mentor,
    );
    expect(find.text('활동 중'), findsOneWidget);
    expect(find.textContaining('서류 없음 · 관리자 확정 대기'), findsOneWidget);
    await tester.tap(find.text('잠시 쉬기'));
    await tester.pumpAndSettle();
    expect(find.text('9월 8일에 자동으로 복귀해요'), findsOneWidget);
    await expectScreenGolden(tester, 'a4b_mentor_activity_pause_sheet');
  });
}
