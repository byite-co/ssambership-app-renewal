import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ssambership_app/app/app_navigation.dart';
import 'package:ssambership_app/app/app_route_paths.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/app/app_tabs.dart';
import 'package:ssambership_app/app/home_shell.dart';
import 'package:ssambership_app/app/router.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/shared/constants/app_constants.dart';

import '../goldens/golden_app_fakes.dart';
import '../goldens/golden_fixtures.dart';

void main() {
  tearDown(() => TabNavigator.request.value = null);

  testWidgets('학생 5탭 순서와 선택 정본은 canonical URL이다', (WidgetTester tester) async {
    final _RouterHarness harness = _productionHarness(AppRole.student);
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.rooms);
    expect(_navigationLabels(tester), AppConstants.studentBottomTabLabels);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await _tapTab(tester, '개별질문');
    expect(_path(harness.router), AppRoutePaths.individualQuestions);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    harness.router.go(AppRoutePaths.home);
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.rooms);

    harness.router.go(AppRoutePaths.root);
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.rooms);

    harness.router.go(AppRoutePaths.settlements);
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.rooms);
  });

  testWidgets('멘토 5탭은 정산을 노출하고 기존 답변·정산 요약을 재사용한다', (
    WidgetTester tester,
  ) async {
    const MyPageData data = MyPageData(
      role: AppRole.mentor,
      profile: MyProfile(name: '탐색멘토', roleLabel: '멘토'),
      mentor: MentorDashboard(
        studentCount: 3,
        pendingAnswers: 2,
        latestSettlementCents: 120000,
      ),
    );
    final _RouterHarness harness = _productionHarness(
      AppRole.mentor,
      myPage: const GoldenMyPageRepository(data),
    );
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    expect(_navigationLabels(tester), AppConstants.mentorBottomTabLabels);
    await _tapTab(tester, '정산');

    expect(_path(harness.router), AppRoutePaths.settlements);
    expect(find.text('답변 · 정산 요약'), findsOneWidget);
    expect(find.text('받은 질문 보기'), findsOneWidget);

    await tester.tap(find.text('받은 질문 보기'));
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.rooms);
  });

  testWidgets('멘토의 /mentors deep URL은 숨은 shared branch에서 그대로 유효하다', (
    WidgetTester tester,
  ) async {
    final _RouterHarness harness = _productionHarness(AppRole.mentor);
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    harness.router.go(AppRoutePaths.mentors);
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.mentors);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(find.text('멘토 찾기'), findsWidgets);
  });

  testWidgets('게스트 canonical은 /mentors이고 /community 외 탭은 로그인으로 간다', (
    WidgetTester tester,
  ) async {
    final _RouterHarness harness = _productionHarness(
      AppRole.guest,
      guest: true,
    );
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.mentors);
    harness.router.go(AppRoutePaths.home);
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.mentors);
    await _tapTab(tester, '커뮤니티');
    expect(_path(harness.router), AppRoutePaths.community);

    await _tapTab(tester, '개별질문');
    expect(_path(harness.router), AppRoutePaths.login);
    expect(
      harness
          .router.routeInformationProvider.value.uri.queryParameters['notice'],
      'login_required',
    );
  });

  testWidgets('프로필은 URL push이고 뒤로 가면 원래 탭을 유지한다', (WidgetTester tester) async {
    final _RouterHarness harness = _productionHarness(AppRole.student);
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    expect(
      AppNavigation.usesProductionRouter(
        tester.element(find.byType(HomeShell)),
      ),
      isTrue,
    );
    await tester.tap(find.bySemanticsLabel(AppConstants.myPageTitle));
    await tester.pumpAndSettle();
    expect(
      harness.router.routerDelegate.currentConfiguration.last.matchedLocation,
      AppRoutePaths.myPage,
    );
    expect(find.text(AppConstants.myPageTitle), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.rooms);
  });

  testWidgets('TabNavigator는 숫자 대신 경로를 요청하고 같은 경로도 재처리한다', (
    WidgetTester tester,
  ) async {
    final _RouterHarness harness = _productionHarness(AppRole.student);
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    TabNavigator.go(AppTab.individualQuestion);
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.individualQuestions);
    expect(TabNavigator.request.value, isNull);

    TabNavigator.go(AppTab.community);
    await tester.pumpAndSettle();
    TabNavigator.go(AppTab.individualQuestion);
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.individualQuestions);
    expect(TabNavigator.request.value, isNull);
  });

  testWidgets('indexedStack branch를 오가도 각 branch 상태가 보존된다', (
    WidgetTester tester,
  ) async {
    final _RouterHarness harness = _probeHarness();
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('increment-rooms')));
    await tester.pump();
    expect(find.text('rooms:1'), findsOneWidget);

    await _tapTab(tester, '개별질문');
    await tester.tap(find.byKey(const ValueKey<String>('increment-iq')));
    await tester.pump();
    expect(find.text('iq:1'), findsOneWidget);

    await _tapTab(tester, '질문방');
    expect(_path(harness.router), AppRoutePaths.rooms);
    expect(find.text('rooms:1'), findsOneWidget);

    await _tapTab(tester, '멘토 찾기');
    await tester.tap(find.byKey(const ValueKey<String>('increment-mentors')));
    await tester.pump();
    await _tapTab(tester, '커뮤니티');
    await _tapTab(tester, '멘토 찾기');
    expect(_path(harness.router), AppRoutePaths.mentors);
    expect(find.text('mentors:1'), findsOneWidget);
  });

  testWidgets('작은 뷰포트에서 역할별 5탭 전환에 오버플로가 없다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _RouterHarness harness = _probeHarness();
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    for (final String label in AppConstants.studentBottomTabLabels) {
      await _tapTab(tester, label);
      expect(tester.takeException(), isNull, reason: '$label 탭 오버플로/예외');
    }
  });
}

class _RouterHarness {
  const _RouterHarness({required this.router, required this.app});

  final GoRouter router;
  final Widget app;
}

_RouterHarness _productionHarness(
  AppRole role, {
  bool guest = false,
  GoldenMyPageRepository? myPage,
}) {
  final FakeAppAuth auth = FakeAppAuth(
    role: role,
    userId: guest ? null : 'user-1',
    guest: guest,
  );
  final AppDependencies dependencies = goldenDependencies(
    auth: auth,
    myPage: myPage,
    questionRoomRead: const GoldenReadRepository(),
  );
  final GoRouter router = AppRouter.create(dependencies);
  return _RouterHarness(
    router: router,
    app: AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        routerConfig: router,
      ),
    ),
  );
}

_RouterHarness _probeHarness() {
  final AppDependencies dependencies = goldenDependencies(
    auth: FakeAppAuth(role: AppRole.student, userId: 'student-1'),
    questionRoomRead: const GoldenReadRepository(),
  );
  late final GoRouter router;
  router = GoRouter(
    initialLocation: AppRoutePaths.rooms,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) =>
            HomeShell(navigationShell: shell, location: state.uri.path),
        branches: <StatefulShellBranch>[
          _probeBranch(0, AppRoutePaths.rooms, 'rooms'),
          _probeBranch(1, AppRoutePaths.individualQuestions, 'iq'),
          StatefulShellBranch(
            initialLocation: AppRoutePaths.mentors,
            routes: <RouteBase>[
              _probeRoute(2, AppRoutePaths.mentors, 'mentors'),
              _probeRoute(2, AppRoutePaths.settlements, 'settlements'),
            ],
          ),
          _probeBranch(3, AppRoutePaths.community, 'community'),
          _probeBranch(4, AppRoutePaths.notifications, 'notifications'),
        ],
      ),
    ],
  );
  AppNavigation.markProductionRouter(router);
  return _RouterHarness(
    router: router,
    app: AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

StatefulShellBranch _probeBranch(int index, String path, String label) =>
    StatefulShellBranch(routes: <RouteBase>[_probeRoute(index, path, label)]);

GoRoute _probeRoute(int index, String path, String label) => GoRoute(
      path: path,
      builder: (BuildContext context, GoRouterState state) => HomeTabBranch(
        branchIndex: index,
        child: _StateProbe(label: label),
      ),
    );

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.label});

  final String label;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          key: ValueKey<String>('increment-${widget.label}'),
          onPressed: () => setState(() => count++),
          child: Text('${widget.label}:$count'),
        ),
      );
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

List<String> _navigationLabels(WidgetTester tester) {
  final NavigationBar bar = tester.widget<NavigationBar>(
    find.byType(NavigationBar),
  );
  return bar.destinations
      .cast<NavigationDestination>()
      .map((NavigationDestination destination) => destination.label)
      .toList();
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;
