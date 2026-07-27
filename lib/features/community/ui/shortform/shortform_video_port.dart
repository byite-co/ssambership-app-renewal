import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 숏폼 영상 재생 포트 — 위젯 테스트가 fake 를 주입해 실제 네트워크 재생을
/// 피한다(PdfRasterizerPort 와 같은 '포트 + 실구현' 규약).
abstract class ShortformVideoController {
  /// 네트워크 소스 준비. 실패 시 throw — 호출부는 썸네일로 폴백한다(크래시 금지).
  Future<void> initialize();

  bool get isInitialized;
  bool get isPlaying;

  /// 실제 영상 비율(w/h). 초기화 전엔 의미 없음 — 초기화 후에만 읽는다.
  double get aspectRatio;

  Future<void> play();
  Future<void> pause();

  /// 재생 영역 위젯(초기화 이후에만 사용).
  Widget buildPlayer();

  /// 자원 해제 — 화면 dispose 에서 반드시 호출(호출부 책임).
  Future<void> dispose();
}

/// 컨트롤러 팩토리 — 상세 화면에 주입한다(기본: [createShortformVideoController]).
typedef ShortformVideoControllerFactory = ShortformVideoController Function(
    Uri url);

/// 기본 팩토리 — video_player 플러그인 실구현.
ShortformVideoController createShortformVideoController(Uri url) =>
    _VideoPlayerShortformController(url);

class _VideoPlayerShortformController implements ShortformVideoController {
  _VideoPlayerShortformController(Uri url)
      : _controller = VideoPlayerController.networkUrl(url);

  final VideoPlayerController _controller;

  @override
  Future<void> initialize() async {
    await _controller.initialize();
    await _controller.setLooping(true); // 숏폼 관례: 끝나면 반복
  }

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  double get aspectRatio => _controller.value.aspectRatio;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Widget buildPlayer() => VideoPlayer(_controller);

  @override
  Future<void> dispose() => _controller.dispose();
}
