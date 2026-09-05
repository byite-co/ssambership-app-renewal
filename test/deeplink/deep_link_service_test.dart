import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_tabs.dart';
import 'package:ssambership_app/core/deeplink/deep_link_service.dart';
import 'package:ssambership_app/core/push/push_payload.dart';

/// 배선 검증: 알림 '탭' payload 스트림 → DeepLinkService → TabNavigator.go.
///
/// App-F0 이후 프로덕션에는 payload 생산자가 없다(OS 푸시 미도입). 그래서
/// 이 테스트는 FCM 게이트웨이 대신 **스트림을 직접 주입**해 배선만 검증한다 —
/// 검증 대상(판정·보류·중복 제거·탭 이동)은 그대로다.
void main() {
  late StreamController<PushPayload> opened;

  PushPayload payload({
    String type = 'question_answered',
    String? roomId = 'r-1',
    String eventId = 'n-1',
  }) {
    return PushPayload.fromRemote(<String, dynamic>{
      'type': type,
      if (roomId != null) 'room_id': roomId,
      'notification_id': eventId,
    });
  }

  setUp(() {
    TabNavigator.request.value = null;
    opened = StreamController<PushPayload>.broadcast();
  });

  tearDown(() async {
    await DeepLinkService.instance.dispose();
    await opened.close();
    TabNavigator.request.value = null;
  });

  test('알림 탭 payload → TabNavigator 로 탭 전환 요청', () async {
    await DeepLinkService.instance.initialize(openedPayloads: opened.stream);
    DeepLinkService.instance.onSignedIn('u-1');

    opened.add(payload());
    await pumpEventQueue();

    expect(TabNavigator.request.value, AppTab.questionRoom);
  });

  test('콜드 스타트 최초 메시지에 해당하는 payload 도 동일하게 처리된다', () async {
    await DeepLinkService.instance.initialize(openedPayloads: opened.stream);
    DeepLinkService.instance.onSignedIn('u-1');

    opened.add(payload(
      type: 'subscription_expired',
      roomId: null,
      eventId: 'n-cold',
    ));
    await pumpEventQueue();

    expect(TabNavigator.request.value, AppTab.myPage);
  });

  test('비로그인 탭 → 보류, onSignedIn 훅에서 1회 실행', () async {
    await DeepLinkService.instance.initialize(openedPayloads: opened.stream);

    opened.add(payload());
    await pumpEventQueue();
    expect(TabNavigator.request.value, isNull); // 아직 이동 없음.

    DeepLinkService.instance.onSignedIn('u-1');
    expect(TabNavigator.request.value, AppTab.questionRoom);
  });

  test('App-F0: 생산자 미주입(프로덕션 기본) → 구독 0·이동 0, 훅은 안전', () async {
    await DeepLinkService.instance.initialize();
    DeepLinkService.instance.onSignedIn('u-1');

    // 스트림을 주입하지 않았으므로 어떤 payload 도 도달하지 않는다.
    opened.add(payload());
    await pumpEventQueue();

    expect(TabNavigator.request.value, isNull);
    DeepLinkService.instance.onSignedOut();
  });
}
