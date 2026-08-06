import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/observability/crash_reporting.dart';

/// G3: 크래시 리포팅 설정 판정 — DSN 없으면 비활성, 환경 기본 staging.
void main() {
  test('DSN null/공백 → null(리포팅 비활성)', () {
    expect(crashReportingDsn(null), isNull);
    expect(crashReportingDsn(''), isNull);
    expect(crashReportingDsn('   '), isNull);
  });

  test('DSN 값이 있으면 trim 해 반환', () {
    expect(crashReportingDsn(' https://k@o.ingest.sentry.io/1 '),
        'https://k@o.ingest.sentry.io/1');
  });

  test('환경 라벨 — 미지정이면 staging, 지정 시 그대로', () {
    expect(crashReportingEnvironment(null), 'staging');
    expect(crashReportingEnvironment(''), 'staging');
    expect(crashReportingEnvironment('production'), 'production');
  });
}
