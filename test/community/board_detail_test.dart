import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_post_image_url_resolver.dart';
import 'package:ssambership_app/features/community/ui/board/board_detail_screen.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';

import 'fakes.dart';

/// 게시판 상세 — 댓글·좋아요·신고 요소, 신고 시트(외부 연락처 유도 동선), 좋아요 토글 동작.
Widget _wrap(Widget child) => MaterialApp(home: child);

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

BoardDetailScreen _screen(FakeCommunityWrite write) => BoardDetailScreen(
      post: sampleBoard(),
      read: FakeCommunityRead(
        commentsList: <CommunityComment>[sampleComment()],
      ),
      write: write,
    );

void main() {
  testWidgets('상세에 본문·댓글·좋아요·신고 요소가 있다', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(_wrap(_screen(FakeCommunityWrite())));
    await tester.pumpAndSettle();

    expect(find.text('게시판 제목'), findsOneWidget); // 제목
    expect(find.text('본문 내용입니다.'), findsOneWidget); // 본문
    expect(find.textContaining('좋아요'), findsOneWidget); // 좋아요 액션
    expect(find.text('좋은 글이에요.'), findsOneWidget); // 댓글
    expect(find.byTooltip('신고'), findsOneWidget); // 신고 진입
    expect(find.byType(TextField), findsOneWidget); // 댓글 입력창
  });

  testWidgets('좋아요 탭 → write.toggle 호출 + 카운트 증가', (WidgetTester tester) async {
    _bigSurface(tester);
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(_screen(write)));
    await tester.pumpAndSettle();

    expect(find.text('좋아요 3'), findsOneWidget);
    await tester.tap(find.text('좋아요 3'));
    await tester.pumpAndSettle();
    expect(write.reactionCalls, 1);
    expect(find.text('좋아요 4'), findsOneWidget); // 낙관적 증가
  });

  testWidgets('신고 → 시트에 외부 연락처 유도 동선 + 접수 시 write.report 호출',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(_screen(write)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('신고'));
    await tester.pumpAndSettle();

    expect(find.text('신고하기'), findsOneWidget);
    expect(find.text('외부 연락처 유도'), findsOneWidget); // 신고 동선 포함
    expect(find.textContaining('출처·권리'), findsOneWidget); // 출처/권리 문구

    await tester.tap(find.text('신고 접수'));
    await tester.pumpAndSettle();
    expect(write.reportCalls, 1);
    expect(write.lastReportReason, 'inappropriate'); // 기본 선택 사유
    expect(write.lastReportTargetType, 'community_post'); // 글 신고 대상 유지
  });

  testWidgets('댓글 신고 → target_type=board_comment(서버 allowlist 정본)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(_screen(write)));
    await tester.pumpAndSettle();

    // 댓글 타일의 ⋯ 메뉴 → 신고 → 시트에서 접수.
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고 접수'));
    await tester.pumpAndSettle();

    expect(write.reportCalls, 1);
    // ★ 구 'comment' 는 서버 allowlist 가 거부하던 live bug — exact 문자열 고정.
    expect(write.lastReportTargetType, 'board_comment');
    expect(write.lastReportTargetId, 'c1');
  });

  testWidgets('댓글 등록은 게시판 타입·평면(parentId 없음)으로 호출된다',
      (WidgetTester tester) async {
    _bigSurface(tester);
    // 정책 동의 다이얼로그는 별도 테스트(content_policy_gate_test)에서 검증 — 여기선 통과.
    ContentPolicyGate.agreedThisSession = true;
    addTearDown(() => ContentPolicyGate.agreedThisSession = false);
    final FakeCommunityWrite write = FakeCommunityWrite();
    await tester.pumpWidget(_wrap(_screen(write)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '새 댓글');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(write.commentCalls, 1);
    expect(write.lastCommentPostType, CommunityPostType.board);
    expect(write.lastCommentParentId, isNull); // 평면 UI — 답글 미전송
  });

  testWidgets('댓글 헤더 수는 표시 중인 댓글 리스트 길이와 일치한다', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(_wrap(_screen(FakeCommunityWrite())));
    await tester.pumpAndSettle();

    // 헤더는 리스트 길이(1) — 카드/반응바의 comment_count(서버 유지 컬럼)와 별개 표기.
    expect(find.text('댓글 1'), findsOneWidget);
  });

  group('수정 진입점 — 내 글에만 노출(역할 무관, 판정 정본은 서버)', () {
    BoardDetailScreen screenFor(FakeCommunityWrite write, BoardPost post) =>
        BoardDetailScreen(
          post: post,
          read: const FakeCommunityRead(),
          write: write,
        );

    testWidgets('내 글(학생·멘토 동일): 더보기 메뉴에 수정이 보인다',
        (WidgetTester tester) async {
      for (final String role in <String>['student', 'mentor']) {
        _bigSurface(tester);
        final FakeCommunityWrite write = FakeCommunityWrite(uid: 'me');
        await tester.pumpWidget(_wrap(screenFor(
            write, sampleBoard(authorId: 'me', authorRole: role))));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('더보기'));
        await tester.pumpAndSettle();
        expect(find.text('수정'), findsOneWidget, reason: role);

        // 수정 탭 → 수정 화면 진입(글 수정 타이틀).
        await tester.tap(find.text('수정'));
        await tester.pumpAndSettle();
        expect(find.text('글 수정'), findsOneWidget, reason: role);

        // 다음 역할 검증을 위해 수정 화면을 닫는다(재-pump 시 잔존 route 방지).
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('타인 글: 수정 항목이 아예 노출되지 않는다', (WidgetTester tester) async {
      _bigSurface(tester);
      final FakeCommunityWrite write = FakeCommunityWrite(uid: 'me');
      await tester.pumpWidget(
          _wrap(screenFor(write, sampleBoard(authorId: 'someone-else'))));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      expect(find.text('수정'), findsNothing);
      expect(find.text('이 사용자 차단'), findsOneWidget); // 기존 항목 유지
    });

    testWidgets('비로그인·author_id 미상: 수정 미노출(fail-closed)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      // 비로그인(uid null).
      await tester.pumpWidget(_wrap(screenFor(
          FakeCommunityWrite(), sampleBoard(authorId: 'me'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      expect(find.text('수정'), findsNothing);
      // 메뉴 닫기.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // author_id 를 모르는 행(구 스냅샷) — 내 글 확신 불가 → 미노출.
      await tester.pumpWidget(_wrap(
          screenFor(FakeCommunityWrite(uid: 'me'), sampleBoard())));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('더보기'));
      await tester.pumpAndSettle();
      expect(find.text('수정'), findsNothing);
    });
  });

  group('첨부 이미지 표시 — 서명 URL 경로(원문 ref 비노출)', () {
    const String uid = 'c04a191c-fa59-49a7-8fa4-6819e65580fb';
    const String ref1 = 'community-post-images/$uid/1_a.png';
    const String ref2 = 'community-post-images/$uid/2_b.jpg';

    CommunityPostImageUrlResolver resolver(_ImageReadBackend backend) =>
        CommunityPostImageUrlResolver(backend);

    Future<void> pump(
      WidgetTester tester, {
      required List<String> imageRefs,
      required _ImageReadBackend backend,
    }) async {
      _bigSurface(tester);
      await tester.pumpWidget(_wrap(BoardDetailScreen(
        post: sampleBoard(imageRefs: imageRefs),
        read: const FakeCommunityRead(),
        write: FakeCommunityWrite(),
        imageUrlResolver: resolver(backend),
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('imageRefs 순서대로 이미지가 렌더된다(여러 장)', (WidgetTester tester) async {
      final _ImageReadBackend backend = _ImageReadBackend();
      await pump(tester,
          imageRefs: const <String>[ref1, ref2], backend: backend);

      final Finder first = find.byKey(const ValueKey<String>('post-image-$ref1'));
      final Finder second =
          find.byKey(const ValueKey<String>('post-image-$ref2'));
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      // 순서 보존 — 첫 ref 가 위에 그려진다.
      expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
      // 두 장 모두 서명 URL 로 Image 위젯이 만들어졌다.
      expect(
          find.descendant(of: first, matching: find.byType(Image)), findsOneWidget);
      expect(find.descendant(of: second, matching: find.byType(Image)),
          findsOneWidget);
      // 발급은 버킷 접두사를 뗀 object path 로만 나간다.
      expect(backend.paths, <String>['$uid/1_a.png', '$uid/2_b.jpg']);
      // 원문 ref·소유자 UUID·Storage 경로는 화면 어디에도 없다.
      expect(find.textContaining('community-post-images'), findsNothing);
      expect(find.textContaining(uid), findsNothing);
      // 본문·댓글은 그대로.
      expect(find.text('본문 내용입니다.'), findsOneWidget);
    });

    testWidgets('일부 이미지 실패는 그 장의 플레이스홀더로 끝난다(본문·다른 장 유지)',
        (WidgetTester tester) async {
      final _ImageReadBackend backend = _ImageReadBackend()
        ..failPaths.add('$uid/1_a.png');
      await pump(tester,
          imageRefs: const <String>[ref1, ref2], backend: backend);

      final Finder first = find.byKey(const ValueKey<String>('post-image-$ref1'));
      final Finder second =
          find.byKey(const ValueKey<String>('post-image-$ref2'));
      // 실패 장: 중립 안내(원문 경로 없음), Image 위젯 없음.
      expect(find.descendant(of: first, matching: find.text('이미지를 불러오지 못했어요.')),
          findsOneWidget);
      expect(find.descendant(of: first, matching: find.byType(Image)),
          findsNothing);
      // 성공 장·본문·댓글은 그대로.
      expect(find.descendant(of: second, matching: find.byType(Image)),
          findsOneWidget);
      expect(find.text('본문 내용입니다.'), findsOneWidget);
      expect(find.text('좋은 글이에요.'), findsNothing); // FakeCommunityRead() 빈 댓글
      expect(find.textContaining('community-post-images'), findsNothing);
    });

    testWidgets('imageRefs 가 비면 기존 텍스트 게시글과 동일(이미지 영역 없음)',
        (WidgetTester tester) async {
      final _ImageReadBackend backend = _ImageReadBackend();
      await pump(tester, imageRefs: const <String>[], backend: backend);
      expect(find.textContaining('이미지를 불러오지 못했어요.'), findsNothing);
      expect(backend.paths, isEmpty); // 발급 시도 0
      expect(find.text('본문 내용입니다.'), findsOneWidget);
    });
  });
}

/// 서명 발급 가짜 백엔드 — 경로 기록 + 지정 경로 실패.
class _ImageReadBackend implements CommunityPostImageReadBackend {
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
