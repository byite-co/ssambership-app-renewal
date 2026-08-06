import 'package:flutter_test/flutter_test.dart';

import '../../tool/validate_release_env.dart';

/// §16 release preflight — 출시 빌드 환경 판정(secret 미출력 계약 포함).
///
/// SUPABASE_URL 은 출시 정본 URL(공개 식별자, secret 아님)과의 '정확 일치'
/// 게이트다 — 허용 정규화는 단일 trailing slash 제거 하나뿐. DSN·key
/// fixture 는 실제 운영 값을 닮지 않은 순수 테스트 문자열이다.
Map<String, String> _base() => <String, String>{
      'SENTRY_DSN': 'test-fixture-dsn-not-real',
      'SENTRY_ENVIRONMENT': 'production',
      'SUPABASE_URL': kProductionSupabaseUrl,
      'SUPABASE_ANON_KEY': 'test-fixture-key-not-real',
    };

bool _urlOk(String url) => validateReleaseEnv(_base()..['SUPABASE_URL'] = url)
    .supabaseUrlIsExactProduction;

void main() {
  test('14a. DSN 없음 → FAIL', () {
    final Map<String, String> env = _base()..['SENTRY_DSN'] = '';
    expect(validateReleaseEnv(env).ok, isFalse);
    expect(validateReleaseEnv(env).dsnPresent, isFalse);
  });

  test('14b. environment 없음 → FAIL', () {
    final Map<String, String> env = _base()..remove('SENTRY_ENVIRONMENT');
    expect(validateReleaseEnv(env).environmentIsProduction, isFalse);
    expect(validateReleaseEnv(env).ok, isFalse);
  });

  test('14c. environment=staging → FAIL(출시 빌드는 production 강제)', () {
    final Map<String, String> env = _base()..['SENTRY_ENVIRONMENT'] = 'staging';
    expect(validateReleaseEnv(env).ok, isFalse);
  });

  test('14d. 전부 충족(production) → PASS', () {
    expect(validateReleaseEnv(_base()).ok, isTrue);
  });

  test('14f. anon key 없음 → FAIL', () {
    final Map<String, String> env = _base()..['SUPABASE_ANON_KEY'] = '';
    expect(validateReleaseEnv(env).ok, isFalse);
  });

  test('14g. 판정 결과에 secret 원문이 없다(bool 필드만)', () {
    final ReleaseEnvResult r = validateReleaseEnv(_base());
    // 결과 타입은 4개 bool + ok 뿐 — 값·host·길이 어떤 것도 노출하지 않는다.
    expect(r.ok, isTrue);
    expect(<Object>[
      r.dsnPresent,
      r.environmentIsProduction,
      r.supabaseUrlIsExactProduction,
      r.anonKeyPresent,
    ], everyElement(isA<bool>()));
  });

  group('SUPABASE_URL 정확 일치 게이트(7종)', () {
    test('1. 출시 정본 URL 정확 일치 → PASS', () {
      expect(_urlOk('https://lbeqxarxothkmzqvpudy.supabase.co'), isTrue);
    });

    test('2. 단일 trailing slash → PASS(허용되는 유일한 정규화)', () {
      expect(_urlOk('https://lbeqxarxothkmzqvpudy.supabase.co/'), isTrue);
      // 이중 slash 는 정규화 대상이 아니다 — FAIL.
      expect(_urlOk('https://lbeqxarxothkmzqvpudy.supabase.co//'), isFalse);
    });

    test('3. 다른 Supabase 프로젝트(HTTPS 라도) → FAIL', () {
      expect(_urlOk('https://example-project.supabase.co'), isFalse);
      expect(_urlOk('https://aaaaaaaaaaaaaaaaaaaa.supabase.co'), isFalse);
    });

    test('4. localhost → FAIL', () {
      expect(_urlOk('http://localhost:54321'), isFalse);
      expect(_urlOk('https://localhost'), isFalse);
      expect(_urlOk('http://127.0.0.1:54321'), isFalse);
    });

    test('5. LAN 주소 → FAIL', () {
      expect(_urlOk('https://192.168.0.10:54321'), isFalse);
      expect(_urlOk('http://10.0.2.2:54321'), isFalse);
    });

    test('6. production host 라도 http → FAIL', () {
      expect(_urlOk('http://lbeqxarxothkmzqvpudy.supabase.co'), isFalse);
    });

    test('7. userinfo·query·fragment·명시 port → FAIL', () {
      expect(_urlOk('https://user@lbeqxarxothkmzqvpudy.supabase.co'), isFalse);
      expect(_urlOk('https://lbeqxarxothkmzqvpudy.supabase.co?x=1'), isFalse);
      expect(_urlOk('https://lbeqxarxothkmzqvpudy.supabase.co#frag'), isFalse);
      expect(_urlOk('https://lbeqxarxothkmzqvpudy.supabase.co:443'), isFalse);
      expect(_urlOk(''), isFalse);
    });
  });

  test('env 파서 — 주석·빈 줄·따옴표 처리', () {
    final Map<String, String> env = parseEnvFile('''
# comment
SENTRY_DSN="quoted-value"

SENTRY_ENVIRONMENT=production
BROKEN_LINE_NO_EQ
''');
    expect(env['SENTRY_DSN'], 'quoted-value');
    expect(env['SENTRY_ENVIRONMENT'], 'production');
    expect(env.containsKey('BROKEN_LINE_NO_EQ'), isFalse);
  });
}
