import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/ui/board/board_detail_screen.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';

import 'fakes.dart';

/// 게시판 상세 — 댓글·좋아요·신고 요소, 신고 시트(외부 연락처 유도 동선), 좋아요 토글 동작.
Widget _wrap(Widget child) => MaterialApp(home: child);

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

BoardDetailScreen _screen(FakeCommunityWrite write) => BoardDetailScreen(
      post: sampleBoard(),
      read: FakeCommunityRead(
        commentsList: <CommunityComment>[sampleComment()],
      ),
      write: write,
    );

void main() {
  testWidgets('상세에 본문·댓글·좋아요·신고 요소가 있다', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(_wrap(_screen(FakeCommunityWrite())));
    await tester.pumpAndSettle();

    expect(find.text('게시판 제목'), findsOneWidget); // 제목
    expect(find.text('본문 내용입니다.'), findsOneWidget); // 본문
    expect(find.textContaining('좋아요'), findsOneWidget); // 좋아요 액션
    expect(find.text('좋은 글이에요.'), findsOneWidget); // 댓글
    expect(find.byTooltip('신고'), findsOneWidget); // 신고 진입
    expect(find.byType(TextField), findsOneWidget); // 댓글 입력창
  });

  testWidgets('좋아요 탭 → write.toggle 호출 + 카운트 증가', (WidgetTester tester) async {
    _bigSurface(tester);
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(_screen(write)));
    await tester.pumpAndSettle();

    expect(find.text('좋아요 3'), findsOneWidget);
    await tester.tap(find.text('좋아요 3'));
    await tester.pumpAndSettle();
    expect(write.reactionCalls, 1);
    expect(find.text('좋아요 4'), findsOneWidget); // 낙관적 증가
  });

  testWidgets('신고 → 시트에 외부 연락처 유도 동선 + 접수 시 write.report 호출',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(_screen(write)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('신고'));
    await tester.pumpAndSettle();

    expect(find.text('신고하기'), findsOneWidget);
    expect(find.text('외부 연락처 유도'), findsOneWidget); // 신고 동선 포함
    expect(find.textContaining('출처·권리'), findsOneWidget); // 출처/권리 문구

    await tester.tap(find.text('신고 접수'));
    await tester.pumpAndSettle();
    expect(write.reportCalls, 1);
    expect(write.lastReportReason, 'inappropriate'); // 기본 선택 사유
    expect(write.lastReportTargetType, 'community_post'); // 글 신고 대상 유지
  });

  testWidgets('댓글 신고 → 대상 테이블은 정본 comments(target_type=comment)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(_screen(write)));
    await tester.pumpAndSettle();

    // 댓글 타일의 ⋯ 메뉴 → 신고 → 시트에서 접수.
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고 접수'));
    await tester.pumpAndSettle();

    expect(write.reportCalls, 1);
    expect(write.lastReportTargetType, 'comment'); // ★ v16 정본 전환
    expect(write.lastReportTargetId, 'c1');
  });

  testWidgets('댓글 등록은 게시판 타입·평면(parentId 없음)으로 호출된다',
      (WidgetTester tester) async {
    _bigSurface(tester);
    // 정책 동의 다이얼로그는 별도 테스트(content_policy_gate_test)에서 검증 — 여기선 통과.
    ContentPolicyGate.agreedThisSession = true;
    addTearDown(() => ContentPolicyGate.agreedThisSession = false);
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(_screen(write)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '새 댓글');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(write.commentCalls, 1);
    expect(write.lastCommentPostType, CommunityPostType.board);
    expect(write.lastCommentParentId, isNull); // 평면 UI — 답글 미전송
  });

  testWidgets('댓글 헤더 수는 표시 중인 댓글 리스트 길이와 일치한다', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(_wrap(_screen(FakeCommunityWrite())));
    await tester.pumpAndSettle();

    // 헤더는 리스트 길이(1) — 카드/반응바의 comment_count(서버 유지 컬럼)와 별개 표기.
    expect(find.text('댓글 1'), findsOneWidget);
  });
}
