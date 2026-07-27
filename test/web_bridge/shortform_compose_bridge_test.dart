import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/web_bridge/shortform_compose_bridge.dart';

void main() {
  final ShortformComposeBridge bridge =
      ShortformComposeBridge(baseUrl: 'https://ssambership.com');

  group('bootstrap POST 본문 — Android form-urlencoded 계약', () {
    test('본문은 percent-encode 된 form-urlencoded, target=shortform_create 고정',
        () {
      final String body = utf8.decode(ShortformComposeBridge.buildBootstrapBody(
        accessToken: 'a.b+c/d=e&f',
        refreshToken: 'r t?&=',
      ));
      final Map<String, String> parsed = Uri.splitQueryString(body);
      expect(parsed['access_token'], 'a.b+c/d=e&f'); // 왕복 보존 = 인코딩 정상
      expect(parsed['refresh_token'], 'r t?&=');
      expect(parsed['target'], 'shortform_create');
      // 원문에 비인코딩 구분자 침범 없음(필드 3개 유지).
      expect(parsed.length, 3);
    });

    test('토큰은 URL 에 싣지 않는다 — bootstrap URI 는 query/fragment 없음', () {
      expect(bridge.bootstrapUri.toString(),
          'https://ssambership.com/api/app-session/bootstrap');
      expect(bridge.bootstrapUri.hasQuery, isFalse);
      expect(bridge.bootstrapUri.hasFragment, isFalse);
    });
  });

  group('탐색 allowlist — exact host + 허용 경로만', () {
    test('허용: bootstrap·작성 표면·완료/오류 브릿지(https, 동일 host)', () {
      for (final String u in <String>[
        'https://ssambership.com/api/app-session/bootstrap',
        'https://ssambership.com/app/community/shortform/new',
        'https://ssambership.com/app/community/shortform/new?error=video',
        'https://ssambership.com/app/bridge/complete?kind=shortform&result=draft',
        'https://ssambership.com/app/bridge/error?code=mentor_only',
      ]) {
        expect(bridge.isAllowedNavigation(Uri.parse(u)), isTrue, reason: u);
      }
    });

    test('차단: 타 호스트·evil suffix·서브도메인', () {
      for (final String u in <String>[
        'https://evil.com/app/community/shortform/new',
        'https://ssambership.com.evil.com/app/community/shortform/new',
        'https://evilssambership.com/app/community/shortform/new',
        'https://www.ssambership.com/app/community/shortform/new', // exact host 원칙
      ]) {
        expect(bridge.isAllowedNavigation(Uri.parse(u)), isFalse, reason: u);
      }
    });

    test('차단: 비 https 스킴(javascript:/file:/data:/intent:/http:)', () {
      for (final String u in <String>[
        'javascript:alert(1)',
        'file:///etc/passwd',
        'data:text/html,<h1>x</h1>',
        'intent://scan/#Intent;scheme=zxing;end',
        'http://ssambership.com/app/community/shortform/new',
      ]) {
        expect(bridge.isAllowedNavigation(Uri.parse(u)), isFalse, reason: u);
      }
    });

    test('차단: 결제·구독·충전·기타 웹 경로(동일 host 여도)', () {
      for (final String u in <String>[
        'https://ssambership.com/subscribe',
        'https://ssambership.com/wallet/charge',
        'https://ssambership.com/wallet/ledger',
        'https://ssambership.com/community/shortform', // 웹 피드(작성 표면 아님)
        'https://ssambership.com/',
        'https://ssambership.com/mypage',
      ]) {
        expect(bridge.isAllowedNavigation(Uri.parse(u)), isFalse, reason: u);
      }
    });
  });

  group('완료 브릿지 판정 — kind/result enum 고정', () {
    test('draft/published 만 결과로 인정', () {
      expect(
        bridge.completionOf(Uri.parse(
            'https://ssambership.com/app/bridge/complete?kind=shortform&result=draft')),
        ShortformComposeResult.draft,
      );
      expect(
        bridge.completionOf(Uri.parse(
            'https://ssambership.com/app/bridge/complete?kind=shortform&result=published')),
        ShortformComposeResult.published,
      );
    });

    test('미지 kind/result·타 호스트는 완료로 인정하지 않음', () {
      for (final String u in <String>[
        'https://ssambership.com/app/bridge/complete?kind=shortform&result=cancel',
        'https://ssambership.com/app/bridge/complete?kind=payment&result=draft',
        'https://ssambership.com/app/bridge/complete',
        'https://evil.com/app/bridge/complete?kind=shortform&result=draft',
        'http://ssambership.com/app/bridge/complete?kind=shortform&result=draft',
      ]) {
        expect(bridge.completionOf(Uri.parse(u)), isNull, reason: u);
      }
    });
  });
}
