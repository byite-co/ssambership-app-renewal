import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Android signed release-candidate workflow 계약
/// (`.github/workflows/android-signed-release-candidate.yml`).
///
/// 목적: 서명 workflow 의 보안 불변식이 **의도 없이** 약화되는 회귀를 잡는다.
/// 문자열 비교만으로 거짓 통과하지 않도록 YAML 을 구조 파싱해 검증하고,
/// 금지 문자열(secret 유출 경로)은 원문 전체를 별도 스캔한다.
///
/// 의도된 변경(대상 SHA 교체, 버전 상향 등)은 이 테스트와 workflow·런북
/// (docs/ANDROID_BUILD.md '§ signed release-candidate workflow')을 함께
/// 갱신해야 통과한다.
const String kWorkflowPath =
    '.github/workflows/android-signed-release-candidate.yml';

/// 빌드 대상 고정 — PR #51 head(1.0.0+18). 전체 40자 SHA 여야 한다.
const String kSourceSha = '35d7b03afe1f1fc601032e5f2c5218b7040422f5';

void main() {
  final String raw = File(kWorkflowPath).readAsStringSync();
  final YamlMap doc = loadYaml(raw) as YamlMap;

  // YAML 1.1 호환 파서가 `on:` 키를 bool true 로 읽는 경우까지 흡수한다.
  Object? triggerKey() =>
      doc.containsKey('on') ? doc['on'] : (doc.containsKey(true) ? doc[true] : null);

  group('트리거 계약 — workflow_dispatch 단독', () {
    test('workflow_dispatch 만 존재한다', () {
      final YamlMap on = triggerKey()! as YamlMap;
      expect(on.keys.map((Object? k) => k.toString()).toList(),
          <String>['workflow_dispatch'],
          reason: 'push/pull_request/schedule/repository_dispatch/workflow_run '
              '등 자동 트리거 추가 금지 — 서명 작업은 수동 dispatch 만');
    });

    test('수동 확인 입력 2종 — required + default false', () {
      final YamlMap on = triggerKey()! as YamlMap;
      final YamlMap inputs =
          (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
      for (final String name in <String>[
        'confirm_version_code_18_unused',
        'confirm_no_store_upload',
      ]) {
        final YamlMap input = inputs[name] as YamlMap;
        expect(input['required'], isTrue, reason: '$name: required 필수');
        expect(input['type'], 'boolean', reason: '$name: boolean 타입');
        expect(input['default'], isFalse,
            reason: '$name: 기본값은 false — 실수 실행 방지');
      }
    });

    test('job 은 두 확인 입력이 모두 true 일 때만 시작한다', () {
      final YamlMap job =
          (doc['jobs'] as YamlMap)['signed-release-candidate'] as YamlMap;
      final String cond = job['if'].toString();
      expect(cond, contains('confirm_version_code_18_unused == true'));
      expect(cond, contains('confirm_no_store_upload == true'));
      expect(cond, contains('&&'), reason: '두 확인의 AND 결합이어야 한다');
    });
  });

  group('권한·환경·동시성 계약', () {
    test('permissions 최소화 — contents/pull-requests read 뿐', () {
      final YamlMap perms = doc['permissions'] as YamlMap;
      expect(Map<Object?, Object?>.of(perms),
          <Object?, Object?>{'contents': 'read', 'pull-requests': 'read'},
          reason: 'write 권한·추가 scope 금지');
    });

    test('environment=android-release-candidate (approval 게이트 지점)', () {
      final YamlMap job =
          (doc['jobs'] as YamlMap)['signed-release-candidate'] as YamlMap;
      expect((job['environment'] as YamlMap)['name'],
          'android-release-candidate');
    });

    test('concurrency 고정 그룹 + cancel-in-progress=false', () {
      final YamlMap conc = doc['concurrency'] as YamlMap;
      expect(conc['group'], 'android-signed-release-candidate-18');
      expect(conc['cancel-in-progress'], isFalse,
          reason: '진행 중 서명 작업 취소는 반쪽 산출물을 남긴다');
    });
  });

  group('빌드 대상 고정 계약', () {
    final YamlMap env = doc['env'] as YamlMap;

    test('SOURCE_SHA 는 전체 40자 SHA 상수로 고정(자유 입력 아님)', () {
      expect(env['SOURCE_SHA'], kSourceSha);
      expect(kSourceSha.length, 40);
      final YamlMap on = triggerKey()! as YamlMap;
      final YamlMap inputs =
          (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
      for (final Object? name in inputs.keys) {
        expect(name.toString().toLowerCase(), isNot(contains('sha')),
            reason: 'SHA 를 입력으로 받으면 임의 코드를 서명할 수 있다 — 금지');
        expect(name.toString().toLowerCase(), isNot(contains('ref')),
            reason: 'ref 입력도 동일한 우회 경로 — 금지');
      }
    });

    test('버전·패키지 기대값 고정 (1.0.0+18 / versionCode 18 / edu 패키지)', () {
      expect(env['EXPECTED_PR'].toString(), '51');
      expect(env['EXPECTED_VERSION'].toString(), '1.0.0+18');
      expect(env['EXPECTED_VERSION_NAME'].toString(), '1.0.0');
      expect(env['EXPECTED_VERSION_CODE'].toString(), '18');
      expect(env['EXPECTED_APPLICATION_ID'], 'com.ssambership.edu');
      expect(env['EXPECTED_MIN_SDK'].toString(), '24');
      expect(env['EXPECTED_TARGET_SDK'].toString(), '36');
    });

    test('checkout step 은 SOURCE_SHA 를 ref 로 쓴다', () {
      final YamlMap job =
          (doc['jobs'] as YamlMap)['signed-release-candidate'] as YamlMap;
      final YamlList steps = job['steps'] as YamlList;
      final YamlMap checkout = steps.whereType<YamlMap>().firstWhere(
          (YamlMap s) => (s['uses'] ?? '').toString().startsWith('actions/checkout@'));
      expect((checkout['with'] as YamlMap)['ref'], r'${{ env.SOURCE_SHA }}',
          reason: 'workflow 정의(master)와 빌드 대상(SOURCE_SHA)을 혼동하지 않는다');
    });

    test('bundletool 은 버전+checksum 고정(latest 금지)', () {
      expect(env['BUNDLETOOL_VERSION'].toString(),
          matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(env['BUNDLETOOL_SHA256'].toString(),
          matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(raw, isNot(contains('/latest/')),
          reason: 'latest URL 은 공급망 고정 위반');
      expect(raw, contains('sha256sum -c'),
          reason: '다운로드 후 checksum 검증이 있어야 한다');
    });
  });

  group('secret·서명 안전 계약 (원문 스캔)', () {
    test('secret 유출 경로 금지 문자열이 없다', () {
      expect(raw, isNot(contains('set -x')));
      expect(raw, isNot(contains('printenv')));
      expect(raw, isNot(contains('cat .env')));
      expect(raw, isNot(contains('cat android/key.properties')));
      expect(raw.contains('allowInsecureSigning'), isFalse,
          reason: 'debug 서명 폴백 옵트인 금지 — keystore 없으면 실패해야 한다');
    });

    test('Play Console 업로드 step 이 없다', () {
      for (final String marker in <String>[
        'upload-google-play',
        'r0adkll',
        'androidpublisher',
        'play_store',
        'fastlane',
      ]) {
        expect(raw.toLowerCase(), isNot(contains(marker)),
            reason: '이 workflow 는 검증 전용 — 업로드 step 추가 금지($marker)');
      }
    });

    test('artifact 에 secret 파일이 없고 retention 3일이다', () {
      final YamlMap job =
          (doc['jobs'] as YamlMap)['signed-release-candidate'] as YamlMap;
      final YamlList steps = job['steps'] as YamlList;
      final YamlMap upload = steps.whereType<YamlMap>().firstWhere((YamlMap s) =>
          (s['uses'] ?? '').toString().startsWith('actions/upload-artifact@'));
      final YamlMap w = upload['with'] as YamlMap;
      expect(w['retention-days'], 3);
      expect(w['name'], 'ssambership-android-1.0.0-18-35d7b03-signed-aab');
      final String path = w['path'].toString();
      expect(path, contains('app-release.aab'));
      expect(path, contains('validation-summary.txt'));
      expect(path, contains('aab-sha256.txt'));
      for (final String forbidden in <String>[
        '.env',
        'key.properties',
        'keystore',
        '.jks',
      ]) {
        expect(path, isNot(contains(forbidden)),
            reason: 'secret 파일 artifact 포함 금지($forbidden)');
      }
    });

    test('cleanup step 은 always() 로 실행되고 secret 파일을 지운다', () {
      final YamlMap job =
          (doc['jobs'] as YamlMap)['signed-release-candidate'] as YamlMap;
      final YamlList steps = job['steps'] as YamlList;
      final YamlMap cleanup = steps.whereType<YamlMap>().lastWhere(
          (YamlMap s) => (s['name'] ?? '').toString().contains('cleanup'));
      expect(cleanup['if'].toString(), contains('always()'),
          reason: '실패 경로에서도 secret 파일이 남으면 안 된다');
      final String run = cleanup['run'].toString();
      expect(run, contains('rm -f .env android/key.properties'));
      expect(run, contains('ENV_FILE_CLEANED='));
      expect(run, contains('KEY_PROPERTIES_CLEANED='));
      expect(run, contains('KEYSTORE_CLEANED='));
      expect(run, contains('EXTRACTED_ENV_CLEANED='));
    });

    test('feature flag true 주입이 없다(기본 false 빌드)', () {
      for (final String flag in <String>[
        'IQ_CREATE_ENABLED=true',
        'SUBS_MANAGE_LINK_ENABLED=true',
        'PAYOUT_MANAGE_LINK_ENABLED=true',
      ]) {
        expect(raw, isNot(contains(flag)));
      }
      expect(raw, isNot(contains('--dart-define')),
          reason: 'release candidate 는 dart-define 주입 없이 기본값으로 빌드');
    });

    test('PR head 이동 차단 상태 문자열과 preflight 게이트가 배선돼 있다', () {
      expect(raw, contains('BLOCKED_APP_PR_HEAD_MOVED'));
      expect(raw, contains('dart run tool/validate_release_env.dart'));
      expect(raw, contains('jarsigner -verify'));
      expect(raw, contains('validate --bundle'));
      expect(raw, contains('CN=Android Debug'),
          reason: 'debug 인증서 검출 로직이 있어야 한다');
    });
  });

  group('문서 정본 계약', () {
    test('런북에 기본 브랜치 병합 전제와 workflow 절이 있다', () {
      final String runbook =
          File('docs/ANDROID_BUILD.md').readAsStringSync();
      expect(runbook, contains('signed release-candidate workflow'));
      expect(runbook, contains('기본 브랜치(master)에\n  병합된 이후에만'),
          reason: 'workflow_dispatch 의 기본 브랜치 전제를 런북에 명시(§C 계약)');
      expect(runbook, contains('android-release-candidate'));
      expect(runbook, contains('BLOCKED_APP_PR_HEAD_MOVED'));
    });

    test('workflow 주석에도 기본 브랜치 전제가 명시돼 있다', () {
      expect(raw, contains('기본 브랜치(master)에 병합된 이후에만'));
    });
  });
}
