import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/ui/widgets/notification_card.dart';

AppNotification _n({
  bool read = false,
  NotificationEventType eventType = NotificationEventType.questionAnswered,
  String body = '새 답변이 있어요',
  String? title,
}) =>
    AppNotification(
      id: '1',
      eventType: eventType,
      title: title,
      body: body,
      isRead: read,
      createdAt: DateTime(2026, 7, 1, 10, 0),
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('유형칩·본문·읽음 버튼 렌더 + 탭/읽음 콜백', (WidgetTester tester) async {
    int open = 0;
    int read = 0;
    await tester.pumpWidget(_wrap(NotificationCard(
      notification: _n(),
      onOpen: () => open++,
      onMarkRead: () => read++,
    )));

    expect(find.text('질문방'), findsOneWidget); // 유형칩(한글, 코드 비노출)
    expect(find.text('새 답변이 있어요'), findsOneWidget);
    expect(find.text('읽음'), findsOneWidget);

    await tester.tap(find.text('읽음'));
    await tester.pump();
    expect(read, 1);
    expect(open, 0); // 읽음 버튼은 이동하지 않음

    await tester.tap(find.text('새 답변이 있어요'));
    await tester.pump();
    expect(open, 1);
  });

  testWidgets('읽은 알림은 "읽음" 버튼이 없다', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(NotificationCard(
      notification: _n(read: true),
      onOpen: () {},
      onMarkRead: () {},
    )));
    expect(find.text('읽음'), findsNothing);
  });

  testWidgets('data.title 이 있으면 제목도 렌더', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(NotificationCard(
      notification: _n(title: '새 답변 도착', body: '본문 미리보기'),
      onOpen: () {},
      onMarkRead: () {},
    )));
    expect(find.text('새 답변 도착'), findsOneWidget);
    expect(find.text('본문 미리보기'), findsOneWidget);
  });

  testWidgets('맞춤의뢰·기타 유형도 한글 칩으로 렌더(코드 비노출)', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(NotificationCard(
      notification: _n(
        eventType: NotificationEventType.newOrderMessage,
        body: '맞춤의뢰 소식이 있어요.',
      ),
      onOpen: () {},
      onMarkRead: () {},
    )));
    expect(find.text('맞춤의뢰'), findsOneWidget);
    expect(find.textContaining('new_order_message'), findsNothing);

    await tester.pumpWidget(_wrap(NotificationCard(
      notification: _n(
        eventType: NotificationEventType.unknown,
        body: '새 알림이 있어요.',
      ),
      onOpen: () {},
      onMarkRead: () {},
    )));
    expect(find.text('기타'), findsOneWidget);
  });
}
