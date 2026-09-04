import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/app/routes/community_routes.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';

import '../support/app_scope_test_harness.dart';
import 'fakes.dart';

void main() {
  testWidgets(
    'board edit route re-fetches and renders the current owner only',
    (WidgetTester tester) async {
      final TestAppAuth auth = TestAppAuth(
        role: AppRole.student,
        userId: 'owner-1',
      );
      final _RecordingBoardRead read = _RecordingBoardRead(
        sampleBoard(
          id: 'post-1',
          authorId: 'owner-1',
          updatedAtRaw: '2026-09-05T00:00:00Z',
        ),
      );
      final FakeCommunityWrite write = FakeCommunityWrite(uid: 'owner-1');

      await tester.pumpWidget(
        _app(auth: auth, read: read, write: write, postId: 'post-1'),
      );
      await tester.pumpAndSettle();

      expect(read.requestedIds, <String>['post-1']);
      expect(find.text('글 수정'), findsOneWidget);
      expect(find.text('게시글을 찾을 수 없어요.'), findsNothing);
    },
  );

  testWidgets('board edit route hides another user post before any write UI', (
    WidgetTester tester,
  ) async {
    final TestAppAuth auth = TestAppAuth(
      role: AppRole.student,
      userId: 'viewer-2',
    );
    final _RecordingBoardRead read = _RecordingBoardRead(
      sampleBoard(
        id: 'post-1',
        authorId: 'owner-1',
        updatedAtRaw: '2026-09-05T00:00:00Z',
      ),
    );
    final FakeCommunityWrite write = FakeCommunityWrite(uid: 'viewer-2');

    await tester.pumpWidget(
      _app(auth: auth, read: read, write: write, postId: 'post-1'),
    );
    await tester.pumpAndSettle();

    expect(read.requestedIds, <String>['post-1']);
    expect(find.text('게시글을 찾을 수 없어요.'), findsOneWidget);
    expect(find.text('글 수정'), findsNothing);
    expect(write.uploadImageCalls, 0);
    expect(write.updateCalls, 0);
  });

  testWidgets('board edit route fails closed without a current user', (
    WidgetTester tester,
  ) async {
    final TestAppAuth auth = TestAppAuth(role: AppRole.guest);
    final _RecordingBoardRead read = _RecordingBoardRead(
      sampleBoard(id: 'post-1', authorId: 'owner-1'),
    );
    final FakeCommunityWrite write = FakeCommunityWrite();

    await tester.pumpWidget(
      _app(auth: auth, read: read, write: write, postId: 'post-1'),
    );
    await tester.pumpAndSettle();

    expect(read.requestedIds, isEmpty);
    expect(find.text('게시글을 찾을 수 없어요.'), findsOneWidget);
    expect(find.text('글 수정'), findsNothing);
  });
}

Widget _app({
  required TestAppAuth auth,
  required _RecordingBoardRead read,
  required FakeCommunityWrite write,
  required String postId,
}) {
  final AppDependencies defaults = testAppDependencies(auth: auth);
  final AppDependencies dependencies = AppDependencies(
    auth: auth,
    supabaseClient: () => null,
    communityRead: read,
    communityWrite: write,
    accountDeletion: defaults.accountDeletion,
    attachmentUrlResolver: defaults.attachmentUrlResolver,
    notifications: defaults.notifications,
    notificationBadge: defaults.notificationBadge,
    deletionNotice: defaults.deletionNotice,
    versionGate: defaults.versionGate,
  );
  return AppScope(
    dependencies: dependencies,
    child: MaterialApp(home: BoardEditRoutePage(postId: postId)),
  );
}

class _RecordingBoardRead extends CommunityReadRepository {
  _RecordingBoardRead(this.post);

  final BoardPost? post;
  final List<String> requestedIds = <String>[];

  @override
  Future<BoardPost?> boardPostById(String postId) async {
    requestedIds.add(postId);
    return post;
  }
}
