// tool/validate_release_env.dart — 출시(스토어 제출) 빌드 preflight.
//
// 사용: dart run tool/validate_release_env.dart [.env 경로]
//
// .env 를 읽어 출시 필수 조건을 판정한다. **secret 원문은 절대 출력하지
// 않는다** — DSN·key 의 값·host·길이·prefix 전부 미출력, YES/NO 판정만.
//
// 통과 조건(전부 충족 시 exit 0, 아니면 exit 1):
//   SENTRY_DSN            : 비어 있지 않음
//   SENTRY_ENVIRONMENT    : 정확히 'production' (빈 값·staging 은 실패)
//   SUPABASE_URL          : 출시 정본 URL 과 '정확히' 일치 — 허용 정규화는
//                           단일 trailing slash 제거 하나뿐. 다른 project ref·
//                           명시 port(:443 포함)·userinfo·query·fragment·
//                           http·localhost/LAN 전부 실패.
//   SUPABASE_ANON_KEY     : 비어 있지 않음
//
// 런타임 기본값(staging)은 안전한 비-production 값으로 유지된다 — 이 도구는
// '출시 빌드에 한해' production 을 강제하는 별도 게이트다.
import 'dart:io';

/// 출시 Supabase 프로젝트 정본 URL. project URL 은 클라이언트 바이너리에
/// 포함되는 공개 식별자다(secret 아님) — 정확 일치 비교의 기준값.
const String kProductionSupabaseUrl =
    'https://lbeqxarxothkmzqvpudy.supabase.co';

class ReleaseEnvResult {
  const ReleaseEnvResult({
    required this.dsnPresent,
    required this.environmentIsProduction,
    required this.supabaseUrlIsExactProduction,
    required this.anonKeyPresent,
  });

  final bool dsnPresent;
  final bool environmentIsProduction;
  final bool supabaseUrlIsExactProduction;
  final bool anonKeyPresent;

  bool get ok =>
      dsnPresent &&
      environmentIsProduction &&
      supabaseUrlIsExactProduction &&
      anonKeyPresent;
}

/// KEY=VALUE 형식(.env) 파서 — 주석(#)·빈 줄 무시, 값의 따옴표 제거.
Map<String, String> parseEnvFile(String content) {
  final Map<String, String> out = <String, String>{};
  for (final String rawLine in content.split('\n')) {
    final String line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final int eq = line.indexOf('=');
    if (eq <= 0) continue;
    final String key = line.substring(0, eq).trim();
    String value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    out[key] = value;
  }
  return out;
}

/// SUPABASE_URL 정확 일치 게이트. 허용되는 정규화는 '단일 trailing slash
/// 제거' 하나뿐이며, 그 결과가 [kProductionSupabaseUrl] 과 문자열로 동일해야
/// 한다. 문자열 정확 비교이므로 다른 project ref·명시 port(:443 포함)·
/// userinfo·query·fragment·http·localhost/LAN 은 구조적으로 전부 실패한다.
bool supabaseUrlIsExactProductionUrl(String rawUrl) {
  String s = rawUrl.trim();
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  return s == kProductionSupabaseUrl;
}

/// 판정 순수 함수 — 테스트가 직접 검증한다. secret 값을 반환하지 않는다.
ReleaseEnvResult validateReleaseEnv(Map<String, String> env) {
  final String dsn = (env['SENTRY_DSN'] ?? '').trim();
  final String environment = (env['SENTRY_ENVIRONMENT'] ?? '').trim();
  final String url = (env['SUPABASE_URL'] ?? '').trim();
  final String anonKey = (env['SUPABASE_ANON_KEY'] ?? '').trim();

  return ReleaseEnvResult(
    dsnPresent: dsn.isNotEmpty,
    environmentIsProduction: environment == 'production',
    supabaseUrlIsExactProduction: supabaseUrlIsExactProductionUrl(url),
    anonKeyPresent: anonKey.isNotEmpty,
  );
}

String yn(bool v) => v ? 'YES' : 'NO';

void main(List<String> args) {
  final String path = args.isNotEmpty ? args[0] : '.env';
  final File file = File(path);
  final Map<String, String> env = file.existsSync()
      ? parseEnvFile(file.readAsStringSync())
      : <String, String>{};
  final ReleaseEnvResult r = validateReleaseEnv(env);

  stdout.writeln('SENTRY_DSN_PRESENT=${yn(r.dsnPresent)}');
  stdout.writeln(
      'SENTRY_ENVIRONMENT_IS_PRODUCTION=${yn(r.environmentIsProduction)}');
  stdout.writeln(
      'SUPABASE_URL_IS_EXACT_PRODUCTION=${yn(r.supabaseUrlIsExactProduction)}');
  stdout.writeln('SUPABASE_ANON_KEY_PRESENT=${yn(r.anonKeyPresent)}');
  stdout.writeln('RELEASE_ENV_VALIDATION=${r.ok ? 'PASS' : 'FAIL'}');
  exit(r.ok ? 0 : 1);
}
