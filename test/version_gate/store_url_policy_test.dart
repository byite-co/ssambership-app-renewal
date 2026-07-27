import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/version_gate/store_url_policy.dart';

/// validatedStoreUri — 앱측 스토어 URL 재검증(https + 허용 호스트 정확 일치).
/// 서버가 검증해 내려주더라도 앱이 최종 방어선이다.
void main() {
  group('통과 케이스', () {
    test('Play 스토어(https://play.google.com/...)', () {
      final Uri? uri = validatedStoreUri(
          'https://play.google.com/store/apps/details?id=co.kr.byite.ssambership');
      expect(uri, isNotNull);
      expect(uri!.host, 'play.google.com');
    });

    test('App Store(https://apps.apple.com/...)', () {
      expect(validatedStoreUri('https://apps.apple.com/kr/app/id123456789'),
          isNotNull);
    });

    test('iTunes(https://itunes.apple.com/...)', () {
      expect(validatedStoreUri('https://itunes.apple.com/kr/app/id123456789'),
          isNotNull);
    });

    test('호스트 대문자 표기도 통과(호스트는 대소문자 무관)', () {
      expect(
          validatedStoreUri('https://Play.Google.com/store/apps'), isNotNull);
    });
  });

  group('차단 케이스', () {
    test('허용 목록 밖 호스트(https://evil.com) → 열지 않는다', () {
      expect(validatedStoreUri('https://evil.com/store'), isNull);
    });

    test('http 스킴(http://play.google.com) → https 아님이므로 차단', () {
      expect(validatedStoreUri('http://play.google.com/store/apps'), isNull);
    });

    test('접미 위장(play.google.com.evil.com) → 정확 일치가 아니므로 차단', () {
      expect(validatedStoreUri('https://play.google.com.evil.com/x'), isNull);
    });

    test('서브도메인 위장(evil.play.google.com 형태의 상위 위장) → 차단', () {
      expect(validatedStoreUri('https://fake-play.google.com/x'), isNull);
    });

    test('null/빈 문자열/파싱 불가 → 차단(안내 문구로 대체)', () {
      expect(validatedStoreUri(null), isNull);
      expect(validatedStoreUri(''), isNull);
      expect(validatedStoreUri('::: not a url :::'), isNull);
    });

    test('스킴 없는 값(play.google.com/...) → 차단(https 강제)', () {
      expect(validatedStoreUri('play.google.com/store/apps'), isNull);
    });
  });
}
