import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mypage/data/notification_settings_repository.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';
import 'package:ssambership_app/features/notifications/notifications_screen.dart';

/// CR 게이트 OFF — 앱 표면에서 맞춤의뢰 알림 2종(exact type)을 노출하지 않는다.
/// 서버 계약(정본 17종 enum·producer)은 불변 — '앱 출시 표면'만 게이트한다.

String _id(int i) => i.toString().padLeft(4, '0');

Map<String, dynamic> _row(int i, String createdAt,
        {String type = 'question_answered'}) =>
    <String, dynamic>{
      'id': _id(i),
      'type': type,
      'body': '알림 $i',
      'is_read': false,
      'created_at': createdAt,
      'data': null,
      'metadata': null,
    };

/// DB 단계 exact 제외를 흉내내는 keyset fake — 실제 레포와 같은
/// (created_at DESC, id DESC) 정렬·cursor 필터 위에 게이트 필터를 먼저 적용한다.
class _GatedKeysetFakeRepo implements NotificationsRepository {
  _GatedKeysetFakeRepo(this.allRows);

  final List<Map<String, dynamic>> allRows;

  @override
  Future<NotificationsPage> fetch(
      {NotificationCursor? after, int pageSize = 20}) async {
    List<Map<String, dynamic>> rows = allRows
        .where(
            (r) => !kGatedNotificationTypeCodes.contains(r['type'] as String))
        .toList()
      ..sort((a, b) {
        final int c =
            (b['created_at'] as String).compareTo(a['created_at'] as String);
        if (c != 0) return c;
        return (b['id'] as String).compareTo(a['id'] as String);
      });
    if (after != null) {
      rows = rows.where((r) {
        final String ca = r['created_at'] as String;
        final String id = r['id'] as String;
        if (ca.compareTo(after.createdAtRaw) < 0) return true;
        return ca == after.createdAtRaw && id.compareTo(after.id) < 0;
      }).toList();
    }
    return assembleNotificationsPage(
        rows.take(pageSize + 1).toList(), pageSize);
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

void main() {
  test('게이트 코드는 정확히 2종 — 부분 문자열 의미 없음(exact 비교)', () {
    expect(kGatedNotificationTypeCodes,
        <String>{'new_order_message', 'new_application'});
    expect(kGatedNotificationTypeCodes.contains('new_order_message2'), isFalse);
    expect(kGatedNotificationTypeCodes.contains('order'), isFalse);
    expect(kGatedNotificationTypeCodes.contains('application'), isFalse);
  });

  test('페이지 경계에 게이트 타입이 섞여도 중복·누락 0 · hasMore 정확 · (created_at,id) cursor 유지',
      () async {
    // 30건: 짝수 index 는 게이트 대상(제외), 동일 created_at 다건 포함(끝자리 3개 동시각).
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
      for (int i = 0; i < 27; i++)
        _row(i, '2026-07-24T0${(9 - (i ~/ 3)).clamp(0, 9)}:00:0${i % 3}',
            type: i.isEven ? 'new_order_message' : 'question_answered'),
      // 동일 created_at 경계 3건(게이트 1 + 노출 2) — id 로만 순서가 갈린다.
      _row(27, '2026-07-24T00:00:00', type: 'new_application'),
      _row(28, '2026-07-24T00:00:00'),
      _row(29, '2026-07-24T00:00:00'),
    ];
    final _GatedKeysetFakeRepo repo = _GatedKeysetFakeRepo(rows);
    final Set<String> expectedIds = rows
        .where(
            (r) => !kGatedNotificationTypeCodes.contains(r['type'] as String))
        .map((r) => r['id'] as String)
        .toSet();

    final List<String> collected = <String>[];
    NotificationCursor? cursor;
    bool hasNext = true;
    int guard = 0;
    while (hasNext && guard < 10) {
      guard++;
      final NotificationsPage page =
          await repo.fetch(after: cursor, pageSize: 5);
      collected.addAll(page.items.map((n) => n.id));
      // 페이지 크기 계약: 마지막 페이지 외에는 pageSize 를 그대로 채운다.
      if (page.hasNext) expect(page.items.length, 5);
      hasNext = page.hasNext;
      cursor = page.next;
    }

    expect(collected.length, collected.toSet().length, reason: '중복 0');
    expect(collected.toSet(), expectedIds, reason: '누락 0 · 게이트 2종 노출 0');
  });

  test('전부 게이트 타입이면 빈 상태 — hasNext false', () async {
    final _GatedKeysetFakeRepo repo =
        _GatedKeysetFakeRepo(<Map<String, dynamic>>[
      _row(0, '2026-07-24T09:00:00', type: 'new_order_message'),
      _row(1, '2026-07-24T08:00:00', type: 'new_application'),
    ]);
    final NotificationsPage page = await repo.fetch(pageSize: 5);
    expect(page.items, isEmpty);
    expect(page.hasNext, isFalse);
  });

  test('다른 타입(unknown 포함)은 기존 안전 fallback 그대로 통과', () async {
    final _GatedKeysetFakeRepo repo =
        _GatedKeysetFakeRepo(<Map<String, dynamic>>[
      _row(0, '2026-07-24T09:00:00', type: 'refund_completed_v99'), // 미지 타입
      _row(1, '2026-07-24T08:00:00', type: 'question_answered'),
    ]);
    final NotificationsPage page = await repo.fetch(pageSize: 5);
    expect(page.items.length, 2); // 미지 타입도 숨기지 않는다(기타 표시)
  });

  testWidgets('알림 화면: 맞춤의뢰 전용 필터 칩 미노출(다른 칩은 유지)', (WidgetTester tester) async {
    final _GatedKeysetFakeRepo repo =
        _GatedKeysetFakeRepo(<Map<String, dynamic>>[
      _row(1, '2026-07-24T08:00:00'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: NotificationsScreen(repository: repo)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('맞춤의뢰'), findsNothing);
    expect(find.text('전체'), findsOneWidget);
    expect(find.text('질문방'), findsWidgets);
    expect(find.text('개별질문'), findsOneWidget);
  });

  test('알림 설정: 서버 key order 는 호환 유지, 라벨만 개별질문 알림으로', () {
    expect(NotificationGroups.keys.contains('order'), isTrue);
    expect(NotificationGroups.labelOf('order'), '개별질문 알림');
    // 다른 그룹 라벨 불변.
    expect(NotificationGroups.labelOf('qna'), '질문방 알림');
    expect(NotificationGroups.labelOf('refund'), '환불 알림');
  });
}
