import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/ui/board/board_list_view.dart';

import 'fakes.dart';

/// 게시판 카테고리 필터 칩의 선택 표시 회귀.
///
/// 증상: 칩을 탭하면 목록 필터링은 되는데(pager 알림 경로) 선택 표시(활성 스타일)는
/// '전체' 칩에 고정된 채 움직이지 않았다 — _selectCategory 가 setState 없이
/// _category 만 바꿔, build() 에서 계산되는 selected 인덱스가 재계산되지 않았다.
/// 활성 판정은 chip_scroll.dart 의 스타일 계약(활성 w800 · 비활성 w600)으로 한다.
void main() {
  FontWeight? weightOf(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.fontWeight;

  testWidgets('칩 탭 → 선택 표시가 탭한 칩으로 이동하고 이전 칩은 비활성',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BoardListView(
          read: const FakeCommunityRead(),
          write: FakeCommunityWrite(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 초기: '전체' 활성.
    expect(weightOf(tester, '전체'), FontWeight.w800);
    expect(weightOf(tester, '학습법'), FontWeight.w600);

    await tester.tap(find.text('학습법'));
    await tester.pumpAndSettle();

    // 탭 후: 탭한 칩이 활성, '전체'는 비활성으로 돌아간다.
    expect(weightOf(tester, '학습법'), FontWeight.w800);
    expect(weightOf(tester, '전체'), FontWeight.w600);
  });
}
