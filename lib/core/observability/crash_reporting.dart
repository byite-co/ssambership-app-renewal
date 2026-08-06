import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 크래시 리포팅(G3) — Sentry. Firebase-free 정책 유지.
///
/// DSN 은 .env 의 SENTRY_DSN 에서 읽는다. 비어 있으면 SDK 를 아예 기동하지
/// 않고 앱만 그대로 켠다(개발·CI 기본값). DSN 이 있으면 SentryFlutter.init
/// 이 전역 핸들러(FlutterError.onError, PlatformDispatcher.onError)를 걸어
/// 미처리 예외·네이티브 크래시를 수집한다.
///
/// ★ PII 최소화: sendDefaultPii 기본값(false) 유지 — 사용자 식별자·IP 를
///   이벤트에 싣지 않는다. 성능 추적(traces)도 쓰지 않는다(크래시만).
Future<void> bootstrapCrashReporting({
  required Future<void> Function() appRunner,
}) async {
  final String? dsn = crashReportingDsn(dotenv.maybeGet('SENTRY_DSN'));
  if (dsn == null) {
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (SentryFlutterOptions options) {
      options.dsn = dsn;
      options.environment =
          crashReportingEnvironment(dotenv.maybeGet('SENTRY_ENVIRONMENT'));
      options.tracesSampleRate = null; // 성능 추적 미사용 — 크래시 리포팅만.
    },
    appRunner: appRunner,
  );
}

/// DSN 정규화 — null/공백이면 null(리포팅 비활성). 값 판정만 하는 순수 함수.
String? crashReportingDsn(String? raw) {
  final String v = raw?.trim() ?? '';
  return v.isEmpty ? null : v;
}

/// 환경 라벨 — 미지정이면 staging(현 배포 대상 DB 와 동일 기본값).
String crashReportingEnvironment(String? raw) {
  final String v = raw?.trim() ?? '';
  return v.isEmpty ? 'staging' : v;
}
