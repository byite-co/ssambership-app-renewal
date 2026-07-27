import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';
import 'package:ssambership_app/features/notifications/notifications_screen.dart';

/// id 를 0채움 2자리로 만들어 문자열 비교가 수 비교와 일치하게 한다.
String _id(int i) => 'n${i.toString().padLeft(2, '0')}';

Map<String, dynamic> _row(int i, String createdAt) => <String, dynamic>{
      'id': _id(i),
      'type': 'question_answered',
      'body': '알림 ${_id(i)}',
      'is_read': false,
      'read': false,
      'created_at': createdAt,
      'data': null,
      'metadata': null,
    };

/// 키셋 페이징을 서버처럼 흉내 내는 fake — (created_at DESC, id DESC) 정렬과
/// (created_at, id) < 커서 필터를 그대로 구현한다. created_at 원문 문자열 비교
/// (UTC ISO8601 동일 포맷 가정 — 서버 저장 원문 그대로 통과).
class _KeysetFakeRepo implements NotificationsRepository {
  _KeysetFakeRepo(List<Map<String, dynamic>> rows)
      : _rows = List<Map<String, dynamic>>.of(rows) {
    _rows.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int c =
          (b['created_at'] as String).compareTo(a['created_at'] as String);
      if (c != 0) return c;
      return (b['id'] as String).compareTo(a['id'] as String);
    });
  }

  final List<Map<String, dynamic>> _rows;
  int fetchCalls = 0;

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) async {
    fetchCalls++;
    Iterable<Map<String, dynamic>> filtered = _rows;
    if (after != null) {
      filtered = _rows.where((Map<String, dynamic> r) {
        final int c = (r['created_at'] as String).compareTo(after.createdAtRaw);
        if (c != 0) return c < 0;
        return (r['id'] as String).compareTo(after.id) < 0;
      });
    }
    return assembleNotificationsPage(
        filtered.take(pageSize + 1).toList(), pageSize);
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

void main() {
  group('assembleNotificationsPage(순수 조립 로직)', () {
    test('pageSize 이하 → hasNext=false, next=null', () {
      final NotificationsPage p =
          assembleNotificationsPage(<Map<String, dynamic>>[
        _row(1, '2026-07-01T00:00:02+00:00'),
        _row(0, '2026-07-01T00:00:01+00:00'),
      ], 2);
      expect(p.items.length, 2);
      expect(p.hasNext, false);
      expect(p.next, isNull);
    });

    test('pageSize+1 → 초과분 잘라내고 hasNext=true + 마지막 행 원문 커서', () {
      final NotificationsPage p =
          assembleNotificationsPage(<Map<String, dynamic>>[
        _row(2, '2026-07-01T00:00:03.123456+00:00'),
        _row(1, '2026-07-01T00:00:02.999999+00:00'),
        _row(0, '2026-07-01T00:00:01+00:00'),
      ], 2);
      expect(p.items.length, 2);
      expect(p.hasNext, true);
      // 커서는 '표시된 마지막 행'의 created_at 원문(µs 그대로) + id.
      expect(p.next!.createdAtRaw, '2026-07-01T00:00:02.999999+00:00');
      expect(p.next!.id, _id(1));
    });

    test('빈 결과 → 빈 페이지', () {
      final NotificationsPage p =
          assembleNotificationsPage(<Map<String, dynamic>>[], 20);
      expect(p.items, isEmpty);
      expect(p.hasNext, false);
      expect(p.next, isNull);
    });
  });

  test('notificationsAfterFilter — (created_at,id) 키셋 or 식(원문 통과)', () {
    const NotificationCursor c = NotificationCursor(
      createdAtRaw: '2026-07-01T00:00:02.123456+00:00',
      id: 'abc',
    );
    expect(
      notificationsAfterFilter(c),
      'created_at.lt.2026-07-01T00:00:02.123456+00:00,'
      'and(created_at.eq.2026-07-01T00:00:02.123456+00:00,id.lt.abc)',
    );
  });

  group('키셋 다중 페이지 타일링(경계 동일 created_at)', () {
    test('동일 created_at 이 페이지 경계에 걸려도 중복·누락 없음', () async {
      // 45건(id n00~n44), 내림차순으로 id 44→0. 동일 created_at 묶음 두 개가
      // 페이지 경계(20/21번째, 40/41번째)를 가로지르도록 배치:
      //  - ids 21~26 → 같은 시각(26초): 1페이지가 26,25 에서 끊기고 2페이지가 24~21 로 이어짐
      //  - ids 2~6  → 같은 시각(6초):  2페이지가 6,5 에서 끊기고 3페이지가 4~2 로 이어짐
      String ts(int sec) =>
          '2026-07-01T00:00:${sec.toString().padLeft(2, '0')}+00:00';
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        for (int i = 0; i < 45; i++)
          _row(
            i,
            ts((i >= 21 && i <= 26)
                ? 26
                : (i >= 2 && i <= 6)
                    ? 6
                    : i),
          ),
      ];
      final _KeysetFakeRepo repo = _KeysetFakeRepo(rows);

      // 화면이 쓰는 동일한 경로(appendNotificationsDeduped)로 이어 붙인다.
      final List<AppNotification> items = <AppNotification>[];
      final Set<String> seen = <String>{};
      NotificationsPage page = await repo.fetch(pageSize: 20);
      appendNotificationsDeduped(items, seen, page.items);
      while (page.hasNext) {
        page = await repo.fetch(after: page.next, pageSize: 20);
        appendNotificationsDeduped(items, seen, page.items);
      }

      // 누락 없음: 45건 전부, 중복 없음: id 유일.
      expect(items.length, 45);
      expect(seen.length, 45);
      // 순서도 보존: (created_at, id) 내림차순 = id 44→0.
      expect(
        items.map((AppNotification n) => n.id).toList(),
        <String>[for (int i = 44; i >= 0; i--) _id(i)],
      );
      // 3페이지(20+20+5)로 끝난다 — 무한 루프·재조회 없음.
      expect(repo.fetchCalls, 3);
    });

    test('전 행이 동일 created_at 이어도 id 타이브레이커로 전진한다', () async {
      const String ts = '2026-07-01T00:00:00+00:00';
      final _KeysetFakeRepo repo = _KeysetFakeRepo(
          <Map<String, dynamic>>[for (int i = 0; i < 7; i++) _row(i, ts)]);

      final List<AppNotification> items = <AppNotification>[];
      final Set<String> seen = <String>{};
      NotificationsPage page = await repo.fetch(pageSize: 3);
      appendNotificationsDeduped(items, seen, page.items);
      while (page.hasNext) {
        page = await repo.fetch(after: page.next, pageSize: 3);
        appendNotificationsDeduped(items, seen, page.items);
      }
      expect(items.length, 7);
      // id 내림차순 그대로(중간 뒤섞임 없음).
      expect(items.map((AppNotification n) => n.id).toList(),
          <String>[for (int i = 6; i >= 0; i--) _id(i)]);
    });
  });

  test('appendNotificationsDeduped — 이미 본 id 는 다시 넣지 않는다', () {
    final List<AppNotification> items = <AppNotification>[];
    final Set<String> seen = <String>{};
    AppNotification n(String id) => AppNotification(
          id: id,
          eventType: NotificationEventType.questionAnswered,
          body: '알림 $id',
          isRead: false,
          createdAt: DateTime(2026, 7, 1),
        );
    expect(
        appendNotificationsDeduped(
            items, seen, <AppNotification>[n('a'), n('b')]),
        2);
    // 경계 중복(b)이 다음 페이지에 다시 와도 한 번만 남는다.
    expect(
        appendNotificationsDeduped(
            items, seen, <AppNotification>[n('b'), n('c')]),
        1);
    expect(items.map((AppNotification x) => x.id).toList(),
        <String>['a', 'b', 'c']);
  });
}
