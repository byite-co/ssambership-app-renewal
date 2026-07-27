import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/ui/shortform/shortform_detail_screen.dart';
import 'package:ssambership_app/features/community/ui/shortform/shortform_video_port.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';
import 'package:ssambership_app/features/community/ui/widgets/thumbnail_view.dart';

import 'fakes.dart';

/// 숏폼 상세(P2-14) — 영상 재생(포트 fake 주입: 실네트워크 없음),
/// 썸네일 폴백(URL 없음/초기화 실패), dispose 해제, 좋아요·스크랩 독립 낙관 토글.
const Key _kFakePlayer = Key('fake-player');

/// 재생 포트 fake — 초기화 성공/실패를 시나리오로 지정, dispose 호출 기록.
class FakeShortformVideo implements ShortformVideoController {
  FakeShortformVideo({this.failInit = false});

  final bool failInit;
  bool initialized = false;
  bool disposed = false;
  bool playing = false;

  @override
  Future<void> initialize() async {
    if (failInit) throw Exception('init failed');
    initialized = true;
  }

  @override
  bool get isInitialized => initialized;

  @override
  bool get isPlaying => playing;

  @override
  double get aspectRatio => 9 / 16;

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> pause() async => playing = false;

  @override
  Widget buildPlayer() =>
      const ColoredBox(key: _kFakePlayer, color: Color(0xFF000000));

  @override
  Future<void> dispose() async => disposed = true;
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ShortformDetailScreen _screen({
  ShortformPost? post,
  FakeCommunityRead? read,
  FakeCommunityWrite? write,
  ShortformVideoControllerFactory? videoFactory,
}) {
  return ShortformDetailScreen(
    post: post ?? sampleShortform(),
    read: read ?? const FakeCommunityRead(),
    write: write ?? FakeCommunityWrite(),
    videoControllerFactory: videoFactory ?? (Uri url) => FakeShortformVideo(),
  );
}

void main() {
  group('영상 재생/폴백', () {
    testWidgets('videoUrl 없음 → 팩토리 미호출 + 썸네일 폴백', (WidgetTester tester) async {
      _bigSurface(tester);
      int factoryCalls = 0;
      await tester.pumpWidget(_wrap(_screen(
        post: sampleShortform(), // videoUrl: null
        videoFactory: (Uri url) {
          factoryCalls++;
          return FakeShortformVideo();
        },
      )));
      await tester.pumpAndSettle();

      expect(factoryCalls, 0);
      expect(find.byType(ThumbnailView), findsOneWidget);
      expect(find.byKey(_kFakePlayer), findsNothing);
    });

    testWidgets('http(s) 아닌 videoUrl → 재생 시도 없이 썸네일 폴백',
        (WidgetTester tester) async {
      _bigSurface(tester);
      int factoryCalls = 0;
      await tester.pumpWidget(_wrap(_screen(
        post: sampleShortform(videoUrl: 'not a url'),
        videoFactory: (Uri url) {
          factoryCalls++;
          return FakeShortformVideo();
        },
      )));
      await tester.pumpAndSettle();

      expect(factoryCalls, 0);
      expect(find.byType(ThumbnailView), findsOneWidget);
    });

    testWidgets('유효한 videoUrl → 플레이어 렌더 + 탭으로 재생/일시정지 토글',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final FakeShortformVideo video = FakeShortformVideo();
      await tester.pumpWidget(_wrap(_screen(
        post: sampleShortform(videoUrl: 'https://cdn.example.com/v.mp4'),
        videoFactory: (Uri url) => video,
      )));
      await tester.pumpAndSettle();

      expect(video.initialized, isTrue);
      expect(find.byKey(_kFakePlayer), findsOneWidget);
      expect(find.byType(ThumbnailView), findsNothing);
      // 일시정지 상태 → 재생 어포던스 오버레이.
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);

      await tester.tap(find.byKey(_kFakePlayer));
      await tester.pumpAndSettle();
      expect(video.playing, isTrue);
      expect(find.byIcon(Icons.play_circle_fill), findsNothing);

      await tester.tap(find.byKey(_kFakePlayer));
      await tester.pumpAndSettle();
      expect(video.playing, isFalse);
    });

    testWidgets('화면 dispose 시 컨트롤러 dispose 호출(자원 해제)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final FakeShortformVideo video = FakeShortformVideo();
      await tester.pumpWidget(_wrap(_screen(
        post: sampleShortform(videoUrl: 'https://cdn.example.com/v.mp4'),
        videoFactory: (Uri url) => video,
      )));
      await tester.pumpAndSettle();
      expect(video.disposed, isFalse);

      await tester.pumpWidget(_wrap(const SizedBox())); // 화면 제거
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
    });

    testWidgets('초기화 실패 → 크래시 없이 썸네일 폴백', (WidgetTester tester) async {
      _bigSurface(tester);
      final FakeShortformVideo video = FakeShortformVideo(failInit: true);
      await tester.pumpWidget(_wrap(_screen(
        post: sampleShortform(videoUrl: 'https://cdn.example.com/v.mp4'),
        videoFactory: (Uri url) => video,
      )));
      await tester.pumpAndSettle();

      expect(find.byType(ThumbnailView), findsOneWidget);
      expect(find.byKey(_kFakePlayer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('좋아요·스크랩(낙관 토글·실패 롤백·독립성)', () {
    testWidgets('좋아요 실패 → 낙관 증가가 롤백된다', (WidgetTester tester) async {
      _bigSurface(tester);
      final FakeCommunityWrite write = FakeCommunityWrite()
        ..failReactions = true;
      await tester.pumpWidget(_wrap(_screen(write: write)));
      await tester.pumpAndSettle();

      expect(find.text('좋아요 5'), findsOneWidget);
      await tester.tap(find.text('좋아요 5'));
      await tester.pump(); // 낙관 반영 프레임
      await tester.pumpAndSettle(); // 실패 → 롤백 + 스낵바

      expect(write.reactionLog, <String>['like:on']);
      expect(find.text('좋아요 5'), findsOneWidget); // 카운트 원복
    });

    testWidgets('스크랩 실패 → 낙관 상태가 롤백된다', (WidgetTester tester) async {
      _bigSurface(tester);
      final FakeCommunityWrite write = FakeCommunityWrite()
        ..failReactions = true;
      await tester.pumpWidget(_wrap(_screen(write: write)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('스크랩'));
      await tester.pumpAndSettle();

      expect(write.reactionLog, <String>['scrap:on']);
      // 실패 롤백 → 채워진 북마크 아이콘이 아닌 외곽선 아이콘.
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNothing);
    });

    testWidgets('스크랩 성공은 좋아요 실패와 독립(각자 자기 상태만)', (WidgetTester tester) async {
      _bigSurface(tester);
      final FakeCommunityWrite write = FakeCommunityWrite();
      await tester.pumpWidget(_wrap(_screen(write: write)));
      await tester.pumpAndSettle();

      // 스크랩 on(성공).
      await tester.tap(find.text('스크랩'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      // 좋아요는 실패 → 좋아요만 롤백, 스크랩 상태는 유지.
      write.failReactions = true;
      await tester.tap(find.text('좋아요 5'));
      await tester.pumpAndSettle();

      expect(find.text('좋아요 5'), findsOneWidget); // 좋아요 롤백
      expect(find.byIcon(Icons.bookmark), findsOneWidget); // 스크랩 유지
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(write.reactionLog, <String>['scrap:on', 'like:on']);
    });
  });

  testWidgets('본문(body 우선) 텍스트가 상세에 렌더된다', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(_wrap(_screen()));
    await tester.pumpAndSettle();
    expect(find.text('숏폼 설명'), findsOneWidget);
  });

  group('숏폼 댓글 경로(정본 전환 무관 — legacy 유지)', () {
    testWidgets('댓글 신고 대상은 community_comment 그대로', (WidgetTester tester) async {
      _bigSurface(tester);
      final FakeCommunityWrite write = FakeCommunityWrite();
      await tester.pumpWidget(_wrap(_screen(
        read: FakeCommunityRead(
            commentsList: <CommunityComment>[sampleComment()]),
        write: write,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('신고'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('신고 접수'));
      await tester.pumpAndSettle();

      expect(write.lastReportTargetType, 'community_comment'); // ★ 미전환
      expect(write.lastReportTargetId, 'c1');
    });

    testWidgets('댓글 등록은 shortform 타입으로 호출된다(게시판과 분리)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      ContentPolicyGate.agreedThisSession = true;
      addTearDown(() => ContentPolicyGate.agreedThisSession = false);
      final FakeCommunityWrite write = FakeCommunityWrite();
      await tester.pumpWidget(_wrap(_screen(write: write)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '숏폼 댓글');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(write.commentCalls, 1);
      expect(write.lastCommentPostType, CommunityPostType.shortform);
      expect(write.lastCommentParentId, isNull);
    });
  });
}
