import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/mentor_profile_edit_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';
import '../support/fake_scan_port.dart';
import '../support/mentor_document_fixtures.dart';

/// 멘토 프로필 편집(A-4a α1·α2·α3) — 9필드 전면 전송 · 과목 정본 코드 · 열림 토글 · 사진.
void main() {
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  MentorOwnProfile profile({
    List<String> subjects = const <String>['수학', 'math_calculus', '코딩'],
    bool open = true,
    String? image,
  }) =>
      MentorOwnProfile(
        userId: 'm1',
        universityName: '서울대학교',
        departmentName: '의예과',
        highSchoolName: '한국고',
        teachingSubjects: subjects,
        introLine: '수능 수학 1등급의 풀이 습관',
        bio: '개념부터 실전까지.',
        answerStyle: '단계별 풀이',
        profileImageUrl: image,
        isOpenForSubscriptions: open,
        verificationStatus: 'approved',
      );

  Widget app(FakeMentorConsole port, {FakeScanPort? scan}) => withTestAppScope(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: MentorProfileEditScreen(
            portOverride: port,
            scanPicker: scan ?? FakeScanPort(result: jpgDocument(name: 'me.jpg')),
          ),
        ),
        auth: TestAppAuth(role: AppRole.mentor, userId: 'm1'),
      );

  Finder fieldUnder(String label) => find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(Column),
        ).first,
        matching: find.byType(TextField),
      );

  testWidgets('현재 값이 채워지고, 저장은 9필드를 한 번에 · 과목은 정본 코드만', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(profile: profile());
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    expect(find.text('서울대학교'), findsOneWidget);
    expect(find.text('의예과'), findsOneWidget);
    expect(find.text('수능 수학 1등급의 풀이 습관'), findsOneWidget);
    // '수학'(라벨)·'math_calculus'(코드) → 2개 선택, 자유 라벨 '코딩'은 제외.
    expect(find.text('2개 선택'), findsNothing); // 문장 안에 포함되어 있음.
    expect(find.textContaining('2개 선택'), findsOneWidget);
    expect(find.textContaining('math'), findsNothing); // 코드 비노출.

    // 과목 하나 추가(영어), 소개 수정, 열림 끄기.
    await tester.tap(find.text('영어'));
    await tester.enterText(fieldUnder('한줄 소개'), '영어도 함께');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('3개 선택'), findsOneWidget);
    expect(find.text('새 구독 신청을 받지 않아요. 이미 구독 중인 학생은 그대로예요.'),
        findsOneWidget);

    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    final Map<String, Object?> call = port.calls.single;
    expect(call['name'], 'updateOwnProfile');
    expect(call['p_university_name'], '서울대학교');
    expect(call['p_department_name'], '의예과');
    expect(call['p_high_school_name'], '한국고');
    expect(call['p_teaching_subjects'], <String>['english', 'math', 'math_calculus']);
    expect(call['p_intro_line'], '영어도 함께');
    expect(call['p_bio'], '개념부터 실전까지.');
    expect(call['p_answer_style'], '단계별 풀이');
    expect(call['p_profile_image_url'], isNull);
    expect(call['p_is_open_for_subscriptions'], false);
    expect(find.text('프로필을 저장했어요.'), findsOneWidget);
  });

  testWidgets('대학교·학과를 비우면 저장 비활성 · 41자는 사유 문장', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(profile: profile());
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    await tester.enterText(fieldUnder('학과 (필수)'), '   ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);

    await tester.enterText(fieldUnder('학과 (필수)'), '의예과');
    await tester.enterText(fieldUnder('대학교 (필수)'), '가' * 41);
    await tester.pumpAndSettle();
    expect(find.text('대학교은(는) 40자까지 입력할 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);

    await tester.enterText(fieldUnder('대학교 (필수)'), '연세대학교');
    await tester.enterText(fieldUnder('상세 소개'), '나' * 501);
    await tester.pumpAndSettle();
    expect(find.text('상세 소개은(는) 500자까지 입력할 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);
  });

  testWidgets('사진 올리기: 촬영/갤러리 시트 → 업로드 → URL 이 저장 payload 에 실린다', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(profile: profile());
    final FakeScanPort scan = FakeScanPort(result: jpgDocument(name: 'me.jpg'));
    await tester.pumpWidget(app(port, scan: scan));
    await tester.pumpAndSettle();

    expect(find.text('사진 올리기'), findsOneWidget);
    await tester.tap(find.text('사진 올리기'));
    await tester.pumpAndSettle();
    expect(find.text('프로필 사진'), findsWidgets); // 시트 제목.
    expect(find.text('파일'), findsNothing); // 사진은 촬영/갤러리만.
    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();

    expect(scan.calls, <ScanSource>[ScanSource.gallery]);
    expect(port.calls.first['name'], 'uploadAvatar');
    expect(find.text('사진 바꾸기'), findsOneWidget);
    expect(find.text('사진 지우기'), findsOneWidget);

    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(port.calls.last['p_profile_image_url'], port.avatarUrl);
  });

  testWidgets('사진 지우기 → null 로 저장 · 형식 밖 사진은 사유 문장', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(
      profile: profile(image: 'https://example.test/profile-avatars/m1/old.jpg'),
    );
    // PDF 는 사진이 아니다 — 첨부 규약(validatePickedImage)과 같은 문구로 거부.
    final FakeScanPort scan = FakeScanPort(result: pdfDocument());
    await tester.pumpWidget(app(port, scan: scan));
    await tester.pumpAndSettle();

    await tester.tap(find.text('사진 바꾸기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('촬영'));
    await tester.pumpAndSettle();
    expect(find.text('이미지(JPG·PNG) 형식만 올릴 수 있어요.'), findsOneWidget);
    expect(port.calls, isEmpty); // 업로드 안 함.

    await tester.tap(find.text('사진 지우기'));
    await tester.pumpAndSettle();
    expect(find.text('사진 올리기'), findsOneWidget);
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(port.calls.single['p_profile_image_url'], isNull);
  });

  testWidgets('서버 거부(코드) → 인라인 문구 · 입력 유지', (WidgetTester tester) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(profile: profile())
      ..failWith = const AppError('프로필 사진 참조가 올바르지 않아요. 사진을 다시 올려 주세요.');
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(find.text('프로필 사진 참조가 올바르지 않아요. 사진을 다시 올려 주세요.'),
        findsOneWidget);
    expect(find.text('서울대학교'), findsOneWidget);
  });

  testWidgets('조회 실패 → 오류 + 다시 시도', (WidgetTester tester) async {
    final FakeMentorConsole port = FakeMentorConsole(profile: profile())
      ..loadFailure = const AppError('네트워크 오류');
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text('프로필을 불러오지 못했어요'), findsOneWidget);
    port.loadFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('서울대학교'), findsOneWidget);
  });
}
