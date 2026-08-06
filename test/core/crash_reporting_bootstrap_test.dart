import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:ssambership_app/core/observability/crash_reporting.dart';

/// G3 보강 — fail-open 부팅 계약(§14)·옵션(§15)·환경 정책(§16)·release(§17).
void main() {
  group('§14 부팅 계약', () {
    test('1. blank DSN → initializer 0회, appRunner 1회', () async {
      int initCalls = 0, runnerCalls = 0;
      await bootstrapCrashReporting(
        appRunner: () async => runnerCalls++,
        dsnOverride: '',
        initializerOverride: (FutureOr<void> Function(SentryFlutterOptions) c,
            {Future<void> Function()? appRunner}) async {
          initCalls++;
        },
      );
      expect(initCalls, 0);
      expect(runnerCalls, 1);
    });

    test('2. whitespace DSN → initializer 0회, appRunner 1회', () async {
      int initCalls = 0, runnerCalls = 0;
      await bootstrapCrashReporting(
        appRunner: () async => runnerCalls++,
        dsnOverride: '   ',
        initializerOverride: (FutureOr<void> Function(SentryFlutterOptions) c,
            {Future<void> Function()? appRunner}) async {
          initCalls++;
        },
      );
      expect(initCalls, 0);
      expect(runnerCalls, 1);
    });

    test('3. DSN 있음 + 정상 init → initializer 1회, appRunner 1회(내부에서)', () async {
      int initCalls = 0, runnerCalls = 0;
      await bootstrapCrashReporting(
        appRunner: () async => runnerCalls++,
        dsnOverride: 'https://k@example.invalid/1',
        initializerOverride: (FutureOr<void> Function(SentryFlutterOptions) c,
            {Future<void> Function()? appRunner}) async {
          initCalls++;
          await appRunner!();
        },
      );
      expect(initCalls, 1);
      expect(runnerCalls, 1);
    });

    test('4. init 이 appRunner 전에 throw → fallback 1회, 총 1회', () async {
      int runnerCalls = 0;
      await bootstrapCrashReporting(
        appRunner: () async => runnerCalls++,
        dsnOverride: 'https://k@example.invalid/1',
        initializerOverride: (FutureOr<void> Function(SentryFlutterOptions) c,
            {Future<void> Function()? appRunner}) async {
          throw StateError('sentry native init failed');
        },
      );
      expect(runnerCalls, 1, reason: 'fail-open fallback 정확 1회');
    });

    test('5. init 이 appRunner 실행 후 throw → 재실행 0, 총 1회, 부팅 유지', () async {
      int runnerCalls = 0;
      await bootstrapCrashReporting(
        appRunner: () async => runnerCalls++,
        dsnOverride: 'https://k@example.invalid/1',
        initializerOverride: (FutureOr<void> Function(SentryFlutterOptions) c,
            {Future<void> Function()? appRunner}) async {
          await appRunner!();
          throw StateError('post-runner init failure');
        },
      );
      expect(runnerCalls, 1, reason: '이미 부팅됨 — 재실행·중복 runApp 금지');
    });

    test('6. appRunner 가 throw → 원본 오류·스택 보존 rethrow, 총 1회, 삼킴 없음', () async {
      int runnerCalls = 0;
      final StateError original = StateError('bootstrap exploded');
      Object? caught;
      StackTrace? caughtStack;
      try {
        await bootstrapCrashReporting(
          appRunner: () async {
            runnerCalls++;
            throw original;
          },
          dsnOverride: 'https://k@example.invalid/1',
          initializerOverride: (FutureOr<void> Function(SentryFlutterOptions) c,
              {Future<void> Function()? appRunner}) async {
            await appRunner!(); // runner 오류가 init 밖으로 전파되는 실제 경로
          },
        );
      } catch (e, st) {
        caught = e;
        caughtStack = st;
      }
      expect(runnerCalls, 1);
      expect(identical(caught, original), isTrue,
          reason: 'init 실패로 오인해 fallback 재실행하거나 다른 오류로 감싸면 안 된다');
      expect(caughtStack.toString(), contains('crash_reporting_bootstrap_test'),
          reason: '원본 스택 보존(throwWithStackTrace)');
    });

    test('7. init 이 appRunner 를 중복 호출해도 실제 bootstrap 1회', () async {
      int runnerCalls = 0;
      await bootstrapCrashReporting(
        appRunner: () async => runnerCalls++,
        dsnOverride: 'https://k@example.invalid/1',
        initializerOverride: (FutureOr<void> Function(SentryFlutterOptions) c,
            {Future<void> Function()? appRunner}) async {
          await appRunner!();
          await appRunner();
          await Future.wait(<Future<void>>[appRunner(), appRunner()]); // 동시 호출
        },
      );
      expect(runnerCalls, 1, reason: 'once-only guard');
    });
  });

  group('§15 옵션 정본', () {
    SentryFlutterOptions apply({String environment = 'staging'}) {
      final SentryFlutterOptions o = SentryFlutterOptions();
      applyCrashReportingOptions(o,
          dsn: 'https://k@example.invalid/1', environment: environment);
      return o;
    }

    test('8. sendDefaultPii=false 명시', () {
      expect(apply().sendDefaultPii, isFalse);
    });

    test(
        '9. tracing 완전 비활성 — tracesSampleRate=null ∧ tracesSampler=null ∧ isTracingEnabled=false',
        () {
      final SentryFlutterOptions o = apply();
      expect(o.tracesSampleRate, isNull);
      expect(o.tracesSampler, isNull);
      expect(o.isTracingEnabled(), isFalse,
          reason: 'SDK 계약: 둘 다 null 이면 트랜잭션 생성 자체가 없다');
    });

    test('10. profiling 비활성 — profilesSampleRate=null (tracing off 전제)', () {
      // ignore: experimental_member_use
      expect(apply().profilesSampleRate, isNull);
    });

    test(
        '§17 release/dist — 수동 설정 없음(null 유지 → SDK LoadReleaseIntegration 이 '
        'packageName@version+buildNumber / dist=buildNumber 로 채운다)', () {
      final SentryFlutterOptions o = apply();
      expect(o.release, isNull, reason: '하드코딩·수동 override 금지');
      expect(o.dist, isNull);
    });
  });

  group('§16 environment 정책', () {
    test('11. blank environment → production 으로 해석되지 않는다(staging 기본)', () {
      expect(crashReportingEnvironment(null), 'staging');
      expect(crashReportingEnvironment(''), 'staging');
      expect(crashReportingEnvironment('  '), 'staging');
      expect(crashReportingEnvironment(''), isNot('production'));
    });

    test('12. staging → staging 유지', () {
      expect(crashReportingEnvironment('staging'), 'staging');
    });

    test('13. production → production 유지', () {
      expect(crashReportingEnvironment('production'), 'production');
    });
  });
}
