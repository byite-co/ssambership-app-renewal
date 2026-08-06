import 'package:flutter_test/flutter_test.dart';

import '../../tool/validate_release_env.dart';

/// §16 release preflight — 출시 빌드 환경 판정(secret 미출력 계약 포함).
///
/// fixture 값은 실제 운영 값을 닮지 않은 순수 테스트 문자열이다.
Map<String, String> _base() => <String, String>{
      'SENTRY_DSN': 'test-fixture-dsn-not-real',
      'SENTRY_ENVIRONMENT': 'production',
      'SUPABASE_URL': 'https://example-project.supabase.co',
      'SUPABASE_ANON_KEY': 'test-fixture-key-not-real',
    };

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

  test('14e. 로컬 Supabase URL(127.0.0.1/localhost/http) → FAIL', () {
    for (final String bad in <String>[
      'http://127.0.0.1:54321',
      'http://localhost:54321',
      'https://192.168.0.10:54321',
      '',
    ]) {
      final Map<String, String> env = _base()..['SUPABASE_URL'] = bad;
      expect(validateReleaseEnv(env).supabaseUrlIsRemoteHttps, isFalse,
          reason: bad);
    }
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
      r.supabaseUrlIsRemoteHttps,
      r.anonKeyPresent,
    ], everyElement(isA<bool>()));
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
