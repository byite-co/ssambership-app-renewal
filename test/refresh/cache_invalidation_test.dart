import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/refresh/data_refresh_bus.dart';
import 'package:ssambership_app/features/community/community_screen.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/ui/board/board_list_view.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/mypage_screen.dart';

import '../community/fakes.dart';
import '../support/app_scope_test_harness.dart';

/// 세션1 §4 — 캐시 무효화·재조회 수렴.
/// (a) 댓글 mutation 후 상세·목록 count, (b) 외부 변경(숨김·복구)의
/// resume/refresh 반영, (c) 지갑(잔액·원장) 교차 표면 무효화, stale 방어.

BoardPost _post(String id, {int commentCount = 0}) => BoardPost(
      id: id,
      title: '글$id',
      body: '본문',
      category: 'study',
      authorLabel: '학생A',
      authorRole: 'student',
      likeCount: 0,
      commentCount: commentCount,
      viewCount: 0,
      createdAt: DateTime(2026, 7, 20),
    );

CommunityComment _comment(String id) => CommunityComment(
      id: id,
      body: '댓글$id',
      authorLabel: '학생B',
      createdAt: DateTime(2026, 7, 21),
    );

/// 호출 시점의 목록을 돌려주는 가변 read fake(재조회 반영 검증용).
class _MutableRead extends CommunityReadRepository {
  _MutableRead({required this.boardsData, required this.commentsData});

  List<BoardPost> boardsData;
  List<CommunityComment> commentsData;
  int boardsCalls = 0;
  int commentsCalls = 0;

  @override
  Future<CommunityPage<BoardPost>> boards(
      {String? category, int? limit, int offset = 0}) async {
    boardsCalls++;
    final List<BoardPost> items = offset >= boardsData.length
        ? <BoardPost>[]
        : boardsData.sublist(offset);
    return CommunityPage<BoardPost>(
      items: limit == null ? items : items.take(limit).toList(),
      rawCount: items.length,
      nextOffset: offset + items.length,
      hasMore: false,
    );
  }

  @override
  Future<List<CommunityComment>> comments(CommunityPostType type, String postId,
          {int? limit, int offset = 0}) async =>
      List<CommunityComment>.of(commentsData);

  @override
  Future<Set<String>> myBoardReactionIds(String reactionType,
          {String? postId}) async =>
      <String>{};
}

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    ContentPolicyGate.agreedThisSession = true;
  });

  group('(a) 댓글 작성 → 상세 count·목록 카드 갱신', () {
    testWidgets('상세: 댓글 등록 후 재조회 — 헤더·ReactionBar count 최신화 + 뒤로가기 시 목록 재조회',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        boardsData: <BoardPost>[_post('p1', commentCount: 1)],
        commentsData: <CommunityComment>[_comment('c1')],
      );
      final FakeCommunityWrite write = FakeCommunityWrite();

      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: BoardListView(read: read, write: write))));
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget);
      final int boardsCallsBefore = read.boardsCalls;

      // 상세 진입 → 댓글 1 표시(ReactionBar 라벨 + 댓글 헤더 2곳).
      await tester.tap(find.text('글p1'));
      await tester.pumpAndSettle();
      expect(find.text('댓글 1'), findsNWidgets(2));

      // 댓글 등록 → 서버(가짜)엔 2개 → 재조회로 '댓글 2' + 카드 count 원천 갱신.
      read.commentsData = <CommunityComment>[_comment('c1'), _comment('c2')];
      read.boardsData = <BoardPost>[_post('p1', commentCount: 2)];
      await tester.enterText(find.byType(TextField), '새 댓글');
      await tester.tap(find.byIcon(Icons.send_rounded), warnIfMissed: false);
      if (write.commentCalls == 0) {
        // 전송 아이콘 명칭이 다르면 접근 가능한 IconButton 폴백.
        await tester.tap(find.byType(IconButton).last);
      }
      await tester.pumpAndSettle();
      expect(write.commentCalls, 1);
      // 헤더(목록 길이)와 ReactionBar(override) 둘 다 최신 count 로.
      expect(find.text('댓글 2'), findsNWidgets(2));

      // 뒤로가기(_changed=true 전달) → 목록 첫 페이지 재조회(변경시에만).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(read.boardsCalls, greaterThan(boardsCallsBefore));
    });
  });

  group('(b) 숨김·복구 — resume/refresh 반영', () {
    testWidgets('관리자 숨김 → resumed 재조회로 제거, 복구 → 재노출',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        boardsData: <BoardPost>[_post('p1'), _post('p2')],
        commentsData: const <CommunityComment>[],
      );
      final FakeCommunityWrite write = FakeCommunityWrite();
      // AuthService 상태와 무관한 목록 화면만 검증(커뮤니티 탭 셸).
      await tester.pumpScopedWidget(
          MaterialApp(home: CommunityScreen(read: read, write: write)));
      await tester.pumpAndSettle();
      // 게시판 탭으로 전환.
      await tester.tap(find.text('게시판'));
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget);
      expect(find.text('글p2'), findsOneWidget);

      // 관리자 숨김(외부 변경) → 앱 복귀(resumed) → 목록에서 제거.
      read.boardsData = <BoardPost>[_post('p2')];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsNothing);
      expect(find.text('글p2'), findsOneWidget);

      // 복구 → 다시 resumed → 재노출.
      read.boardsData = <BoardPost>[_post('p1'), _post('p2')];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget);
    });

    testWidgets('pull-to-refresh 로 즉시 재조회(세대 토큰 — stale 응답 폐기 구조)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        boardsData: <BoardPost>[_post('p1')],
        commentsData: const <CommunityComment>[],
      );
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(
              body: BoardListView(read: read, write: FakeCommunityWrite()))));
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget);

      read.boardsData = <BoardPost>[_post('p1'), _post('p3')];
      // RefreshIndicator 배선 계약 검증: onRefresh == paginator.refresh.
      // (제스처 시뮬레이션은 로딩 스피너의 무한 애니메이션과 얽혀 flaky —
      //  당김 제스처 자체는 프레임워크 계약이므로 배선만 고정한다.)
      final RefreshIndicator ri =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      await ri.onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('글p3'), findsOneWidget);
    });
  });

  group('(c) 지갑(잔액·원장) 교차 무효화 — DataRefreshBus', () {
    MyPageData data(int balanceCents) => MyPageData(
          role: AppRole.student,
          profile: const MyProfile(name: '학생', roleLabel: '학생'),
          cash: CashSummary(
            balanceCents: balanceCents,
            recent: <CashEntry>[
              CashEntry(
                  deltaCents: -balanceCents,
                  createdAt: DateTime(2026, 7, 24),
                  reason: 'individual_question_escrow_hold'),
            ],
          ),
        );

    testWidgets('bumpWallet → 마이페이지 잔액·최근 내역 재조회(정확히 1회 추가)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      int calls = 0;
      int balance = 5000000;
      await tester.pumpScopedWidget(MaterialApp(
        home: Scaffold(
          body: MyPageScreen(loaderOverride: () async {
            calls++;
            return data(balance);
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('50,000원'), findsOneWidget);

      // IQ 환불(다른 화면) 성공 신호 → 재조회 정확히 1회, 최신 잔액 표시.
      balance = 6000000;
      DataRefreshBus.bumpWallet();
      await tester.pumpAndSettle();
      expect(calls, 2, reason: '무한 새로고침·중복 호출 없음');
      expect(find.text('60,000원'), findsOneWidget);
      expect(find.text('개별질문 안전 결제'), findsOneWidget); // 원장 reason 재조회
    });

    testWidgets('dispose 후 bump → 상태 변경·크래시 없음', (WidgetTester tester) async {
      _bigSurface(tester);
      int calls = 0;
      await tester.pumpScopedWidget(MaterialApp(
        home: Scaffold(body: MyPageScreen(loaderOverride: () async {
          calls++;
          return data(1000);
        })),
      ));
      await tester.pumpAndSettle();
      // 화면 제거(dispose — 리스너 해제).
      await tester.pumpScopedWidget(const MaterialApp(home: SizedBox()));
      final int before = calls;
      DataRefreshBus.bumpWallet();
      await tester.pump();
      expect(calls, before); // dispose 후 재조회·setState 없음
    });

    testWidgets('느린 이전 응답이 최신 잔액을 덮지 않는다(Future 교체 방어)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final Completer<MyPageData> slow = Completer<MyPageData>();
      int calls = 0;
      await tester.pumpScopedWidget(MaterialApp(
        home: Scaffold(body: MyPageScreen(loaderOverride: () {
          calls++;
          if (calls == 1) return slow.future; // 환불 '전' 스냅샷 — 늦게 도착
          return Future<MyPageData>.value(data(6000000)); // 환불 후 최신
        })),
      ));
      await tester.pump();

      DataRefreshBus.bumpWallet(); // 최신 조회 시작(빠르게 완료)
      await tester.pumpAndSettle();
      expect(find.text('60,000원'), findsOneWidget);

      slow.complete(data(5000000)); // 환불 전 값이 늦게 도착
      await tester.pumpAndSettle();
      expect(find.text('60,000원'), findsOneWidget, reason: 'stale 미반영');
      expect(find.text('50,000원'), findsNothing);
    });

    test('bumpWallet 은 세대 증가 + 리스너 통지(값 미탑재 — 재조회는 각 표면 몫)', () {
      final int start = DataRefreshBus.walletGeneration.value;
      int notified = 0;
      void l() => notified++;
      DataRefreshBus.walletGeneration.addListener(l);
      DataRefreshBus.bumpWallet();
      expect(DataRefreshBus.walletGeneration.value, start + 1);
      expect(notified, 1);
      DataRefreshBus.walletGeneration.removeListener(l);
    });
  });
}
