import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/design/widgets/app_empty_state.dart';

/// v3 빈 상태(AppEmptyState) — 옛 EmptyState 테스트를 같은 단언으로 이관(A-6b 3단계).
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('아이콘·제목·본문을 렌더한다', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const AppEmptyState(
      icon: Icons.bookmark_rounded,
      title: '구독 중인 멘토가 없어요',
      description: '관심 있는 멘토를 구독해 보세요',
    )));
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(find.text('구독 중인 멘토가 없어요'), findsOneWidget);
    expect(find.text('관심 있는 멘토를 구독해 보세요'), findsOneWidget);
  });

  testWidgets('CTA는 label+콜백이 있을 때만 노출된다', (WidgetTester tester) async {
    // 콜백/라벨 없음 → 버튼 없음.
    await tester.pumpWidget(_wrap(const AppEmptyState(
      icon: Icons.receipt_long_rounded,
      title: '거래 내역이 없어요',
      description: '구독·충전 내역이 여기에 표시돼요',
    )));
    expect(find.text('멘토 찾기'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);

    // 라벨+콜백 있음 → 버튼 노출.
    await tester.pumpWidget(_wrap(AppEmptyState(
      icon: Icons.bookmark_rounded,
      title: '구독 중인 멘토가 없어요',
      description: '관심 있는 멘토를 구독해 보세요',
      actionLabel: '멘토 찾기',
      onAction: () {},
    )));
    expect(find.text('멘토 찾기'), findsOneWidget);
  });

  testWidgets('CTA 탭 시 콜백이 호출된다', (WidgetTester tester) async {
    int calls = 0;
    await tester.pumpWidget(_wrap(AppEmptyState(
      icon: Icons.bookmark_rounded,
      title: '구독 중인 멘토가 없어요',
      description: '관심 있는 멘토를 구독해 보세요',
      actionLabel: '멘토 찾기',
      onAction: () => calls++,
    )));
    await tester.tap(find.text('멘토 찾기'));
    await tester.pump();
    expect(calls, 1);
  });
}
