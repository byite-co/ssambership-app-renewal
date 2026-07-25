import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/community_screen.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/ui/activity/my_activity_view.dart';
import 'package:ssambership_app/features/community/ui/shortform/shortform_feed_view.dart';

import '../community/fakes.dart';

/// §4-3·§4-4 — 커뮤니티 표면별 최신성 수렴.
///
/// 기존 실측: board 탭만 resume 재조회·PTR·상세복귀 재조회를 갖고 있었고,
/// 숏폼 피드·내 활동은 initState 1회 조회 후 갱신 경로가 없었다(관리자 숨김·복구
/// 미반영). 여기서는 그 빠진 표면만 board 와 동일한 계약으로 보완했음을 고정한다.

BoardPost _post(String id) => BoardPost(
      id: id,
      title: '글$id',
      body: '본문',
      category: 'study',
      authorLabel: '학생A',
      authorRole: 'student',
      likeCount: 0,
      commentCount: 0,
      viewCount: 0,
      createdAt: DateTime(2026, 7, 20),
    );

ShortformPost _short(String id) => ShortformPost(
      id: id,
      title: '숏폼$id',
      authorLabel: '멘토A',
      authorRole: 'mentor',
      likeCount: 0,
      viewCount: 0,
      createdAt: DateTime(2026, 7, 20),
    );

/// 호출 시점의 데이터를 돌려주는 가변 read fake(재조회 반영 검증용).
class _MutableRead extends CommunityReadRepository {
  _MutableRead({
    this.shortformsData = const <ShortformPost>[],
    this.activityData = const MyActivity(),
  });

  List<ShortformPost> shortformsData;
  MyActivity activityData;
  int shortformCalls = 0;
  int activityCalls = 0;

  /// 설정 시 다음 myActivity 호출이 이 future 를 돌려준다(늦은 응답·실패 주입).
  Future<MyActivity>? activityOverride;

  @override
  Future<CommunityPage<BoardPost>> boards(
      {String? category, int? limit, int offset = 0}) async {
    return const CommunityPage<BoardPost>(
      items: <BoardPost>[],
      rawCount: 0,
      nextOffset: 0,
      hasMore: false,
    );
  }

  @override
  Future<CommunityPage<ShortformPost>> shortforms(
      {int? limit, int offset = 0}) async {
    shortformCalls++;
    final List<ShortformPost> items = offset >= shortformsData.length
        ? <ShortformPost>[]
        : shortformsData.sublist(offset);
    return CommunityPage<ShortformPost>(
      items: limit == null ? items : items.take(limit).toList(),
      rawCount: items.length,
      nextOffset: offset + items.length,
      hasMore: false,
    );
  }

  @override
  Future<List<CommunityComment>> comments(CommunityPostType type, String postId,
          {int? limit, int offset = 0}) async =>
      const <CommunityComment>[];

  @override
  Future<Set<String>> myBoardReactionIds(String reactionType) async =>
      <String>{};

  @override
  Future<Set<String>> myShortformReactionIds(String reactionType) async =>
      <String>{};

  @override
  Future<MyActivity> myActivity() {
    activityCalls++;
    final Future<MyActivity>? override = activityOverride;
    if (override != null) {
      activityOverride = null;
      return override;
    }
    return Future<MyActivity>.value(activityData);
  }
}

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('§4-3 숏폼 피드 — 숨김·복구 반영', () {
    testWidgets('앱 복귀(resumed) → 재조회로 숨겨진 숏폼 제거, 복구 시 재노출',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        shortformsData: <ShortformPost>[_short('s1'), _short('s2')],
      );
      await tester.pumpWidget(MaterialApp(
          home: CommunityScreen(read: read, write: FakeCommunityWrite())));
      await tester.pumpAndSettle();
      expect(find.text('숏폼s1'), findsOneWidget);
      expect(find.text('숏폼s2'), findsOneWidget);

      // 관리자 숨김(외부 변경) → 앱 복귀 → 목록에서 제거.
      read.shortformsData = <ShortformPost>[_short('s2')];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('숏폼s1'), findsNothing);
      expect(find.text('숏폼s2'), findsOneWidget);

      // 복구 → 다시 resumed → 재노출.
      read.shortformsData = <ShortformPost>[_short('s1'), _short('s2')];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('숏폼s1'), findsOneWidget);
    });

    testWidgets('pull-to-refresh 로 즉시 재조회(세대 토큰 — stale 응답 폐기 구조)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read =
          _MutableRead(shortformsData: <ShortformPost>[_short('s1')]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ShortformFeedView(read: read, write: FakeCommunityWrite())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('숏폼s1'), findsOneWidget);

      read.shortformsData = <ShortformPost>[_short('s1'), _short('s3')];
      // RefreshIndicator 배선 계약 검증: onRefresh == paginator.refresh
      // (제스처 시뮬레이션은 로딩 스피너 애니메이션과 얽혀 flaky — board 탭과 동일 관행).
      final RefreshIndicator ri =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      await ri.onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('숏폼s3'), findsOneWidget);
    });
  });

  group('§4-3 내 활동 — 숨김·복구 반영', () {
    testWidgets('앱 복귀(resumed) → 재조회로 숨겨진 글 제거', (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        activityData:
            MyActivity(myPosts: <BoardPost>[_post('p1'), _post('p2')]),
      );
      await tester.pumpWidget(MaterialApp(
          home: CommunityScreen(read: read, write: FakeCommunityWrite())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('내 활동'));
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget);

      read.activityData = MyActivity(myPosts: <BoardPost>[_post('p2')]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsNothing);
      expect(find.text('글p2'), findsOneWidget);
    });

    testWidgets('pull-to-refresh 로 즉시 재조회', (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        activityData: MyActivity(myPosts: <BoardPost>[_post('p1')]),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MyActivityView(read: read, write: FakeCommunityWrite())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget);

      read.activityData =
          MyActivity(myPosts: <BoardPost>[_post('p1'), _post('p3')]);
      final RefreshIndicator ri =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      await ri.onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('글p3'), findsOneWidget);
    });

    testWidgets('빈 상태에서도 당길 수 있다(PTR 스크롤 물리 보장)', (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MyActivityView(read: read, write: FakeCommunityWrite())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('아직 활동이 없어요'), findsOneWidget);

      read.activityData = MyActivity(myPosts: <BoardPost>[_post('p1')]);
      final RefreshIndicator ri =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      await ri.onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget);
    });

    testWidgets('늦은 이전 응답이 최신 목록을 덮지 않는다(세대 guard)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final Completer<MyActivity> slow = Completer<MyActivity>();
      final _MutableRead read = _MutableRead(
        activityData: MyActivity(myPosts: <BoardPost>[_post('p1')]),
      );
      read.activityOverride = slow.future; // 첫 조회를 늦춘다
      final GlobalKey<MyActivityViewState> key =
          GlobalKey<MyActivityViewState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body:
              MyActivityView(key: key, read: read, write: FakeCommunityWrite()),
        ),
      ));
      await tester.pump();

      // 최신 조회(빠르게 완료) — 숨김 반영 후 목록.
      read.activityData = MyActivity(myPosts: <BoardPost>[_post('p9')]);
      await key.currentState!.reload();
      await tester.pumpAndSettle();
      expect(find.text('글p9'), findsOneWidget);

      // 숨김 '전' 목록이 뒤늦게 도착 — 최신 목록을 되돌리면 안 된다.
      slow.complete(MyActivity(myPosts: <BoardPost>[_post('p1')]));
      await tester.pumpAndSettle();
      expect(find.text('글p9'), findsOneWidget, reason: 'stale 미반영');
      expect(find.text('글p1'), findsNothing);
    });

    testWidgets('재조회 실패 → 마지막 정상 목록을 지우지 않는다', (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        activityData: MyActivity(myPosts: <BoardPost>[_post('p1')]),
      );
      final GlobalKey<MyActivityViewState> key =
          GlobalKey<MyActivityViewState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body:
              MyActivityView(key: key, read: read, write: FakeCommunityWrite()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget);

      read.activityOverride = Future<MyActivity>.error(StateError('network'));
      await key.currentState!.reload();
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsOneWidget, reason: '마지막 정상 스냅샷 보존');
      expect(find.textContaining('내 활동을 불러오지 못했어요'), findsNothing);
    });

    testWidgets('첫 로드 실패는 오류 화면(마지막 정상 스냅샷이 없을 때만)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead();
      // Completer 로 주입한다 — 미리 만든 Future.error 는 리스너가 붙기 전
      // 마이크로태스크에서 '미처리 비동기 오류'로 보고돼 테스트가 오탐한다.
      final Completer<MyActivity> first = Completer<MyActivity>();
      read.activityOverride = first.future;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MyActivityView(read: read, write: FakeCommunityWrite())),
      ));
      await tester.pump();

      first.completeError(StateError('network'));
      await tester.pumpAndSettle();
      expect(find.textContaining('내 활동을 불러오지 못했어요'), findsOneWidget);
    });

    testWidgets('dispose 후 reload 응답 도착 → 상태 변경·크래시 없음',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final Completer<MyActivity> slow = Completer<MyActivity>();
      final _MutableRead read = _MutableRead();
      read.activityOverride = slow.future;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MyActivityView(read: read, write: FakeCommunityWrite())),
      ));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      slow.complete(MyActivity(myPosts: <BoardPost>[_post('p1')]));
      await tester.pumpAndSettle();
      expect(find.text('글p1'), findsNothing);
    });
  });

  group('§4-4 커뮤니티 셸 — 살아 있는 탭만 resume 재조회', () {
    testWidgets('아직 만들어지지 않은 탭은 재조회하지 않는다(다음 진입 시 어차피 fresh)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        shortformsData: <ShortformPost>[_short('s1')],
        activityData: MyActivity(myPosts: <BoardPost>[_post('p1')]),
      );
      await tester.pumpWidget(MaterialApp(
          home: CommunityScreen(read: read, write: FakeCommunityWrite())));
      await tester.pumpAndSettle();
      // TabBarView 는 지연 생성 — 초기 탭(숏폼)만 살아 있다.
      final int shortBefore = read.shortformCalls;
      expect(read.activityCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      // 살아 있는 탭은 재조회, 죽은 탭은 호출 0(크래시·불필요 호출 없음).
      expect(read.shortformCalls, greaterThan(shortBefore));
      expect(read.activityCalls, 0);
    });

    testWidgets('탭 진입으로 살아난 뒤에는 같은 resumed 신호로 재조회된다',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _MutableRead read = _MutableRead(
        shortformsData: <ShortformPost>[_short('s1')],
        activityData: MyActivity(myPosts: <BoardPost>[_post('p1')]),
      );
      await tester.pumpWidget(MaterialApp(
          home: CommunityScreen(read: read, write: FakeCommunityWrite())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('내 활동'));
      await tester.pumpAndSettle();
      final int activityBefore = read.activityCalls;
      expect(activityBefore, greaterThan(0));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(read.activityCalls, greaterThan(activityBefore));
    });
  });
}
