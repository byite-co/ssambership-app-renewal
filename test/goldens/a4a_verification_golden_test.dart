import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/education_verification_screen.dart';

import '../support/fake_mentor_console.dart';
import '../support/fake_scan_port.dart';
import 'golden_harness.dart';

/// A-4a #4 학력 인증(미제출 · 재제출 필요).
void main() {
  testWidgets('golden: a4a_education_verification', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      EducationVerificationScreen(
        portOverride: FakeMentorConsole(),
        scanPicker: FakeScanPort(),
      ),
      role: AppRole.mentor,
    );
    expect(find.text('아직 인증하지 않았어요'), findsOneWidget);
    await expectScreenGolden(tester, 'a4a_education_verification');
  });

  testWidgets('golden: a4a_education_verification_resubmit', (
    WidgetTester tester,
  ) async {
    await pumpGoldenScreen(
      tester,
      EducationVerificationScreen(
        portOverride: FakeMentorConsole(
          schoolVerifications: <SchoolVerificationRecord>[
            SchoolVerificationRecord(
              id: 'v2',
              status: ReviewStatus.resubmitRequired,
              documentStorageRef: 'student-id-images/m1/school-verifications/b.pdf',
              rejectReason:
                  '제출한 증명서의 발급일이 6개월을 넘었어요. 최근 3개월 안에 발급받은 서류가 필요해요.',
              createdAt: DateTime(2026, 8, 20),
            ),
            SchoolVerificationRecord(
              id: 'v1',
              status: ReviewStatus.superseded,
              documentStorageRef: 'student-id-images/m1/school-verifications/a.jpg',
              createdAt: DateTime(2026, 7, 2),
            ),
          ],
        ),
        scanPicker: FakeScanPort(),
      ),
      role: AppRole.mentor,
    );
    expect(find.text('서류를 다시 보내 주세요'), findsOneWidget);
    await expectScreenGolden(tester, 'a4a_education_verification_resubmit');
  });

}
