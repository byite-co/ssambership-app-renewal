import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notification_badge_controller.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';
import 'package:ssambership_app/features/notifications/notifications_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 배지(서버 개수 단일 소스)·읽음 봉투·실시간 dedup upsert — 순수/컨트롤러 검증.
class _CountRepo implements NotificationsRepository {
  _CountRepo(this.count);

  int count;
  bool fail = false;
  int calls = 0;

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) async =>
      const NotificationsPage(items: <AppNotification>[], hasNext: false);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;

  @override
  Future<int> unreadCount() async {
    calls++;
    if (fail) throw const AppError('네트워크');
    return count;
  }
}

AppNotification _n(String id) => AppNotification(
      id: id,
      eventType: NotificationEventType.questionAnswered,
      body: '알림 $id',
      isRead: false,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  group('notificationBadgeLabel — 서버 개수만으로 결정', () {
    test('null(미확인)·0 → 숨김(null)', () {
      expect(notificationBadgeLabel(null), isNull);
      expect(notificationBadgeLabel(0), isNull);
    });
    test('1·99 → 숫자 그대로', () {
      expect(notificationBadgeLabel(1), '1');
      expect(notificationBadgeLabel(99), '99');
    });
    test('100 이상 → 99+', () {
      expect(notificationBadgeLabel(100), '99+');
      expect(notificationBadgeLabel(1234), '99+');
    });
  });

  group('parseUnreadCountEnvelope — strict 계약 파싱', () {
    test('정본 봉투 → count', () {
      expect(
        parseUnreadCountEnvelope(<String, dynamic>{
          'ok': true,
          'count': 7,
          'contract_version': 1,
        }),
        7,
      );
      expect(
        parseUnreadCountEnvelope(<String, dynamic>{
          'ok': true,
          'count': 0,
          'contract_version': 1,
        }),
        0,
      );
    });

    test('계약 밖(ok 아님·버전 불일치·count 손상) → null(개수 위장 금지)', () {
      expect(parseUnreadCountEnvelope(null), isNull);
      expect(parseUnreadCountEnvelope(5), isNull);
      expect(
        parseUnreadCountEnvelope(
            <String, dynamic>{'ok': false, 'count': 3, 'contract_version': 1}),
        isNull,
      );
      expect(
        parseUnreadCountEnvelope(
            <String, dynamic>{'ok': true, 'count': 3, 'contract_version': 2}),
        isNull,
      );
      expect(
        parseUnreadCountEnvelope(<String, dynamic>{
          'ok': true,
          'count': -1,
          'contract_version': 1,
        }),
        isNull,
      );
      expect(
        parseUnreadCountEnvelope(<String, dynamic>{
          'ok': true,
          'count': 'x',
          'contract_version': 1,
        }),
        isNull,
      );
    });
  });

  group('isMarkNotificationReadSuccess — 단건 읽음 멱등 봉투', () {
    test('{ok, contract_version:1} 성공 — idempotent_hit 무관', () {
      expect(
        isMarkNotificationReadSuccess(<String, dynamic>{
          'ok': true,
          'contract_version': 1,
          'idempotent_hit': false,
        }),
        isTrue,
      );
      expect(
        isMarkNotificationReadSuccess(<String, dynamic>{
          'ok': true,
          'contract_version': 1,
          'idempotent_hit': true, // 이미 읽음 — 멱등 성공.
        }),
        isTrue,
      );
    });

    test('실패 봉투·계약 밖 → 실패(성공 위장 금지)', () {
      expect(isMarkNotificationReadSuccess(null), isFalse);
      expect(isMarkNotificationReadSuccess(<String, dynamic>{'ok': false}),
          isFalse);
      expect(
        isMarkNotificationReadSuccess(
            <String, dynamic>{'ok': true, 'contract_version': 2}),
        isFalse,
      );
    });
  });

  group('NotificationBadgeController — 서버 정본 + 낙관 감소/롤백', () {
    test('refresh → 서버 값, 실패 시 마지막 값 유지', () async {
      final _CountRepo repo = _CountRepo(5);
      final NotificationBadgeController c =
          NotificationBadgeController(repository: repo);
      expect(c.count.value, isNull);
      await c.refresh();
      expect(c.count.value, 5);

      repo.fail = true;
      await c.refresh();
      expect(c.count.value, 5, reason: '실패는 값 날조·초기화 없이 유지');
    });

    test('낙관 감소 → 실패 롤백(0 미만 금지·미확인 상태 무동작)', () async {
      final NotificationBadgeController c =
          NotificationBadgeController(repository: _CountRepo(2));
      c.onMarkReadOptimistic();
      expect(c.count.value, isNull, reason: '서버 확인 전에는 만들지 않는다');

      await c.refresh();
      c.onMarkReadOptimistic();
      expect(c.count.value, 1);
      c.rollbackMarkRead();
      expect(c.count.value, 2);

      c.onMarkReadOptimistic();
      c.onMarkReadOptimistic();
      c.onMarkReadOptimistic(); // 0 에서 추가 감소 없음.
      expect(c.count.value, 0);
    });

    test('clear → 이전 사용자 값 폐기(배지 숨김)', () async {
      final NotificationBadgeController c =
          NotificationBadgeController(repository: _CountRepo(3));
      await c.refresh();
      expect(c.count.value, 3);
      c.clear();
      expect(c.count.value, isNull);
    });
  });

  group('실시간 dedup upsert — 화면과 같은 경로(appendNotificationsDeduped)', () {
    test('같은 id 이벤트가 중복 도착해도 목록에는 1개', () {
      final List<AppNotification> items = <AppNotification>[];
      final Set<String> seen = <String>{};
      appendNotificationsDeduped(items, seen, <AppNotification>[_n('a')]);
      // 실시간 중복 이벤트(재전송) — seen 가드로 0건 추가.
      final int added =
          appendNotificationsDeduped(items, seen, <AppNotification>[_n('a')]);
      expect(added, 0);
      expect(items.length, 1);
    });
  });
}
