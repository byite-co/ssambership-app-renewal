import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ssambership_app/app/app_route_paths.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/app/entry_guard.dart';
import 'package:ssambership_app/app/router.dart';
import 'package:ssambership_app/core/auth/account_status.dart';
import 'package:ssambership_app/core/auth/auth_service.dart'
    show AccessState, AppRole;
import 'package:ssambership_app/features/community/ui/shortform/shortform_compose_screen.dart';

import '../community/fakes.dart';
import '../goldens/golden_fixtures.dart';
import '../support/app_scope_test_harness.dart';

void main() {
  String? guard(
    AccessState access,
    String location, {
    AppRole role = AppRole.guest,
  }) =>
      EntryGuard.redirect(access: access, location: location, role: role);

  test('guest keeps only community and mentor read URLs public', () {
    expect(guard(AccessState.guest, AppRoutePaths.community), isNull);
    expect(
      guard(AccessState.guest, '${AppRoutePaths.community}?tab=shortform'),
      isNull,
    );
    expect(
      guard(AccessState.guest, AppRoutePaths.boardPost('post-1')),
      isNull,
    );
    expect(
      guard(AccessState.guest, AppRoutePaths.shortform('shortform-1')),
      isNull,
    );
    expect(guard(AccessState.guest, AppRoutePaths.mentors), isNull);
    expect(
      guard(AccessState.guest, AppRoutePaths.mentor('mentor-1')),
      isNull,
    );
  });

  test('guest cannot open community mutation URLs', () {
    expect(
      guard(AccessState.guest, AppRoutePaths.newBoardPost),
      EntryGuard.home,
    );
    expect(
      guard(AccessState.guest, AppRoutePaths.editBoardPost('post-1')),
      EntryGuard.home,
    );
    expect(
      guard(AccessState.guest, AppRoutePaths.newShortform),
      EntryGuard.home,
    );
  });

  test('guest public matching does not grant a community prefix wildcard', () {
    expect(
      guard(AccessState.guest, '/community/boards/post-1/comments'),
      EntryGuard.home,
    );
    expect(
      guard(AccessState.guest, '/community/private'),
      EntryGuard.home,
    );
    expect(
      guard(AccessState.guest, '/mentors/mentor-1/private'),
      EntryGuard.home,
    );
  });

  test('shortform mutation is mentor-only while board creation stays shared',
      () {
    expect(
      guard(
        AccessState.full,
        AppRoutePaths.newShortform,
        role: AppRole.student,
      ),
      AppRoutePaths.community,
    );
    expect(
      guard(
        AccessState.full,
        AppRoutePaths.newShortform,
        role: AppRole.mentor,
      ),
      isNull,
    );
    expect(
      guard(
        AccessState.full,
        AppRoutePaths.newBoardPost,
        role: AppRole.student,
      ),
      isNull,
    );
  });

  testWidgets('AppRouter redirects a student shortform compose URL to feed',
      (WidgetTester tester) async {
    final _RouterHarness harness = _routerHarness(AppRole.student);
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    harness.router.go(AppRoutePaths.newShortform);
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.community);
    expect(find.byType(ShortformComposeScreen), findsNothing);
  });

  testWidgets('AppRouter keeps a mentor shortform compose URL',
      (WidgetTester tester) async {
    final _RouterHarness harness = _routerHarness(AppRole.mentor);
    addTearDown(harness.router.dispose);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    harness.router.go(AppRoutePaths.newShortform);
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.newShortform);
    expect(find.byType(ShortformComposeScreen), findsOneWidget);
  });
}

class _RouterHarness {
  const _RouterHarness({required this.router, required this.app});

  final GoRouter router;
  final Widget app;
}

_RouterHarness _routerHarness(AppRole role) {
  final TestAppAuth auth = TestAppAuth(
    role: role,
    userId: '${role.name}-1',
    account: AccountState.active,
  );
  final AppDependencies defaults = testAppDependencies(auth: auth);
  final AppDependencies dependencies = AppDependencies(
    auth: auth,
    supabaseClient: () => null,
    questionRoomRead: const GoldenReadRepository(),
    communityRead: const FakeCommunityRead(),
    communityWrite: FakeCommunityWrite(uid: auth.currentUserId),
    accountDeletion: defaults.accountDeletion,
    attachmentUrlResolver: defaults.attachmentUrlResolver,
    notifications: defaults.notifications,
    notificationBadge: defaults.notificationBadge,
    deletionNotice: defaults.deletionNotice,
    versionGate: defaults.versionGate,
  );
  final GoRouter router = AppRouter.create(dependencies);
  return _RouterHarness(
    router: router,
    app: AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;
