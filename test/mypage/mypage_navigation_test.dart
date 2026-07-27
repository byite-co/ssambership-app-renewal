import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/home_shell.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/shared/constants/app_constants.dart';

/// 마이페이지 → 알림/받은 질문 보기 '실제 화면 이동' 검증.
///
/// 결함 배경: 마이페이지는 HomeShell 위에 push 된 route 라서 TabNavigator 로
/// 숨은 탭 index 만 바꾸면 사용자에게는 무반응으로 보였다. 수정 후에는
/// route 를 pop 하면서 탭 index 를 반환하고 HomeShell 이 실제 보이는 탭을 전환한다.
/// 콜백 호출 여부가 아니라 '마이페이지 닫힘 + 목적지 화면 등장'을 검증한다.

MyPageData _studentData() => const MyPageData(
      role: AppRole.student,
      profile: MyProfile(name: '탐색학생', roleLabel: '학생', grade: '고2'),
    );

MyPageData _mentorData() => const MyPageData(
      role: AppRole.mentor,
      profile: MyProfile(name: '탐색멘토', roleLabel: '멘토'),
      mentor: MentorDashboard(
        studentCount: 1,
        pendingAnswers: 0,
        latestSettlementCents: 0,
      ),
    );

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openMyPage(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.person_rounded));
  await tester.pumpAndSettle();
  expect(find.text(AppConstants.myPageTitle), findsWidgets); // push 확인
}

void main() {
  testWidgets('학생: 마이페이지 → 알림 → 마이페이지 닫힘 + 알림 탭 화면 등장',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(myPageLoaderOverride: () async => _studentData()),
    ));
    await tester.pumpAndSettle();

    await _openMyPage(tester);
    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();

    // 마이페이지 route 닫힘 + 실제 보이는 탭이 알림(3)으로 전환.
    expect(find.text(AppConstants.myPageTitle), findsNothing);
    expect(
        find.text(AppConstants.bottomTabLabels[3]), findsWidgets); // AppBar 제목
    final NavigationBar bar =
        tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 3);
  });

  testWidgets('멘토: 마이페이지 → 알림 실제 이동(역할 무관 동일 동작)', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(myPageLoaderOverride: () async => _mentorData()),
    ));
    await tester.pumpAndSettle();

    await _openMyPage(tester);
    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();

    expect(find.text(AppConstants.myPageTitle), findsNothing);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3);
  });

  testWidgets('멘토: 받은 질문 보기 → 마이페이지 닫힘 + 질문방 탭 등장(동일 원인 수정)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(myPageLoaderOverride: () async => _mentorData()),
    ));
    await tester.pumpAndSettle();

    await _openMyPage(tester);
    await tester.tap(find.text('받은 질문 보기'));
    await tester.pumpAndSettle();

    expect(find.text(AppConstants.myPageTitle), findsNothing);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0); // 질문방 탭
    expect(find.text(AppConstants.bottomTabLabels[0]), findsWidgets);
  });

  testWidgets('뒤로가기 스택: 마이페이지를 그냥 닫으면 원래 탭 유지·크래시 없음',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(myPageLoaderOverride: () async => _studentData()),
    ));
    await tester.pumpAndSettle();
    final int before =
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    await _openMyPage(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text(AppConstants.myPageTitle), findsNothing);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        before);
    expect(tester.takeException(), isNull);
  });
}
