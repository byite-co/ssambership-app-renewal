import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_post_image_url_resolver.dart';
import 'package:ssambership_app/features/community/ui/widgets/board_post_card.dart';

import 'fakes.dart';

/// 게시판 목록 카드 — 첫 이미지 미리보기(웹 CommunityPostCard imageUrls[0]
/// 계약과 동등). Storage 미접촉(가짜 서명 백엔드 주입).

const String _uid = 'c04a191c-fa59-49a7-8fa4-6819e65580fb';
const String _ref1 = 'community-post-images/$_uid/1_a.png';
const String _ref2 = 'community-post-images/$_uid/2_b.jpg';

const Key _thumbKey = ValueKey<String>('board-card-thumb');

class _SignBackend implements CommunityPostImageReadBackend {
  final List<String> paths = <String>[];
  final Set<String> failPaths = <String>{};

  @override
  String? get currentUserId => 'viewer-1';

  @override
  Future<String> createSignedUrl(String objectPath, int expiresInSeconds) {
    paths.add(objectPath);
    if (failPaths.contains(objectPath)) {
      return Future<String>.error(Exception('denied'));
    }
    return Future<String>.value('https://signed.example/$objectPath?token=t');
  }
}

void main() {
  Widget wrap(Widget card) => MaterialApp(
        home: Scaffold(body: ListView(children: <Widget>[card])),
      );

  testWidgets('imageRefs 0개: 발급 0회·미리보기 영역 없음(기존 텍스트 카드 동일)',
      (WidgetTester tester) async {
    final _SignBackend backend = _SignBackend();
    final CommunityPostImageUrlResolver resolver =
        CommunityPostImageUrlResolver(backend);
    await tester.pumpWidget(wrap(BoardPostCard(
      post: sampleBoard(),
      onOpen: () {},
      imageUrlResolver: resolver,
    )));
    await tester.pumpAndSettle();

    expect(backend.paths, isEmpty); // resolver 호출 0
    expect(find.byKey(_thumbKey), findsNothing);
    expect(find.text('게시판 제목'), findsOneWidget);
    expect(find.text('익명1'), findsOneWidget);
  });

  testWidgets('imageRefs 1개: 첫 ref 서명 URL 로 미리보기 1개 표시',
      (WidgetTester tester) async {
    final _SignBackend backend = _SignBackend();
    final CommunityPostImageUrlResolver resolver =
        CommunityPostImageUrlResolver(backend);
    await tester.pumpWidget(wrap(BoardPostCard(
      post: sampleBoard(imageRefs: const <String>[_ref1]),
      onOpen: () {},
      imageUrlResolver: resolver,
    )));
    await tester.pumpAndSettle();

    expect(backend.paths, <String>['$_uid/1_a.png']);
    expect(find.byKey(_thumbKey), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(_thumbKey), matching: find.byType(Image)),
        findsOneWidget);
  });

  testWidgets('네트워크 이미지 로드 실패: 카드 전체에 전파되지 않는다(텍스트·탭 유지)',
      (WidgetTester tester) async {
    // 위젯 테스트의 기본 HTTP 클라이언트는 실제 이미지를 내려주지 않아
    // Image.network 로드가 실패한다 — errorBuilder 격리 경로가 실제로 돈다.
    final _SignBackend backend = _SignBackend();
    final CommunityPostImageUrlResolver resolver =
        CommunityPostImageUrlResolver(backend);
    int opened = 0;
    await tester.pumpWidget(wrap(BoardPostCard(
      post: sampleBoard(imageRefs: const <String>[_ref1]),
      onOpen: () => opened++,
      imageUrlResolver: resolver,
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // 카드 전체 오류 없음
    expect(find.text('게시판 제목'), findsOneWidget);
    expect(find.text('익명1'), findsOneWidget);
    await tester.tap(find.text('게시판 제목'));
    expect(opened, 1);
  });

  testWidgets('imageRefs 여러 개: 첫 ref 만 해석·미리보기 1개(나머지 미렌더)',
      (WidgetTester tester) async {
    final _SignBackend backend = _SignBackend();
    final CommunityPostImageUrlResolver resolver =
        CommunityPostImageUrlResolver(backend);
    await tester.pumpWidget(wrap(BoardPostCard(
      post: sampleBoard(imageRefs: const <String>[_ref1, _ref2]),
      onOpen: () {},
      imageUrlResolver: resolver,
    )));
    await tester.pumpAndSettle();

    expect(backend.paths, <String>['$_uid/1_a.png']); // 두 번째 ref 발급 0
    expect(find.byKey(_thumbKey), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('서명 실패: 중립 영역만 — 제목·작성자·통계·탭 동작 유지, raw ref 비노출',
      (WidgetTester tester) async {
    final _SignBackend backend = _SignBackend()..failPaths.add('$_uid/1_a.png');
    final CommunityPostImageUrlResolver resolver =
        CommunityPostImageUrlResolver(backend);
    int opened = 0;
    await tester.pumpWidget(wrap(BoardPostCard(
      post: sampleBoard(imageRefs: const <String>[_ref1]),
      onOpen: () => opened++,
      imageUrlResolver: resolver,
    )));
    await tester.pumpAndSettle();

    // 카드 텍스트 전부 유지.
    expect(find.text('게시판 제목'), findsOneWidget);
    expect(find.text('익명1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // likeCount
    expect(find.text('7'), findsOneWidget); // commentCount
    // 실패 장은 Image 없이 중립 영역.
    expect(
        find.descendant(
            of: find.byKey(_thumbKey), matching: find.byType(Image)),
        findsNothing);
    // 원문 ref·UID·경로는 텍스트·semantics 어디에도 없다.
    expect(find.textContaining('community-post-images'), findsNothing);
    expect(find.textContaining(_uid), findsNothing);
    final SemanticsHandle semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('community-post-images|$_uid')),
        findsNothing);
    semantics.dispose();
    // 탭 동작 유지.
    await tester.tap(find.text('게시판 제목'));
    expect(opened, 1);
  });

  testWidgets('일반 rebuild: 같은 카드·같은 ref 에서 재서명 요청 없음',
      (WidgetTester tester) async {
    final _SignBackend backend = _SignBackend();
    final CommunityPostImageUrlResolver resolver =
        CommunityPostImageUrlResolver(backend);
    final BoardPost post = sampleBoard(imageRefs: const <String>[_ref1]);

    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            return ListView(children: <Widget>[
              BoardPostCard(
                  post: post, onOpen: () {}, imageUrlResolver: resolver),
            ]);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(backend.paths, hasLength(1));

    // 부모 rebuild 3회 — 같은 post·ref·resolver 면 새 resolve 를 만들지 않는다.
    for (int i = 0; i < 3; i++) {
      rebuild(() {});
      await tester.pumpAndSettle();
    }
    expect(backend.paths, hasLength(1)); // 재서명 0 (TTL 캐시 이전에 호출 자체가 0)
  });

  testWidgets('post·첫 ref 변경: 새 ref 로 재해석한다', (WidgetTester tester) async {
    final _SignBackend backend = _SignBackend();
    final CommunityPostImageUrlResolver resolver =
        CommunityPostImageUrlResolver(backend);
    BoardPost post = sampleBoard(id: 'p1', imageRefs: const <String>[_ref1]);

    late StateSetter swap;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            swap = setState;
            return ListView(children: <Widget>[
              BoardPostCard(
                  post: post, onOpen: () {}, imageUrlResolver: resolver),
            ]);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(backend.paths, <String>['$_uid/1_a.png']);

    swap(() {
      post = sampleBoard(id: 'p2', imageRefs: const <String>[_ref2]);
    });
    await tester.pumpAndSettle();
    expect(backend.paths, <String>['$_uid/1_a.png', '$_uid/2_b.jpg']);
  });
}
