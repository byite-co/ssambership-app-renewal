import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/features/community/community_screen.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';

import 'fakes.dart';

/// 커뮤니티 탭 셸 — 숏폼/게시판/내활동 탭 + 각 탭 카드 렌더(mock 주입, DB 미접촉).
Widget _wrap(Widget child) => MaterialApp(home: child);

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('상단 탭(숏폼/게시판/내 활동)이 존재하고, 숏폼 카드가 렌더된다',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(_wrap(CommunityScreen(
      read: FakeCommunityRead(shortformsList: <ShortformPost>[sampleShortform()]),
      write: FakeCommunityWrite(),
    )));
    await tester.pumpAndSettle();

    // 탭 3종
    expect(find.text('숏폼'), findsOneWidget);
    expect(find.text('게시판'), findsOneWidget);
    expect(find.text('내 활동'), findsOneWidget);

    // 숏폼 카드(제목·좋아요·조회수)
    expect(find.text('숏폼 제목'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // 좋아요
    expect(find.text('69'), findsOneWidget); // 조회수
  });

  testWidgets('게시판 탭 → 카테고리칩 + 글 카드(제목·댓글수)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(_wrap(CommunityScreen(
      read: FakeCommunityRead(boardsList: <BoardPost>[sampleBoard()]),
      write: FakeCommunityWrite(),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('게시판'));
    await tester.pumpAndSettle();

    // 카테고리칩
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('학습법'), findsWidgets); // 칩 + 카드 배지(웹 정본 라벨)
    // 글 카드
    expect(find.text('게시판 제목'), findsOneWidget);
    expect(find.text('7'), findsOneWidget); // 댓글수
  });

  testWidgets('작성 FAB(멘토): 게시판 탭에서만 노출(숏폼·내활동 없음)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(_wrap(CommunityScreen(
      read: const FakeCommunityRead(),
      write: FakeCommunityWrite(),
      roleOf: () => AppRole.mentor,
    )));
    await tester.pumpAndSettle();

    // 숏폼 탭(기본): FAB 없음.
    expect(find.byType(FloatingActionButton), findsNothing);

    // 게시판 탭: '작성' FAB 노출.
    await tester.tap(find.text('게시판'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FloatingActionButton, '작성'), findsOneWidget);

    // 내 활동 탭: FAB 없음.
    await tester.tap(find.text('내 활동'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('작성 FAB: 학생·게스트에게는 게시판 탭에서도 미노출(§6.5 승인 멘토 전용)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    for (final AppRole role in <AppRole>[AppRole.student, AppRole.guest]) {
      await tester.pumpWidget(_wrap(CommunityScreen(
        read: const FakeCommunityRead(),
        write: FakeCommunityWrite(),
        roleOf: () => role,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('게시판'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing,
          reason: '$role 은 작성 CTA 를 볼 수 없다');
    }
  });
}
