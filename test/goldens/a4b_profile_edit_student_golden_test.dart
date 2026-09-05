import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/data/profile_edit_repository.dart';
import 'package:ssambership_app/features/mypage/ui/profile_edit_screen.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

class _NoBackend implements ProfileEditBackend {
  const _NoBackend();
  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) =>
      throw UnsupportedError('golden');
}

/// A-4b ⑥ 학생 프로필 편집 — 표시명·학년·재학 상태 필드.
void main() {
  testWidgets('golden: a4b_profile_edit_student', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      const ProfileEditScreen(
        profile: MyProfile(
          name: kStudentName,
          roleLabel: '학생',
          email: 'student@example.com',
          grade: '고2',
          studentStatus: '재학 중',
        ),
        repository: ProfileEditRepository(backend: _NoBackend()),
      ),
      role: AppRole.student,
    );
    expect(find.text('재학 상태 (선택)'), findsOneWidget);
    await expectScreenGolden(tester, 'a4b_profile_edit_student');
  });
}
