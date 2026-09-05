import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/data/profile_edit_repository.dart';
import 'package:ssambership_app/features/mypage/ui/profile_edit_screen.dart';

import '../support/app_scope_test_harness.dart';

class _FakeBackend implements ProfileEditBackend {
  final List<(String, Map<String, dynamic>)> calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) async {
    calls.add((fn, Map<String, dynamic>.of(params)));
    return <String, dynamic>{'ok': true, 'contract_version': 1};
  }
}

/// A-4b ⑥ 재학 상태 — 학생 프로필 편집 필드 + v2 RPC 전환(값 있을 때만).
void main() {
  group('레포지토리', () {
    test('재학 상태 경로는 v2 · 종전 경로는 v1 그대로(감소 0)', () async {
      final _FakeBackend b = _FakeBackend();
      final ProfileEditRepository repo = ProfileEditRepository(backend: b);
      await repo.updateProfileWithStudentStatus(nickname: '닉', gradeLevel: '고2', studentStatus: '재학 중');
      expect(b.calls.single.$1, 'user_profile_update_self_v2');
      expect(b.calls.single.$2, <String, dynamic>{
        'p_nickname': '닉', 'p_grade_level': '고2', 'p_student_status': '재학 중',
      });
      await repo.updateProfile(nickname: '닉2');
      expect(b.calls.last.$1, 'user_profile_update_self');
      expect(b.calls.last.$2.containsKey('p_student_status'), isFalse);
      // 비우기 = '' 전송(v2).
      await repo.updateProfileWithStudentStatus(nickname: '닉3', studentStatus: '');
      expect(b.calls.last.$1, 'user_profile_update_self_v2');
      expect(b.calls.last.$2['p_student_status'], '');
    });
  });

  group('화면', () {
    Widget app(ProfileEditRepository repo, {AppRole role = AppRole.student, String? status}) =>
        withTestAppScope(
          MaterialApp(
            home: ProfileEditScreen(
              profile: MyProfile(name: '로컬학생', roleLabel: '학생', grade: '고2', studentStatus: status),
              repository: repo,
            ),
          ),
          auth: TestAppAuth(role: role, userId: 's1'),
        );

    testWidgets('학생: 재학 상태 필드(20자) · 저장 payload · 성공 안내', (tester) async {
      final _FakeBackend b = _FakeBackend();
      await tester.pumpWidget(app(ProfileEditRepository(backend: b), status: '휴학'));
      await tester.pumpAndSettle();
      expect(find.text('재학 상태 (선택)'), findsOneWidget);
      expect(find.text('휴학'), findsOneWidget);
      final Finder field = find.descendant(
        of: find.ancestor(of: find.text('재학 상태 (선택)'), matching: find.byType(Column)).first,
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).maxLength, 20);
      await tester.enterText(field, '재학 중');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(b.calls.single.$1, 'user_profile_update_self_v2');
      expect(b.calls.single.$2['p_student_status'], '재학 중');
      expect(b.calls.single.$2['p_grade_level'], '고2');
    });

    testWidgets('멘토: 재학 상태 필드 없음 · v1 경로', (tester) async {
      final _FakeBackend b = _FakeBackend();
      await tester.pumpWidget(app(ProfileEditRepository(backend: b), role: AppRole.mentor));
      await tester.pumpAndSettle();
      expect(find.text('재학 상태 (선택)'), findsNothing);
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(b.calls.single.$1, 'user_profile_update_self');
      expect(b.calls.single.$2.containsKey('p_student_status'), isFalse);
    });
  });
}
