import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ssambership_app/app/app_route_paths.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/app/router.dart';
import 'package:ssambership_app/core/auth/account_status.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';

import '../support/app_scope_test_harness.dart';

void main() {
  testWidgets(
    'root detail defers active branch resume refresh until it is uncovered',
    (WidgetTester tester) async {
      final _CountingEmptyRooms read = _CountingEmptyRooms();
      final AppDependencies dependencies = testAppDependencies(
        auth: TestAppAuth(
          role: AppRole.student,
          userId: 'student-user',
          account: AccountState.active,
        ),
        questionRoomRead: read,
      );
      final GoRouter router = AppRouter.create(dependencies);
      addTearDown(router.dispose);
      router.go(AppRoutePaths.rooms);

      await tester.pumpWidget(
        AppScope(
          dependencies: dependencies,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(read.myRoomsCalls, 1);

      router.push<void>(AppRoutePaths.newBoardPost);
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        read.myRoomsCalls,
        1,
        reason: 'a root detail route must hide the branch beneath it',
      );

      router.pop();
      await tester.pumpAndSettle();
      expect(
        read.myRoomsCalls,
        2,
        reason:
            'the covered branch must consume one deferred refresh on reveal',
      );
    },
  );
}

class _CountingEmptyRooms extends QuestionRoomReadRepository {
  int myRoomsCalls = 0;

  @override
  Future<List<Room>> myRooms() async {
    myRoomsCalls++;
    return const <Room>[];
  }
}
