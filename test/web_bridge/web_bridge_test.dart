import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/web_bridge/web_bridge.dart';
import 'package:ssambership_app/core/web_bridge/web_bridge_config.dart';

void main() {
  group('설정 완료(baseUrl 주입): URL 조립 + 열기', () {
    late List<Uri> opened;
    WebBridge make() => WebBridge(
          baseUrl: 'https://web.test',
          launcher: (Uri u) async {
            opened.add(u);
            return true;
          },
        );

    setUp(() => opened = <Uri>[]);

    test('openBillingManage: billingManagePath + src 쿼리 반영', () async {
      final WebOpenResult r = await make().openBillingManage();
      expect(r, WebOpenResult.opened);
      expect(opened.single.origin, 'https://web.test');
      expect(opened.single.path, WebBridgeConfig.billingManagePath);
      expect(opened.single.queryParameters['src'], 'app');
    });

    test('buildUri: 추가 쿼리는 기존 쿼리와 병합된다', () {
      final Uri? uri = make().buildUri(
        WebBridgeConfig.billingManagePath,
        <String, String>{'src': 'app', 'from': 'mypage'},
      );
      expect(uri, isNotNull);
      expect(uri!.queryParameters['src'], 'app');
      expect(uri.queryParameters['from'], 'mypage');
    });

    test('결제관리/정산/프로필 각 경로로 조립', () async {
      final WebBridge b = make();
      await b.openBillingManage();
      await b.openPayoutManage();
      await b.openProfileEdit();
      expect(opened.map((Uri e) => e.path).toList(), <String>[
        WebBridgeConfig.billingManagePath,
        WebBridgeConfig.payoutManagePath,
        WebBridgeConfig.profileEditPath,
      ]);
    });

    test('openAccountDelete: accountDeletePath 로 조립', () async {
      final WebOpenResult r = await make().openAccountDelete();
      expect(r, WebOpenResult.opened);
      expect(opened.single.path, WebBridgeConfig.accountDeletePath);
      expect(opened.single.path, '/account/delete');
    });

    test('열기 실패 → failed', () async {
      final WebOpenResult r = await WebBridge(
        baseUrl: 'https://web.test',
        launcher: (Uri u) async => false,
      ).openBillingManage();
      expect(r, WebOpenResult.failed);
    });
  });

  group('P3-7 URL 하드닝: https + 허용 호스트만 연다', () {
    // 운영 base 기준(기본값과 동일 도메인)으로 검증 규칙을 전수 확인한다.
    final WebBridge bridge = WebBridge(
      baseUrl: 'https://ssambership.com',
      launcher: (Uri u) async => true,
    );

    test('https 강제: http 는 차단', () {
      expect(bridge.isAllowedUri(Uri.parse('http://ssambership.com/support')),
          isFalse);
      expect(bridge.isAllowedUri(Uri.parse('https://ssambership.com/support')),
          isTrue);
    });

    test('정확히 같은 호스트 통과', () {
      expect(
          bridge.isAllowedUri(Uri.parse('https://ssambership.com/legal/terms')),
          isTrue);
    });

    test('승인 서브도메인(.ssambership.com) 통과', () {
      expect(bridge.isAllowedUri(Uri.parse('https://www.ssambership.com/x')),
          isTrue);
      expect(bridge.isAllowedUri(Uri.parse('https://app.ssambership.com/x')),
          isTrue);
    });

    test('접미 위장(evilssambership.com) 차단 — 점 없는 접미사는 서브도메인 아님', () {
      expect(bridge.isAllowedUri(Uri.parse('https://evilssambership.com/x')),
          isFalse);
    });

    test('접두 위장(ssambership.com.evil.com) 차단', () {
      expect(
          bridge.isAllowedUri(Uri.parse('https://ssambership.com.evil.com/x')),
          isFalse);
    });

    test('임의 외부 URL 차단', () {
      expect(
          bridge.isAllowedUri(Uri.parse('https://example.com/phish')), isFalse);
      expect(bridge.isAllowedUri(Uri.parse('javascript:alert(1)')), isFalse);
    });

    test('http base 주입이면 열지 않고 failed(launcher 미호출)', () async {
      bool called = false;
      final WebBridge b = WebBridge(
        baseUrl: 'http://ssambership.com',
        launcher: (Uri u) async {
          called = true;
          return true;
        },
      );
      expect(await b.openSupport(), WebOpenResult.failed);
      expect(called, isFalse); // 검증 탈락 URL 은 절대 열지 않는다.
    });

    test('경로 주입으로 호스트가 바뀌는 URL(@ 트릭)도 열지 않는다', () async {
      bool called = false;
      final WebBridge b = WebBridge(
        baseUrl: 'https://ssambership.com',
        launcher: (Uri u) async {
          called = true;
          return true;
        },
      );
      // buildUri 는 '$base$path' 조립이므로 path 가 '@evil.com/x' 면 호스트가 바뀐다.
      final Uri? evil = b.buildUri('@evil.com/x');
      expect(evil, isNotNull);
      expect(b.isAllowedUri(evil!), isFalse); // 조립 결과라도 검증에서 탈락
      expect(called, isFalse);
    });

    test('오버라이드 base(스테이징 등)에서도 동일 규칙: 자기 호스트·서브도메인만', () async {
      // WEB_BASE_URL 오버라이드는 컴파일타임 상수라 여기선 생성자 주입으로 동등 검증.
      final List<Uri> opened = <Uri>[];
      final WebBridge staging = WebBridge(
        baseUrl: 'https://staging.example.com',
        launcher: (Uri u) async {
          opened.add(u);
          return true;
        },
      );
      expect(await staging.openSupport(), WebOpenResult.opened);
      expect(opened.single.host, 'staging.example.com');
      expect(
          staging.isAllowedUri(Uri.parse('https://sub.staging.example.com/x')),
          isTrue);
      expect(staging.isAllowedUri(Uri.parse('https://ssambership.com/x')),
          isFalse); // 오버라이드 중엔 운영 도메인도 '다른 호스트'
    });

    test('기본 설정값은 운영 도메인(https) — 오버라이드 빌드는 제외', () {
      // WEB_BASE_URL 미주입 빌드(테스트 기본)에서만 기본값을 고정 검증한다.
      const bool overridden = bool.hasEnvironment('WEB_BASE_URL');
      if (overridden) return;
      expect(WebBridgeConfig.baseUrl, 'https://ssambership.com');
    });
  });

  group('미확정(baseUrl 비었음): 열지 않고 안내 폴백', () {
    test('launcher 미호출 + notConfigured + buildUri null', () async {
      bool called = false;
      final WebBridge b = WebBridge(
        baseUrl: '',
        launcher: (Uri u) async {
          called = true;
          return true;
        },
      );
      expect(await b.openBillingManage(), WebOpenResult.notConfigured);
      expect(await b.openPayoutManage(), WebOpenResult.notConfigured);
      expect(called, false); // 가짜 URL 을 만들지도, 열지도 않는다.
      expect(b.buildUri(WebBridgeConfig.billingManagePath), isNull);
    });

    test('기본 WebBridge() 는 WebBridgeConfig 설정값을 그대로 반영', () {
      // 운영 도메인 확정(2026-07): 기본 빌드는 설정됨 → URL 조립 가능.
      // baseUrl 은 --dart-define=WEB_BASE_URL 로 주입 가능하므로, 빈 값 주입
      // 빌드에서는 '미설정 반영'만 검증한다(주입 겸용 — 어느 모드든 녹색).
      expect(WebBridge().isConfigured, WebBridgeConfig.isConfigured);
      if (!WebBridgeConfig.isConfigured) return; // 빈 값 주입 모드: 여기까지.
      final Uri? uri = WebBridge().buildUri(WebBridgeConfig.billingManagePath);
      expect(uri, isNotNull);
      expect(uri!.origin, WebBridgeConfig.baseUrl);
      expect(uri.path, WebBridgeConfig.billingManagePath);
    });
  });
}
