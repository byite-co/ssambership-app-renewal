import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/ui/widgets/shortform_card.dart';

import 'fakes.dart';

/// App-SF1 §6 — 피드 카드 현실 반영: 웹이 thumbnail_url=null 로 저장하는
/// 현재 계약에서 거짓 썸네일 대신 중립 영상 플레이스홀더 + '상세 열기'
/// 재생 어포던스를 그린다. legacy thumbnail 행은 기존 이미지 경로 유지.
Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('thumbnailUrl=null → 중립 배경 + 재생 어포던스(+접근성 라벨)',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(
      ShortformCard(post: sampleShortform(), onOpen: () {}),
    ));
    await tester.pump();

    expect(find.byType(Image), findsNothing); // 거짓 썸네일 없음
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    // 카드 전체가 탭 노드라 하위 라벨이 카드 노드로 병합된다 — 병합된
    // 낭독문에 '숏폼 영상 열기'가 포함되는지를 검증(RegExp 부분 일치).
    expect(find.bySemanticsLabel(RegExp('숏폼 영상 열기')), findsOneWidget);
    // 재생 미지원 시절의 영화 아이콘 플레이스홀더와 겹치지 않는다.
    expect(find.byIcon(Icons.movie_outlined), findsNothing);
    semantics.dispose();
  });

  testWidgets('카드 탭(재생 아이콘 포함 영역) → 상세 이동 콜백', (WidgetTester tester) async {
    int opened = 0;
    await tester.pumpWidget(_wrap(
      ShortformCard(post: sampleShortform(), onOpen: () => opened++),
    ));
    await tester.pump();

    // 재생 아이콘 위치를 탭해도 카드 전체 탭으로 상세가 열린다(거짓 CTA 아님).
    await tester.tap(find.byIcon(Icons.play_circle_fill));
    expect(opened, 1);

    await tester.tap(find.text('숏폼 제목'));
    expect(opened, 2);
  });

  testWidgets('legacy thumbnail URL → 기존 이미지 로딩 경로 유지',
      (WidgetTester tester) async {
    const String legacyThumb = 'https://cdn.example.com/t.jpg';
    await tester.pumpWidget(_wrap(
      ShortformCard(
        post: sampleShortform(thumbnailUrl: legacyThumb),
        onOpen: () {},
      ),
    ));
    await tester.pump();

    final Image image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, legacyThumb);
    // 어포던스는 이미지 위에도 유지된다.
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });

  testWidgets('썸네일 이미지 오류 → 깨진 이미지 없이 중립 폴백·크래시 0',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      ShortformCard(
        post: sampleShortform(thumbnailUrl: 'https://cdn.example.com/x.jpg'),
        onOpen: () {},
      ),
    ));
    // 테스트 환경 HttpClient 는 400 을 돌려준다 — errorBuilder 폴백 경로.
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
