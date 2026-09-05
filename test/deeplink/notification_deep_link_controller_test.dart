import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_tabs.dart';
import 'package:ssambership_app/core/deeplink/notification_deep_link_controller.dart';
import 'package:ssambership_app/core/push/push_payload.dart';
import 'package:ssambership_app/features/notifications/data/notification_types.dart';

/// 알림 딥링크 판정(순수 로직) — 허용 목적지·중복 제거·로그인 대기(TTL)·계정 전환.
void main() {
  late List<String> navigations;
  DateTime now = DateTime(2026, 7, 21, 12);

  NotificationDeepLinkController build({
    Duration ttl = const Duration(minutes: 15),
  }) {
    navigations = <String>[];
    now = DateTime(2026, 7, 21, 12);
    return NotificationDeepLinkController(
      navigate: navigations.add,
      now: () => now,
      pendingTtl: ttl,
    );
  }

  NotificationDeepLinkTarget target({
    NotificationEventType type = NotificationEventType.questionAnswered,
    String? roomId,
    String? threadId,
    String? questionId,
    String eventId = '',
  }) {
    return NotificationDeepLinkTarget(
      type: type,
      roomId: roomId,
      threadId: threadId,
      questionId: questionId,
      eventId: eventId,
    );
  }

  group('목적지 매핑(notificationDestinationOf 정본만 허용)', () {
    test('question_answered + room_id → 질문방 탭', () {
      final c = build()..onSignedIn('u-1');
      c.handleTap(target(roomId: 'r-1'));
      expect(navigations, <String>[AppTab.questionRoom]);
    });

    test('thread_id 만 있어도 질문방 탭(정밀 이동은 후속)', () {
      final c = build()..onSignedIn('u-1');
      c.handleTap(target(threadId: 't-1'));
      expect(navigations, <String>[AppTab.questionRoom]);
    });

    test('개별질문(iq_*) + question_id → 개별질문 탭', () {
      final c = build()..onSignedIn('u-1');
      c.handleTap(target(
        type: NotificationEventType.individualQuestionAnswered,
        questionId: 'q-1',
      ));
      expect(navigations, <String>[AppTab.individualQuestion]);
    });

    test('구독·멘토 공지류 → 마이페이지(가상 목적지, id 불필요)', () {
      final c = build()..onSignedIn('u-1');
      c.handleTap(target(
        type: NotificationEventType.subscriptionExpired,
        eventId: 'n-1',
      ));
      c.handleTap(target(
        type: NotificationEventType.mentorTerminationNotice,
        eventId: 'n-2',
      ));
      expect(navigations, <String>[AppTab.myPage, AppTab.myPage]);
    });

    test('stay(맞춤의뢰류)·unknown → 절대 이동하지 않는다', () {
      final c = build()..onSignedIn('u-1');
      c.handleTap(target(type: NotificationEventType.newOrderMessage));
      c.handleTap(target(type: NotificationEventType.newApplication));
      c.handleTap(target(type: NotificationEventType.unknown));
      expect(navigations, isEmpty);
    });

    test('아는 타입인데 필요한 id 부재 → 알림 탭 폴백', () {
      final c = build()..onSignedIn('u-1');
      c.handleTap(target()); // question_answered, room/thread id 없음.
      c.handleTap(target(
        type: NotificationEventType.individualQuestionAssigned,
        eventId: 'n-2',
      )); // question_id 없음.
      expect(navigations, <String>[AppTab.notifications, AppTab.notifications]);
    });
  });

  group('중복 제거(eventId LRU)', () {
    test('같은 eventId 재전달(포그라운드+탭+콜드스타트 중복) → 1회만 이동', () {
      final c = build()..onSignedIn('u-1');
      final t = target(roomId: 'r-1', eventId: 'n-1');
      c.handleTap(t);
      c.handleTap(t);
      c.handleTap(t);
      expect(navigations, <String>[AppTab.questionRoom]);
    });

    test('eventId 가 다르면 각각 이동한다', () {
      final c = build()..onSignedIn('u-1');
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      c.handleTap(target(roomId: 'r-1', eventId: 'n-2'));
      expect(navigations.length, 2);
    });

    test('빈 eventId 는 dedup 불가 — 매 수신을 새 이벤트로 처리(안전측)', () {
      final c = build()..onSignedIn('u-1');
      c.handleTap(target(roomId: 'r-1'));
      c.handleTap(target(roomId: 'r-1'));
      expect(navigations.length, 2);
    });
  });

  group('로그인 대기(pending)', () {
    test('비로그인 탭 → 보류, 로그인 성공 시 정확히 1회 이동', () {
      final c = build();
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      expect(navigations, isEmpty);
      expect(c.hasPendingForTest, isTrue);

      c.onSignedIn('u-1');
      expect(navigations, <String>[AppTab.questionRoom]);

      c.onSignedIn('u-1'); // 재차 로그인 이벤트 — 추가 이동 없음.
      expect(navigations.length, 1);
    });

    test('보류 중 같은 eventId 중복 탭 → pending 1건, 이동도 1회', () {
      final c = build();
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      c.onSignedIn('u-1');
      expect(navigations.length, 1);
    });

    test('TTL(15분) 초과 후 로그인 → 오래된 이동 폐기', () {
      final c = build();
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      now = now.add(const Duration(minutes: 16));
      c.onSignedIn('u-1');
      expect(navigations, isEmpty);
      expect(c.hasPendingForTest, isFalse);
    });

    test('TTL 이내 로그인 → 이동한다(경계 확인)', () {
      final c = build();
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      now = now.add(const Duration(minutes: 14));
      c.onSignedIn('u-1');
      expect(navigations, <String>[AppTab.questionRoom]);
    });

    test('로그아웃 → pending 폐기', () {
      final c = build();
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      c.onSignedOut();
      c.onSignedIn('u-1');
      expect(navigations, isEmpty);
    });

    test('계정 전환: 이전 사용자 몫 pending 은 다른 사용자 로그인 시 폐기', () {
      final c = build();
      // u-a 사용 이력 → 로그아웃 → 그 뒤 도착한 푸시 탭은 u-a 몫으로 보류.
      c.onSignedIn('u-a');
      c.onSignedOut();
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      expect(c.hasPendingForTest, isTrue);

      c.onSignedIn('u-b'); // 다른 계정 — 폐기.
      expect(navigations, isEmpty);
      expect(c.hasPendingForTest, isFalse);
    });

    test('같은 사용자가 다시 로그인하면 pending 을 실행한다', () {
      final c = build();
      c.onSignedIn('u-a');
      c.onSignedOut();
      c.handleTap(target(roomId: 'r-1', eventId: 'n-1'));
      c.onSignedIn('u-a');
      expect(navigations, <String>[AppTab.questionRoom]);
    });
  });

  group('라우팅 테이블(resolveNotificationDeepLink) — type+id → route', () {
    const String roomUuid = '11111111-2222-4333-8444-555555555555';
    const String threadUuid = '21111111-2222-4333-8444-555555555555';
    const String questionUuid = '31111111-2222-4333-8444-555555555555';
    const String mentorUuid = '41111111-2222-4333-8444-555555555555';
    const String postUuid = '51111111-2222-4333-8444-555555555555';
    const String shortformUuid = '61111111-2222-4333-8444-555555555555';

    test('question_answered + 유효 room/thread UUID → 방 상세 route', () {
      final NotificationDeepLinkRoute? r = resolveNotificationDeepLink(
        target(roomId: roomUuid, threadId: threadUuid),
      );
      expect(r, isA<NotificationRoomRoute>());
      final NotificationRoomRoute room = r! as NotificationRoomRoute;
      expect(room.roomId, roomUuid);
      expect(room.threadId, threadUuid);
    });

    test('UUID 형식 불량 id → 상세 대신 탭 폴백(임의 문자열 조회 금지)', () {
      expect(
        resolveNotificationDeepLink(target(roomId: 'r-1; drop table')),
        isA<NotificationTabRoute>()
            .having((NotificationTabRoute t) => t.location, 'location',
                AppTab.questionRoom),
      );
    });

    test('iq_* + 유효 question UUID → IQ 상세 route', () {
      final NotificationDeepLinkRoute? r = resolveNotificationDeepLink(target(
        type: NotificationEventType.individualQuestionAnswered,
        questionId: questionUuid,
      ));
      expect(r, isA<NotificationIqRoute>());
      expect((r! as NotificationIqRoute).questionId, questionUuid);
    });

    test('구독·멘토 공지류 + metadata id → 멘토/게시판/숏폼 상세 route', () {
      expect(
        resolveNotificationDeepLink(NotificationDeepLinkTarget(
          type: NotificationEventType.mentorSubscriptionPriceChanged,
          mentorId: mentorUuid,
        )),
        isA<NotificationMentorRoute>().having(
            (NotificationMentorRoute r) => r.mentorId, 'mentorId', mentorUuid),
      );
      expect(
        resolveNotificationDeepLink(NotificationDeepLinkTarget(
          type: NotificationEventType.subscriptionExpired,
          postId: postUuid,
        )),
        isA<NotificationBoardPostRoute>().having(
            (NotificationBoardPostRoute r) => r.postId, 'postId', postUuid),
      );
      expect(
        resolveNotificationDeepLink(NotificationDeepLinkTarget(
          type: NotificationEventType.subscriptionExpired,
          shortformId: shortformUuid,
        )),
        isA<NotificationShortformRoute>().having(
            (NotificationShortformRoute r) => r.shortformId, 'shortformId',
            shortformUuid),
      );
      // id 없으면 종전과 같은 마이페이지 탭.
      expect(
        resolveNotificationDeepLink(target(
            type: NotificationEventType.subscriptionExpired, eventId: 'n-9')),
        isA<NotificationTabRoute>().having(
            (NotificationTabRoute t) => t.location, 'location', AppTab.myPage),
      );
    });

    test('맞춤의뢰(stay)·unknown → route 없음(제외 유지)', () {
      expect(
        resolveNotificationDeepLink(target(
            type: NotificationEventType.newOrderMessage,
            questionId: questionUuid)),
        isNull,
      );
      expect(
        resolveNotificationDeepLink(
            target(type: NotificationEventType.unknown, roomId: roomUuid)),
        isNull,
      );
    });

    test('openDetail 배선 시 상세 route 는 openDetail 로, 탭 route 는 navigate 로',
        () {
      final List<String> tabs = <String>[];
      final List<NotificationDeepLinkRoute> details =
          <NotificationDeepLinkRoute>[];
      final NotificationDeepLinkController c = NotificationDeepLinkController(
        navigate: tabs.add,
        openDetail: details.add,
      )..onSignedIn('u-1');

      c.handleTap(target(roomId: roomUuid, eventId: 'n-1'));
      c.handleTap(target(
          type: NotificationEventType.subscriptionExpired, eventId: 'n-2'));

      expect(details.length, 1);
      expect(details.single, isA<NotificationRoomRoute>());
      expect(tabs, <String>[AppTab.myPage]);
    });

    test('openDetail 미배선이면 상세 route 도 탭 폴백(기존 계약 호환)', () {
      final List<String> tabs = <String>[];
      final NotificationDeepLinkController c =
          NotificationDeepLinkController(navigate: tabs.add)
            ..onSignedIn('u-1');
      c.handleTap(target(roomId: roomUuid, eventId: 'n-1'));
      c.handleTap(target(
        type: NotificationEventType.individualQuestionAnswered,
        questionId: questionUuid,
        eventId: 'n-2',
      ));
      expect(tabs, <String>[AppTab.questionRoom, AppTab.individualQuestion]);
    });

    test('notificationRouteFallbackLocation — route 종류별 URL', () {
      expect(
        notificationRouteFallbackLocation(
            const NotificationRoomRoute(roomId: roomUuid)),
        AppTab.questionRoom,
      );
      expect(
        notificationRouteFallbackLocation(const NotificationIqRoute(questionUuid)),
        AppTab.individualQuestion,
      );
      expect(
        notificationRouteFallbackLocation(
            const NotificationBoardPostRoute(postUuid)),
        AppTab.community,
      );
      expect(
        notificationRouteFallbackLocation(
            const NotificationShortformRoute(shortformUuid)),
        AppTab.community,
      );
      expect(
        notificationRouteFallbackLocation(const NotificationMentorRoute(mentorUuid)),
        AppTab.mentors,
      );
    });
  });

  group('외부 경로 차단', () {
    test('payload 의 link/url 필드는 무시된다 — 탭 이동 외 어떤 실행도 없다', () {
      // 파싱 단계: link/url 은 PushPayload 에 보관 자리조차 없다.
      final PushPayload p = PushPayload.fromRemote(const <String, dynamic>{
        'type': 'question_answered',
        'room_id': 'r-1',
        'notification_id': 'n-1',
        'link': 'https://evil.example/wallet/charge',
        'url': 'someapp://external',
      });
      final c = build()..onSignedIn('u-1');
      // 컨트롤러에는 런처/URL 실행 의존성이 아예 없다 — 상호작용은 navigate 뿐.
      c.handleTap(NotificationDeepLinkTarget(
        type: p.type,
        roomId: p.roomId,
        threadId: p.threadId,
        questionId: p.questionId,
        eventId: p.eventId,
      ));
      expect(navigations, <String>[AppTab.questionRoom]); // 허용 URL 이동 1회가 전부.
    });
  });
}
