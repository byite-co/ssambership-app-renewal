import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/shortform_media_url_resolver.dart';
import 'package:ssambership_app/features/community/ui/shortform/shortform_detail_screen.dart';
import 'package:ssambership_app/features/community/ui/shortform/shortform_video_port.dart';
import 'package:ssambership_app/features/community/ui/widgets/thumbnail_view.dart';

import 'fakes.dart';

/// App-SF1 — 숏폼 상세 미디어 배선: 정본 참조 → 실제 리졸버(fake 백엔드) →
/// 서명 URL → player 초기화 수렴, 실패/재시도/세대 폐기/dispose 계약(§5).
/// 실네트워크·실 Storage 없이 모든 상태를 재현한다.
const String _uid = '3f2b8a4e-1c5d-4e6f-8a9b-0c1d2e3f4a5b';
const String _ref =
    'shortform-videos/$_uid/e0a1b2c3-d4e5-4f60-8a9b-1c2d3e4f5a6b.mp4';
const Key _kFakePlayer = Key('fake-media-player');

/// 시나리오 스크립트형 백엔드 — 호출 순서대로 [script] 를 소비한다.
/// String → 그 URL 반환 · Exception → throw · Completer<String> → 지연 응답.
/// 스크립트가 비어 있는데 호출되면 테스트 실패(예상 밖 발급 검출).
class _ScriptBackend implements ShortformMediaBackend {
  _ScriptBackend(this.script);

  final List<Object> script;
  int calls = 0;

  @override
  String? get currentUserId => 'viewer-1';

  @override
  Future<String> createSignedUrl(String objectPath, int expiresInSeconds) {
    calls++;
    if (script.isEmpty) {
      fail('예상 밖 createSignedUrl 호출(objectPath 비노출을 위해 값 생략)');
    }
    final Object step = script.removeAt(0);
    if (step is Completer<String>) return step.future;
    if (step is String) return Future<String>.value(step);
    return Future<String>.error(step);
  }
}

/// 재생 포트 fake — 초기화 성공/실패/지연을 시나리오로 지정, dispose 기록.
class _FakeVideo implements ShortformVideoController {
  _FakeVideo({this.failInit = false, this.initGate});

  final bool failInit;
  final Completer<void>? initGate;
  bool initialized = false;
  bool disposed = false;
  bool playing = false;

  @override
  Future<void> initialize() async {
    if (initGate != null) await initGate!.future;
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

/// 컨트롤러 팩토리 기록기 — 받은 URI 와 만든 컨트롤러를 기록한다.
class _RecordingFactory {
  _RecordingFactory({this.builder});

  final _FakeVideo Function(int index)? builder;
  final List<Uri> uris = <Uri>[];
  final List<_FakeVideo> videos = <_FakeVideo>[];

  ShortformVideoController call(Uri url) {
    uris.add(url);
    final _FakeVideo v = builder?.call(videos.length) ?? _FakeVideo();
    videos.add(v);
    return v;
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ShortformDetailScreen _screen({
  required _ScriptBackend backend,
  required _RecordingFactory factory,
  String? videoUrl = _ref,
}) {
  return ShortformDetailScreen(
    post: sampleShortform(videoUrl: videoUrl),
    read: const FakeCommunityRead(),
    write: FakeCommunityWrite(),
    videoControllerFactory: factory.call,
    mediaResolver: ShortformMediaUrlResolver(backend),
  );
}

void main() {
  testWidgets('정본 참조 → 서명 해석 → player 초기화 → 표시(초기 일시정지)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final _ScriptBackend backend =
        _ScriptBackend(<Object>['https://signed.example/v.mp4?token=t1']);
    final _RecordingFactory factory = _RecordingFactory();

    await tester.pumpWidget(_wrap(_screen(backend: backend, factory: factory)));
    await tester.pumpAndSettle();

    expect(backend.calls, 1);
    // 팩토리는 raw 참조가 아니라 '해석된 절대 URL' 을 받는다.
    expect(factory.uris,
        <Uri>[Uri.parse('https://signed.example/v.mp4?token=t1')]);
    expect(find.byKey(_kFakePlayer), findsOneWidget);
    expect(find.byType(ThumbnailView), findsNothing);
    // 초기 상태는 일시정지 — 재생 어포던스 오버레이 표시.
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('서명 실패 → 실패 UI(문구+재시도)·크래시 0·원문 비노출',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final _ScriptBackend backend = _ScriptBackend(
        <Object>[Exception('http://leak.example/?token=SECRET')]);
    final _RecordingFactory factory = _RecordingFactory();

    await tester.pumpWidget(_wrap(_screen(backend: backend, factory: factory)));
    await tester.pumpAndSettle();

    expect(find.text('영상을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(factory.uris, isEmpty);
    expect(find.byKey(_kFakePlayer), findsNothing);
    // 오류 원문(서명 URL·token)이 화면 어디에도 노출되지 않는다.
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('token'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('재시도 연타 → 실제 추가 시도는 정확히 1회', (WidgetTester tester) async {
    _bigSurface(tester);
    final Completer<String> retrySign = Completer<String>();
    final _ScriptBackend backend =
        _ScriptBackend(<Object>[Exception('sign fail'), retrySign]);
    final _RecordingFactory factory = _RecordingFactory();

    await tester.pumpWidget(_wrap(_screen(backend: backend, factory: factory)));
    await tester.pumpAndSettle();
    expect(backend.calls, 1); // 최초 시도(실패)

    // 같은 프레임에서 연타 — 첫 탭이 동기적으로 resolving 전환, 둘째 탭 무시.
    await tester.tap(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'), warnIfMissed: false);
    await tester.pump();
    expect(backend.calls, 2); // 추가 시도 정확히 1회

    retrySign.complete('https://signed.example/v.mp4?token=t2');
    await tester.pumpAndSettle();
    expect(find.byKey(_kFakePlayer), findsOneWidget);
    expect(backend.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('재시도 성공 → 실패 UI 에서 player 로 수렴', (WidgetTester tester) async {
    _bigSurface(tester);
    final _ScriptBackend backend = _ScriptBackend(<Object>[
      Exception('sign fail'),
      'https://signed.example/v.mp4?token=t2',
    ]);
    final _RecordingFactory factory = _RecordingFactory();

    await tester.pumpWidget(_wrap(_screen(backend: backend, factory: factory)));
    await tester.pumpAndSettle();
    expect(find.text('영상을 불러오지 못했어요.'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.byKey(_kFakePlayer), findsOneWidget);
    expect(find.text('영상을 불러오지 못했어요.'), findsNothing);
    expect(factory.uris.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player 초기화 실패 → 실패 컨트롤러 해제 + 재시도로 회복',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final _ScriptBackend backend = _ScriptBackend(<Object>[
      'https://signed.example/v.mp4?token=t1',
      'https://signed.example/v.mp4?token=t2',
    ]);
    final _RecordingFactory factory = _RecordingFactory(
      builder: (int index) => _FakeVideo(failInit: index == 0),
    );

    await tester.pumpWidget(_wrap(_screen(backend: backend, factory: factory)));
    await tester.pumpAndSettle();

    expect(find.text('영상을 불러오지 못했어요.'), findsOneWidget);
    expect(factory.videos.first.disposed, isTrue); // 실패 컨트롤러 즉시 해제
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.byKey(_kFakePlayer), findsOneWidget);
    expect(factory.videos.length, 2);
    expect(backend.calls, 2);
  });

  testWidgets('늦은 이전 응답이 최신 재시도 결과를 덮지 않음(viewLoadGeneration)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final Completer<String> firstSign = Completer<String>();
    final Completer<String> secondSign = Completer<String>();
    final _ScriptBackend backend =
        _ScriptBackend(<Object>[firstSign, secondSign]);
    final _RecordingFactory factory = _RecordingFactory();

    await tester.pumpWidget(_wrap(_screen(backend: backend, factory: factory)));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('sf-media-resolving')),
        findsOneWidget);

    // 프로그램적 재로드(retryMedia) — 세대 전진(1차 응답은 폐기 대상이 된다).
    final ShortformDetailScreenState state = tester
        .state<ShortformDetailScreenState>(find.byType(ShortformDetailScreen));
    unawaited(state.retryMedia());
    await tester.pump();
    expect(backend.calls, 2);

    // 최신(2차) 응답 먼저 도착 → player 수렴.
    secondSign.complete('https://signed.example/v.mp4?token=new');
    await tester.pumpAndSettle();
    expect(factory.uris,
        <Uri>[Uri.parse('https://signed.example/v.mp4?token=new')]);
    expect(find.byKey(_kFakePlayer), findsOneWidget);

    // 이전(1차) 응답이 '이후' 도착 — 화면 상태·컨트롤러에 반영 0.
    firstSign.complete('https://signed.example/v.mp4?token=old');
    await tester.pumpAndSettle();
    expect(factory.uris.length, 1); // 늦은 응답으로 컨트롤러를 만들지 않는다
    expect(find.byKey(_kFakePlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('해석 중 dispose → 늦은 응답의 팩토리 호출·상태 반영 0',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final Completer<String> sign = Completer<String>();
    final _ScriptBackend backend = _ScriptBackend(<Object>[sign]);
    final _RecordingFactory factory = _RecordingFactory();

    await tester.pumpWidget(_wrap(_screen(backend: backend, factory: factory)));
    await tester.pump();

    await tester.pumpWidget(_wrap(const SizedBox())); // 화면 제거(dispose)
    sign.complete('https://signed.example/v.mp4?token=late');
    await tester.pumpAndSettle();

    expect(factory.uris, isEmpty); // dispose 후 컨트롤러 생성 없음
    expect(tester.takeException(), isNull);
  });

  testWidgets('초기화 중 dispose → 컨트롤러 dispose·늦은 상태 반영 0',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final Completer<void> initGate = Completer<void>();
    final _ScriptBackend backend =
        _ScriptBackend(<Object>['https://signed.example/v.mp4?token=t1']);
    final _RecordingFactory factory = _RecordingFactory(
      builder: (int index) => _FakeVideo(initGate: initGate),
    );

    await tester.pumpWidget(_wrap(_screen(backend: backend, factory: factory)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('sf-media-initializing')),
        findsOneWidget);
    expect(factory.videos.single.disposed, isFalse);

    await tester.pumpWidget(_wrap(const SizedBox())); // 화면 제거(dispose)
    expect(factory.videos.single.disposed, isTrue); // 자원 해제 보장

    initGate.complete(); // 늦은 초기화 완료 — 상태 반영 없어야 한다
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy 절대 URL → signer 0회로 기존 재생 회귀 없음',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final _ScriptBackend backend = _ScriptBackend(<Object>[]); // 호출 시 실패
    final _RecordingFactory factory = _RecordingFactory();
    const String legacy = 'https://cdn.example.com/v.mp4';

    await tester.pumpWidget(
        _wrap(_screen(backend: backend, factory: factory, videoUrl: legacy)));
    await tester.pumpAndSettle();

    expect(backend.calls, 0);
    expect(factory.uris, <Uri>[Uri.parse(legacy)]);
    expect(find.byKey(_kFakePlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalidReference → 실패 문구 + 재시도 버튼 미노출·signer 0회',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final _ScriptBackend backend = _ScriptBackend(<Object>[]);
    final _RecordingFactory factory = _RecordingFactory();

    await tester.pumpWidget(_wrap(_screen(
      backend: backend,
      factory: factory,
      videoUrl: 'shortform-thumbnails/$_uid/a.jpg', // 다른 bucket = 참조 손상
    )));
    await tester.pumpAndSettle();

    expect(find.text('영상을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing); // 재시도해도 결과 동일 → 미노출
    expect(backend.calls, 0);
    expect(factory.uris, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('noMedia(videoUrl null) → 준비 안내·재시도 없음·발급 0회',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final _ScriptBackend backend = _ScriptBackend(<Object>[]);
    final _RecordingFactory factory = _RecordingFactory();

    await tester.pumpWidget(
        _wrap(_screen(backend: backend, factory: factory, videoUrl: null)));
    await tester.pumpAndSettle();

    expect(find.text('영상이 준비되지 않았어요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
    expect(backend.calls, 0);
    expect(factory.uris, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
