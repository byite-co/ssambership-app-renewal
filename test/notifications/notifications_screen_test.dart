import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_tabs.dart';
import 'package:ssambership_app/design/widgets/chip_scroll.dart';
import 'package:ssambership_app/design/widgets/count_badge.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';
import 'package:ssambership_app/features/notifications/notifications_screen.dart';
import 'package:ssambership_app/features/notifications/ui/widgets/notification_card.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 단순 fake — 전 항목을 한 페이지로 돌려준다(실패 주입 가능).
class _FakeRepo implements NotificationsRepository {
  _FakeRepo(this.items);

  final List<AppNotification> items;
  final List<String> readCalls = <String>[];
  int markAllCalls = 0;
  bool failFetch = false;
  bool failMarkRead = false;
  bool failMarkAll = false;

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) async {
    if (failFetch) throw const AppError('네트워크 오류가 발생했어요.');
    return NotificationsPage(
        items: List<AppNotification>.of(items), hasNext: false);
  }

  @override
  Future<void> markRead(String id) async {
    if (failMarkRead) throw const AppError('저장하지 못했어요.');
    readCalls.add(id);
  }

  @override
  Future<int> markAllRead() async {
    markAllCalls++;
    if (failMarkAll) throw const AppError('저장하지 못했어요.');
    return items.where((AppNotification n) => !n.isRead).length;
  }
}

/// 페이지 시퀀스 fake — fetch 호출 순서대로 미리 준비한 페이지를 돌려준다.
class _PagedRepo implements NotificationsRepository {
  _PagedRepo(this.pages);

  final List<NotificationsPage> pages;
  final List<NotificationCursor?> afters = <NotificationCursor?>[];
  int calls = 0;

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) async {
    afters.add(after);
    final NotificationsPage p =
        pages[calls < pages.length ? calls : pages.length - 1];
    calls++;
    return p;
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

/// 수동 완료 fake — 응답 시점을 테스트가 제어한다(낡은 응답 폐기 검증용).
class _ManualRepo implements NotificationsRepository {
  final List<Completer<NotificationsPage>> pending =
      <Completer<NotificationsPage>>[];

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) {
    final Completer<NotificationsPage> c = Completer<NotificationsPage>();
    pending.add(c);
    return c.future;
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

AppNotification _n(
  String id,
  String typeCode,
  String body, {
  bool read = false,
  int minute = 0,
}) =>
    AppNotification(
      id: id,
      eventType: NotificationEventType.fromCode(typeCode),
      body: body,
      isRead: read,
      createdAt: DateTime(2026, 7, 1, 10, minute),
    );

/// CR·환불·미지 유형 포함 — 이제 전부 표시되어야 한다(P2-15).
List<AppNotification> _sample() => <AppNotification>[
      _n('a', 'question_answered', 'A 질문방 알림', minute: 9),
      _n('b', 'subscription_expired', 'B 구독 알림', minute: 8),
      _n('c', 'question_answered', 'C 읽은 질문방', read: true, minute: 7),
      _n('d', 'new_order_message', 'D 맞춤의뢰 알림', minute: 6),
      _n('e', 'mentor_termination_refund', 'E 환불 알림', minute: 5),
      _n('f', 'individual_question_answered', 'F 개별질문 알림', minute: 4),
      _n('g', 'weird_unknown_type', 'G 미지 알림', minute: 3),
    ];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Finder _typeChip(String label) =>
    find.descendant(of: find.byType(ChipScroll), matching: find.text(label));

Finder _readBtnOf(String body) => find.descendant(
      of: find.ancestor(
          of: find.text(body), matching: find.byType(NotificationCard)),
      matching: find.text('읽음'),
    );

int _badgeCount(WidgetTester tester) =>
    tester.widget<CountBadge>(find.byType(CountBadge)).count;

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('모든 유형 렌더 — 맞춤의뢰·환불·미지 포함(숨김 없음) + 안읽음 카운트',
      (WidgetTester tester) async {
    await _tall(tester);
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: _FakeRepo(_sample()),
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('A 질문방 알림'), findsOneWidget);
    expect(find.text('B 구독 알림'), findsOneWidget);
    expect(find.text('C 읽은 질문방'), findsOneWidget);
    // ★ 맞춤의뢰·환불·미지 유형도 노출된다(이전 정책의 제외 제거).
    expect(find.text('D 맞춤의뢰 알림'), findsOneWidget);
    expect(find.text('E 환불 알림'), findsOneWidget);
    expect(find.text('F 개별질문 알림'), findsOneWidget);
    expect(find.text('G 미지 알림'), findsOneWidget);
    // 미지 유형은 '기타' 라벨의 일반 알림으로 표시(영문 코드 비노출).
    expect(find.text('기타'), findsOneWidget);
    expect(find.textContaining('weird'), findsNothing);
    // 안읽음 = a,b,d,e,f,g (c만 읽음).
    expect(_badgeCount(tester), 6);
  });

  testWidgets('필터 칩: 맞춤의뢰 칩 미노출(CR 게이트 OFF), 기타 는 전용 칩 없음(전체에서만)',
      (WidgetTester tester) async {
    await _tall(tester);
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: _FakeRepo(_sample()),
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    // 칩 구성(2026-07 QA4): 전체/질문방/구독·결제/개별질문 — 맞춤의뢰 칩은
    // CR 게이트 OFF 로 미노출(해당 이벤트 2종은 레포 쿼리에서 exact 제외),
    // 기타 칩도 없다.
    for (final String label in <String>['전체', '질문방', '구독·결제', '개별질문']) {
      expect(_typeChip(label), findsOneWidget, reason: label);
    }
    expect(_typeChip('맞춤의뢰'), findsNothing);
    expect(_typeChip('기타'), findsNothing);

    await tester.tap(_typeChip('질문방'));
    await tester.pumpAndSettle();
    expect(find.text('A 질문방 알림'), findsOneWidget);
    expect(find.text('C 읽은 질문방'), findsOneWidget);
    expect(find.text('B 구독 알림'), findsNothing);
  });

  testWidgets(
      '딥링크: 질문방→질문방 탭, 구독→마이페이지, 개별질문→개별질문 탭, '
      '맞춤의뢰·미지→이동 없음(읽음 처리만)', (WidgetTester tester) async {
    await _tall(tester);
    final _FakeRepo repo = _FakeRepo(_sample());
    final List<int> tabs = <int>[];
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: tabs.add,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('A 질문방 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B 구독 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('F 개별질문 알림'));
    await tester.pumpAndSettle();
    expect(tabs, <int>[
      AppTab.questionRoom,
      AppTab.myPage,
      AppTab.individualQuestion,
    ]);

    // 맞춤의뢰(stay)·미지(unknown) — 이동하지 않고 읽음 처리만 된다.
    await tester.tap(find.text('D 맞춤의뢰 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G 미지 알림'));
    await tester.pumpAndSettle();
    expect(tabs.length, 3); // 추가 이동 없음
    expect(repo.readCalls, containsAll(<String>['d', 'g']));
  });

  testWidgets('읽음 처리 성공 → repo 호출 + 안읽음 카운트 감소', (WidgetTester tester) async {
    await _tall(tester);
    final _FakeRepo repo = _FakeRepo(_sample());
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(_badgeCount(tester), 6);
    await tester.tap(_readBtnOf('A 질문방 알림'));
    await tester.pumpAndSettle();

    expect(repo.readCalls, contains('a'));
    expect(_badgeCount(tester), 5);
  });

  testWidgets('읽음 처리 실패 → 미읽음 유지 + 스낵바(성공 후에만 UI 반영)',
      (WidgetTester tester) async {
    await _tall(tester);
    final _FakeRepo repo = _FakeRepo(_sample())..failMarkRead = true;
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(_readBtnOf('A 질문방 알림'));
    await tester.pumpAndSettle();

    expect(_badgeCount(tester), 6); // 그대로
    expect(_readBtnOf('A 질문방 알림'), findsOneWidget); // 여전히 미읽음
    expect(find.textContaining('읽음 처리에 실패했어요'), findsOneWidget);
  });

  testWidgets('모두 읽음 성공 → RPC 1회 + 전부 읽음 + 카운트 0', (WidgetTester tester) async {
    await _tall(tester);
    final _FakeRepo repo = _FakeRepo(_sample());
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();

    expect(repo.markAllCalls, 1);
    expect(_badgeCount(tester), 0);
    expect(find.text('읽음'), findsNothing); // 개별 읽음 버튼도 모두 사라짐
  });

  testWidgets('모두 읽음 실패 → 이전 상태 유지 + 스낵바', (WidgetTester tester) async {
    await _tall(tester);
    final _FakeRepo repo = _FakeRepo(_sample())..failMarkAll = true;
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();

    expect(_badgeCount(tester), 6); // 그대로
    expect(find.textContaining('모두 읽음 처리에 실패했어요'), findsOneWidget);
  });

  testWidgets('새로고침 실패 → 기존 목록 유지 + 스낵바', (WidgetTester tester) async {
    await _tall(tester);
    final _FakeRepo repo = _FakeRepo(_sample());
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('A 질문방 알림'), findsOneWidget);

    repo.failFetch = true;
    await tester.fling(find.text('A 질문방 알림'), const Offset(0, 600), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // 목록이 지워지지 않고 그대로 남는다.
    expect(find.text('A 질문방 알림'), findsOneWidget);
    expect(find.text('B 구독 알림'), findsOneWidget);
    expect(find.textContaining('알림을 새로 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('더 보기: 커서 전달 + 경계 중복 id 는 한 번만 표시', (WidgetTester tester) async {
    await _tall(tester);
    const NotificationCursor c1 =
        NotificationCursor(createdAtRaw: '2026-07-01T01:00:00+00:00', id: 'b');
    final _PagedRepo repo = _PagedRepo(<NotificationsPage>[
      NotificationsPage(
        items: <AppNotification>[
          _n('a', 'question_answered', 'A 질문방 알림', minute: 9),
          _n('b', 'subscription_expired', 'B 구독 알림', minute: 8),
        ],
        hasNext: true,
        next: c1,
      ),
      NotificationsPage(
        items: <AppNotification>[
          _n('b', 'subscription_expired', 'B 중복(경계) 알림', minute: 8),
          _n('h', 'question_answered', 'H 다음 페이지 알림', minute: 7),
        ],
        hasNext: false,
      ),
    ]);
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('더 보기'));
    await tester.pumpAndSettle();

    expect(repo.afters, <NotificationCursor?>[null, c1]); // 커서 전달 확인
    expect(find.text('H 다음 페이지 알림'), findsOneWidget);
    // 경계 중복(id 'b')은 다시 붙지 않는다.
    expect(find.text('B 구독 알림'), findsOneWidget);
    expect(find.text('B 중복(경계) 알림'), findsNothing);
    expect(find.text('더 보기'), findsNothing); // hasNext=false
  });

  testWidgets('낡은 응답 폐기: 새로고침 뒤 도착한 이전 세대 더 보기 응답은 버린다',
      (WidgetTester tester) async {
    await _tall(tester);
    final _ManualRepo repo = _ManualRepo();
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: (_) {},
    )));
    await tester.pump();

    // 1) 첫 로드 완료(1페이지 + 더 보기).
    expect(repo.pending.length, 1);
    repo.pending[0].complete(NotificationsPage(
      items: <AppNotification>[_n('a', 'question_answered', 'A 질문방 알림')],
      hasNext: true,
      next: const NotificationCursor(
          createdAtRaw: '2026-07-01T01:00:00+00:00', id: 'a'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('A 질문방 알림'), findsOneWidget);

    // 2) 더 보기 요청(응답 보류).
    await tester.tap(find.text('더 보기'));
    await tester.pump();
    expect(repo.pending.length, 2);

    // 3) 새로고침(세대 +1, 응답 보류).
    await tester.fling(find.text('A 질문방 알림'), const Offset(0, 600), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repo.pending.length, 3);

    // 4) 새로고침 응답 먼저 도착 → 새 목록.
    repo.pending[2].complete(NotificationsPage(
      items: <AppNotification>[_n('z', 'question_answered', 'Z 새 알림')],
      hasNext: false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Z 새 알림'), findsOneWidget);
    expect(find.text('A 질문방 알림'), findsNothing);

    // 5) 이전 세대의 더 보기 응답이 늦게 도착 — 버려져야 한다.
    repo.pending[1].complete(NotificationsPage(
      items: <AppNotification>[_n('s', 'question_answered', 'S 낡은 알림')],
      hasNext: false,
    ));
    await tester.pumpAndSettle();
    expect(find.text('S 낡은 알림'), findsNothing);
    expect(find.text('Z 새 알림'), findsOneWidget);
  });

  testWidgets('첫 로드 실패 → 오류 안내 + 다시 시도로 복구', (WidgetTester tester) async {
    final _FakeRepo repo = _FakeRepo(_sample())..failFetch = true;
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: repo,
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('알림을 불러오지 못했어요'), findsOneWidget);
    // 원문(영문 코드) 비노출.
    expect(find.textContaining('네트워크 오류가 발생했어요'), findsOneWidget);

    repo.failFetch = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('A 질문방 알림'), findsOneWidget);
  });

  testWidgets('빈 상태 안내', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(NotificationsScreen(
      repository: _FakeRepo(<AppNotification>[]),
      onDeepLinkTab: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('새 알림이 없어요'), findsOneWidget);
  });
}
