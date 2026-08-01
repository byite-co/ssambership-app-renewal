import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/ui/board/board_list_view.dart';

import 'fakes.dart';

/// D-3 게스트 열람 회귀: 목록·로딩·오류·빈 상태가 세션 없이도 정상 렌더된다.
BoardPost _post({String id = 'p1', String title = '첫 글', String? role}) =>
    BoardPost(
      id: id,
      title: title,
      body: '본문',
      category: 'free',
      authorRole: role,
      likeCount: 0,
      commentCount: 0,
      viewCount: 0,
      createdAt: DateTime(2026, 7, 1),
    );

/// 조회를 실패시키는 읽기 레포(오류 상태 검증용).
class _FailingRead extends CommunityReadRepository {
  const _FailingRead();

  @override
  Future<CommunityPage<BoardPost>> boards(
      {String? category, int? limit, int offset = 0}) async {
    throw Exception('anon read failed');
  }
}

/// 응답을 보류해 로딩 상태를 관찰할 수 있는 읽기 레포.
class _PendingRead extends CommunityReadRepository {
  _PendingRead();

  final Completer<CommunityPage<BoardPost>> gate =
      Completer<CommunityPage<BoardPost>>();

  @override
  Future<CommunityPage<BoardPost>> boards(
          {String? category, int? limit, int offset = 0}) =>
      gate.future;
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('게스트: 게시판 목록이 렌더된다(세션 없이 열람 가능)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(BoardListView(
      read: FakeCommunityRead(boardsList: <BoardPost>[
        _post(title: '익명으로 보이는 글'),
      ]),
      write: FakeCommunityWrite(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('익명으로 보이는 글'), findsOneWidget);
  });

  testWidgets('게스트: 빈 목록 → 빈 상태 안내(오류로 위장하지 않는다)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(BoardListView(
      read: const FakeCommunityRead(),
      write: FakeCommunityWrite(),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('불러오지 못했'), findsNothing);
  });

  testWidgets('게스트: 조회 실패 → 오류 안내(빈 상태로 위장하지 않는다)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(BoardListView(
      read: const _FailingRead(),
      write: FakeCommunityWrite(),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('불러오지 못했'), findsOneWidget);
  });

  testWidgets('게스트: 응답 전에는 로딩 표시', (WidgetTester tester) async {
    final _PendingRead read = _PendingRead();
    await tester.pumpWidget(_wrap(BoardListView(
      read: read,
      write: FakeCommunityWrite(),
    )));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    read.gate.complete(const CommunityPage<BoardPost>(
      items: <BoardPost>[],
      rawCount: 0,
      nextOffset: 0,
      hasMore: false,
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('작성자 표기는 한글 라벨 — UUID·영문 역할코드 비노출',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(BoardListView(
      read: FakeCommunityRead(boardsList: <BoardPost>[
        _post(role: 'mentor'),
        _post(id: 'p2', title: '둘째 글', role: 'student'),
      ]),
      write: FakeCommunityWrite(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('mentor'), findsNothing);
    expect(find.text('student'), findsNothing);
  });

  testWidgets('열람만으로는 어떤 쓰기도 발생하지 않는다', (WidgetTester tester) async {
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(BoardListView(
      read: FakeCommunityRead(boardsList: <BoardPost>[_post()]),
      write: write,
    )));
    await tester.pumpAndSettle();

    expect(write.postCalls, 0);
    expect(write.commentCalls, 0);
    expect(write.reactionCalls, 0);
    expect(write.reportCalls, 0);
  });
}
