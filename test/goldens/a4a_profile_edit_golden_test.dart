import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/mentor_profile_edit_screen.dart';

import '../support/fake_mentor_console.dart';
import '../support/fake_scan_port.dart';
import 'golden_harness.dart';

/// A-4a α1·α2·α3 멘토 프로필 편집 — 사진 없음 · 구독 열림 · 학력 채워진 상단.
void main() {
  testWidgets('golden: a4a_mentor_profile_edit', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      MentorProfileEditScreen(
        portOverride: FakeMentorConsole(
          profile: const MentorOwnProfile(
            userId: 'm1',
            universityName: '서울대학교',
            departmentName: '의예과',
            highSchoolName: '한국고등학교',
            teachingSubjects: <String>['math', 'math_calculus'],
            introLine: '수능 수학 1등급의 풀이 습관을 만들어요',
            bio: '개념을 먼저 잡고, 기출로 확인하고, 실전 감각을 붙여요.',
            answerStyle: '단계별 풀이',
            verificationStatus: 'approved',
          ),
        ),
        scanPicker: FakeScanPort(),
      ),
      role: AppRole.mentor,
    );
    expect(find.text('서울대학교'), findsOneWidget);
    await expectScreenGolden(tester, 'a4a_mentor_profile_edit');
  });
}
