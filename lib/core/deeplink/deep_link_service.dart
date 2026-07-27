import 'dart:async';

import '../../app/app_tabs.dart';
import '../push/push_payload.dart';
import 'notification_deep_link_controller.dart';

/// 딥링크 서비스 — 알림 '탭' payload 스트림을 탭 이동으로 변환한다.
///
/// ★ 판정·중복 제거·로그인 대기는 순수 로직인 [NotificationDeepLinkController] 가
///   담당(테스트 대상). 이 클래스는 배선만: payload 스트림 → controller.handleTap
///   → TabNavigator.go.
/// ★ App-F0: OS 푸시(FCM)를 제거해 **프로덕션에는 payload 생산자가 없다** —
///   [initialize] 를 인자 없이 부르면 구독 0개로 컨트롤러만 살아 있다(로그인
///   대기·폐기 훅은 그대로 동작). 스트림 주입은 테스트 전용 경계다.
/// ★ payload 의 link/url 등 외부 경로는 파싱 단계(PushPayload)에서 이미 버려진다 —
///   어떤 URL/외부 scheme 도 실행하지 않는다.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  NotificationDeepLinkController? _controller;
  StreamSubscription<PushPayload>? _sub;

  /// 앱 시작 시 1회 초기화. [openedPayloads] 를 주지 않으면 구독하지 않는다
  /// (프로덕션 기본 — OS 푸시 미도입이라 생산자가 없다).
  Future<void> initialize({Stream<PushPayload>? openedPayloads}) async {
    if (_controller != null) return;
    _controller = NotificationDeepLinkController(navigate: TabNavigator.go);
    _sub = openedPayloads?.listen(_onOpened);
  }

  void _onOpened(PushPayload payload) {
    _controller?.handleTap(
      NotificationDeepLinkTarget(
        type: payload.type,
        roomId: payload.roomId,
        threadId: payload.threadId,
        questionId: payload.questionId,
        eventId: payload.eventId,
      ),
    );
  }

  /// 로그인 성공 훅(AuthService) — 유효한 pending 이동을 정확히 1회 실행.
  void onSignedIn(String userId) => _controller?.onSignedIn(userId);

  /// 로그아웃/계정 전환 훅(AuthService) — 이전 사용자의 pending 폐기.
  void onSignedOut() => _controller?.onSignedOut();

  /// 테스트 정리용.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _controller = null;
  }
}
