import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/mentor_iq_list_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/student_iq_list_screen.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/mypage_screen.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';
import 'package:ssambership_app/features/notifications/notifications_screen.dart';
import 'package:ssambership_app/features/question_room/data/models/connection_note.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/ui/connection_notes_screen.dart';

/// 주요 화면의 상태 3종(로딩/빈/에러)이 작은 뷰포트(320×568)에서
/// RenderFlex overflow 예외 없이 그려지는지 스모크.
/// 전부 fake/override 주입 — 실제 DB·네트워크 비접촉.
void main() {
  void smallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // KeyedSubtree(UniqueKey): 같은 타입 화면을 연속 pump 할 때 State 재사용으로
  // initState 의 loader 가 안 바뀌는 것을 방지(매번 리마운트).
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(body: KeyedSubtree(key: UniqueKey(), child: child)),
      );

  /// 로딩 상태 고정용 — 완료되지 않는 Future.
  Future<T> never<T>() => Completer<T>().future;

  Future<void> expectNoOverflow(
    WidgetTester tester,
    Widget child, {
    bool settle = true,
    String? reason,
  }) async {
    await tester.pumpWidget(wrap(child));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(); // 로딩 상태: settle 하면 영원히 대기하므로 1프레임만.
    }
    expect(tester.takeException(), isNull, reason: reason);
  }

  Room room() => Room(
        id: 'room-1',
        studentId: 's1',
        mentorId: 'm1',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );

  IndividualQuestion question() => IndividualQuestion(
        id: 'q1',
        studentId: 's1',
        type: IndividualQuestionType.open,
        status: IndividualQuestionStatus.open,
        title: '수열 질문이에요',
        body: '문제 본문',
        priceCents: 500000,
        createdAt: DateTime(2026, 7, 1),
      );

  group('320×568 — 개별질문 목록(학생)', () {
    testWidgets('로딩', (WidgetTester tester) async {
      smallViewport(tester);
      await expectNoOverflow(
        tester,
        StudentIqListScreen(loaderOverride: never),
        settle: false,
        reason: '학생 IQ 목록 로딩 오버플로',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('빈 상태', (WidgetTester tester) async {
      smallViewport(tester);
      await expectNoOverflow(
        tester,
        StudentIqListScreen(loaderOverride: () async => <IndividualQuestion>[]),
        reason: '학생 IQ 목록 빈 상태 오버플로',
      );
    });

    testWidgets('에러 상태', (WidgetTester tester) async {
      smallViewport(tester);
      await expectNoOverflow(
        tester,
        StudentIqListScreen(
            loaderOverride: () async => throw Exception('네트워크 오류')),
        reason: '학생 IQ 목록 에러 상태 오버플로',
      );
    });
  });

  group('320×568 — 개별질문 목록(멘토)', () {
    testWidgets('로딩·빈·에러', (WidgetTester tester) async {
      smallViewport(tester);
      await expectNoOverflow(
        tester,
        MentorIqListScreen(loaderOverride: never),
        settle: false,
      );
      await expectNoOverflow(
        tester,
        MentorIqListScreen(
          loaderOverride: () async => const MentorIqListData(
            open: <OpenIndividualQuestion>[],
            mine: <IndividualQuestion>[],
          ),
        ),
      );
      await expectNoOverflow(
        tester,
        MentorIqListScreen(loaderOverride: () async => throw Exception('오류')),
      );
    });
  });

  group('320×568 — 개별질문 상세', () {
    testWidgets('데이터·에러', (WidgetTester tester) async {
      smallViewport(tester);
      await expectNoOverflow(
        tester,
        IqDetailScreen(
          questionId: 'q1',
          roleOverride: AppRole.student,
          loaderOverride: () async => IqDetailData(
            question: question(),
            messages: <IqMessage>[],
            attachments: <IqAttachment>[],
          ),
        ),
        reason: 'IQ 상세 데이터 오버플로',
      );
      await expectNoOverflow(
        tester,
        IqDetailScreen(
          questionId: 'q1',
          roleOverride: AppRole.student,
          loaderOverride: () async => throw Exception('오류'),
        ),
        reason: 'IQ 상세 에러 오버플로',
      );
    });
  });

  group('320×568 — 알림', () {
    testWidgets('로딩·빈·에러', (WidgetTester tester) async {
      smallViewport(tester);
      await expectNoOverflow(
        tester,
        NotificationsScreen(
            repository: _FakeNotifications(loading: true),
            onDeepLinkTab: (_) {}),
        settle: false,
      );
      await expectNoOverflow(
        tester,
        NotificationsScreen(
            repository: _FakeNotifications(), onDeepLinkTab: (_) {}),
      );
      await expectNoOverflow(
        tester,
        NotificationsScreen(
            repository: _FakeNotifications(throws: true),
            onDeepLinkTab: (_) {}),
      );
    });
  });

  group('320×568 — 마이페이지', () {
    testWidgets('학생 데이터·에러', (WidgetTester tester) async {
      smallViewport(tester);
      await expectNoOverflow(
        tester,
        MyPageScreen(
          loaderOverride: () async => const MyPageData(
            role: AppRole.student,
            profile: MyProfile(name: '김학생', roleLabel: '학생', email: 's@x.com'),
          ),
        ),
        reason: '마이페이지 학생 오버플로',
      );
      await expectNoOverflow(
        tester,
        MyPageScreen(loaderOverride: () async => throw Exception('오류')),
        reason: '마이페이지 에러 오버플로',
      );
    });
  });

  group('320×568 — 연결노트', () {
    testWidgets('로딩·빈·에러', (WidgetTester tester) async {
      smallViewport(tester);
      await expectNoOverflow(
        tester,
        ConnectionNotesScreen(
          room: room(),
          mentorName: '김멘토',
          currentUserId: 's1',
          notesLoader: never,
        ),
        settle: false,
      );
      await expectNoOverflow(
        tester,
        ConnectionNotesScreen(
          room: room(),
          mentorName: '김멘토',
          currentUserId: 's1',
          notesLoader: () async => <ConnectionNote>[],
        ),
      );
      await expectNoOverflow(
        tester,
        ConnectionNotesScreen(
          room: room(),
          mentorName: '김멘토',
          currentUserId: 's1',
          notesLoader: () async => throw Exception('오류'),
        ),
      );
    });
  });
}

class _FakeNotifications implements NotificationsRepository {
  _FakeNotifications({this.loading = false, this.throws = false});

  final bool loading;
  final bool throws;

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) {
    if (loading) return Completer<NotificationsPage>().future;
    if (throws) throw Exception('네트워크 오류');
    return Future<NotificationsPage>.value(
        const NotificationsPage(items: <AppNotification>[], hasNext: false));
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}
