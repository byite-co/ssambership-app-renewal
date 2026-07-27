import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/data/profile_edit_repository.dart';
import 'package:ssambership_app/features/mypage/ui/profile_edit_screen.dart';

/// 학생 프로필 수정 — 학년 필드의 라벨·초깃값(controller)·저장 payload 가
/// 전부 `grade_level` 로 일치하는지 고정(학교명 표시·저장 바인딩 오류 없음).

class _CapturingRepo extends ProfileEditRepository {
  const _CapturingRepo(this.captured);

  final Map<String, String?> captured;

  @override
  Future<void> updateProfile({String? nickname, String? gradeLevel}) async {
    captured['nickname'] = nickname;
    captured['gradeLevel'] = gradeLevel;
  }
}

void main() {
  testWidgets('라벨=학년 (선택) · 초깃값=grade · 저장 payload=grade_level 값',
      (WidgetTester tester) async {
    final Map<String, String?> captured = <String, String?>{};
    await tester.pumpWidget(MaterialApp(
      home: ProfileEditScreen(
        profile: const MyProfile(name: '학생', roleLabel: '학생', grade: '고2'),
        repository: _CapturingRepo(captured),
      ),
    ));
    await tester.pumpAndSettle();

    // 라벨은 '학년' — 학교 문구가 아니어야 한다.
    expect(find.text('학년 (선택)'), findsOneWidget);
    expect(find.textContaining('학교'), findsNothing);

    // 초깃값: grade_level 미러(grade) 값이 controller 에 들어간다.
    expect(find.widgetWithText(TextField, '고2'), findsOneWidget);

    // 값 변경 후 저장 → payload 의 gradeLevel(=grade_level 컬럼)로 전달.
    await tester.enterText(find.widgetWithText(TextField, '고2'), '고3');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(captured['gradeLevel'], '고3');
  });
}
