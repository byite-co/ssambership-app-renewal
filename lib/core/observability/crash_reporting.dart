import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 크래시 리포팅(G3) — Sentry. Firebase-free 정책 유지.
///
/// DSN 은 .env 의 SENTRY_DSN 에서 읽는다. 비어 있으면 SDK 를 아예 기동하지
/// 않고 앱만 그대로 켠다(개발·CI 기본값). DSN 이 있으면 SentryFlutter.init
/// 이 전역 핸들러(FlutterError.onError, PlatformDispatcher.onError)를 걸어
/// 미처리 예외·네이티브 크래시를 수집한다.
///
/// ## fail-open 부팅 계약 (리뷰 후속)
/// Sentry 는 관측 도구다 — 관측 도구의 실패가 앱 부팅을 막으면 안 된다.
/// - init 이 appRunner 호출 **전에** 실패 → fallback 으로 appRunner 를 1회
///   실행한다(앱 정상 부팅).
/// - init 이 appRunner 실행 **후에** 실패 → 앱은 이미 떠 있다. bootstrap 을
///   재실행하지 않는다(runApp 중복 0).
/// - **appRunner 자체가** 던진 오류는 init 실패로 오인하지 않는다 — 원본
///   오류·스택을 그대로 rethrow 한다(삼킴 금지). Sentry 가 정상 기동했다면
///   전역 핸들러 경로에서 그 오류를 수집할 수 있다.
/// - appRunner 는 어떤 경로로든 **정확히 1회**만 실행된다(once-only guard —
///   중복/동시 호출은 no-op).
typedef CrashReportingInitializer = Future<void> Function(
  FutureOr<void> Function(SentryFlutterOptions) configure, {
  Future<void> Function()? appRunner,
});

Future<void> bootstrapCrashReporting({
  required Future<void> Function() appRunner,
  CrashReportingInitializer? initializerOverride,
  String? dsnOverride,
  String? environmentOverride,
}) async {
  final String? dsn = crashReportingDsn(dsnOverride ?? _maybeEnv('SENTRY_DSN'));
  final String environment = crashReportingEnvironment(
      environmentOverride ?? _maybeEnv('SENTRY_ENVIRONMENT'));

  // once-only guard — 어떤 경로(초기 init·fallback·중복 호출)로도 1회.
  bool runnerStarted = false;
  Object? runnerError;
  StackTrace? runnerStack;
  Future<void> guardedRunner() async {
    if (runnerStarted) return;
    runnerStarted = true;
    try {
      await appRunner();
    } catch (e, st) {
      // appRunner 오류를 별도 기록 — init 실패와 구분하기 위한 표식.
      runnerError = e;
      runnerStack = st;
      rethrow;
    }
  }

  if (dsn == null) {
    // DSN 없음(개발·CI) — Sentry init 0회, 부팅 1회.
    await guardedRunner();
    return;
  }

  final CrashReportingInitializer init =
      initializerOverride ?? SentryFlutter.init;
  try {
    await init(
      (SentryFlutterOptions options) => applyCrashReportingOptions(options,
          dsn: dsn, environment: environment),
      appRunner: guardedRunner,
    );
  } catch (e) {
    if (runnerError != null) {
      // E: 오류의 출처는 appRunner — init 실패로 오인해 재실행하지 않고
      //    원본 오류·스택을 보존해 그대로 전파한다.
      Error.throwWithStackTrace(runnerError!, runnerStack!);
    }
    if (!runnerStarted) {
      // C: init 이 runner 를 부르기 전에 죽었다 — fail-open fallback 1회.
      await guardedRunner();
      return;
    }
    // D: runner 는 이미 정상 실행됐고 init 의 후처리만 실패 — 앱은 떠 있다.
    //    재실행·중복 runApp 금지. 관측만 잃는다(fail-open, 오류는 로그 성격
    //    이므로 여기서 전파하면 살아 있는 앱을 죽인다).
  }
}

/// Sentry 옵션 정본 — 테스트가 이 함수를 직접 검증한다.
///
/// - PII 미전송(sendDefaultPii=false 명시).
/// - 성능 추적 완전 비활성: tracesSampleRate=null ∧ tracesSampler=null 이
///   SDK 계약상 tracing off 다(0 이 아니라 null — 트랜잭션 생성 자체가 없다).
///   프로파일링(profilesSampleRate=null)은 tracing off 에서 동작하지 않으며
///   명시적으로 null 로 둔다.
/// - release/dist 는 설정하지 않는다 — SDK 의 LoadReleaseIntegration 이
///   PackageInfo 로 `<packageName>@<version>+<buildNumber>` / dist=buildNumber
///   를 자동 구성한다(Android com.ssambership.edu@1.0.0+19 / dist=19 형식).
///   수동 override·버전 하드코딩 금지. PackageInfo 조회 실패는 SDK 가 내부
///   로그로 삼켜 부팅에 영향 없다(설치 SDK 소스 확인).
void applyCrashReportingOptions(
  SentryFlutterOptions options, {
  required String dsn,
  required String environment,
}) {
  options.dsn = dsn;
  options.environment = environment;
  options.sendDefaultPii = false;
  options.tracesSampleRate = null;
  options.tracesSampler = null;
  // tracing off(위 두 null)에서는 프로파일링이 구동될 수 없지만, 계약을
  // 명시하기 위해 실험 API 도 null 로 고정한다.
  // ignore: experimental_member_use
  options.profilesSampleRate = null;
}

/// DSN 정규화 — null/공백이면 null(리포팅 비활성). 값 판정만 하는 순수 함수.
String? crashReportingDsn(String? raw) {
  final String v = raw?.trim() ?? '';
  return v.isEmpty ? null : v;
}

/// 환경 라벨 — 미지정/공백이면 staging(**production 이 아닌 안전 기본값**).
/// 빈 값을 production 으로 해석하지 않는다. 스토어 제출 빌드의
/// SENTRY_ENVIRONMENT=production 강제는 release preflight
/// (tool/validate_release_env.dart)가 담당한다.
String crashReportingEnvironment(String? raw) {
  final String v = raw?.trim() ?? '';
  return v.isEmpty ? 'staging' : v;
}

/// dotenv 미로드(순수 단위테스트 등)에서도 안전하게 읽는다.
String? _maybeEnv(String key) {
  try {
    return dotenv.maybeGet(key);
  } catch (_) {
    return null;
  }
}
