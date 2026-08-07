import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Android signed release-candidate workflow 계약
/// (`.github/workflows/android-signed-release-candidate.yml`).
///
/// 목적: 서명 workflow 의 보안 불변식이 **의도 없이** 약화되는 회귀를 잡는다.
/// 문자열 비교만으로 거짓 통과하지 않도록 YAML 을 구조 파싱해 검증한다:
/// - 양성 배선(실행돼야 하는 게이트)은 step `run` 본문 결합 문자열에서 검사
///   — YAML 주석에 옮겨 적는 변이로는 통과하지 못한다.
/// - step 검사(checkout/upload-artifact/cleanup)는 **모든** 해당 step 을
///   순회하고 개수를 고정 — 두 번째 step 추가 변이로는 우회하지 못한다.
/// - 금지 문자열(secret 유출 경로)은 파일 원문 전체를 스캔(가장 엄격).
///
/// 의도된 변경(대상 SHA 교체, 버전 상향 등)은 이 테스트와 workflow·런북
/// (docs/ANDROID_BUILD.md '§ signed release-candidate workflow')을 함께
/// 갱신해야 통과한다.
const String kWorkflowPath =
    '.github/workflows/android-signed-release-candidate.yml';

/// 빌드 대상 고정 — S3 후보(1.0.0+19) head. 전체 40자 SHA 여야 한다.
const String kSourceSha = '2398b9bdc2aee91ff86214207a1998c10b444f3c';

/// 출시 Supabase 정본 URL(공개 식별자) — workflow 비교 기준값과 동일해야 한다.
const String kProductionSupabaseUrl =
    'https://lbeqxarxothkmzqvpudy.supabase.co';

void main() {
  final String raw = File(kWorkflowPath).readAsStringSync();
  final YamlMap doc = loadYaml(raw) as YamlMap;
  final YamlMap job =
      (doc['jobs'] as YamlMap)['signed-release-candidate'] as YamlMap;
  final YamlList steps = job['steps'] as YamlList;

  // YAML 1.1 호환 파서가 `on:` 키를 bool true 로 읽는 경우까지 흡수한다.
  Object? triggerKey() => doc.containsKey('on')
      ? doc['on']
      : (doc.containsKey(true) ? doc[true] : null);

  // 실행되는 shell 본문만 결합(YAML 주석은 파서가 제거 — scalar 내용만 남는다).
  final String runBodies = steps
      .whereType<YamlMap>()
      .map((YamlMap s) => (s['run'] ?? '').toString())
      .join('\n');

  List<YamlMap> stepsUsing(String prefix) => steps
      .whereType<YamlMap>()
      .where((YamlMap s) => (s['uses'] ?? '').toString().startsWith(prefix))
      .toList();

  group('트리거 계약 — workflow_dispatch 단독', () {
    test('workflow_dispatch 만 존재한다', () {
      final YamlMap on = triggerKey()! as YamlMap;
      expect(on.keys.map((Object? k) => k.toString()).toList(),
          <String>['workflow_dispatch'],
          reason: 'push/pull_request/schedule/repository_dispatch/workflow_run '
              '등 자동 트리거 추가 금지 — 서명 작업은 수동 dispatch 만');
    });

    test('수동 확인 입력 2종 — required + default false + 사람 확인 기록 취지', () {
      final YamlMap on = triggerKey()! as YamlMap;
      final YamlMap inputs =
          (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
      for (final String name in <String>[
        'confirm_version_code_19_unused',
        'confirm_no_store_upload',
      ]) {
        final YamlMap input = inputs[name] as YamlMap;
        expect(input['required'], isTrue, reason: '$name: required 필수');
        expect(input['type'], 'boolean', reason: '$name: boolean 타입');
        expect(input['default'], isFalse,
            reason: '$name: 기본값은 false — 실수 실행 방지');
        expect(input['description'].toString(), contains('사람 확인 기록'),
            reason: '$name: 자동/API 검증 대체가 아님을 UI 에서 알려야 한다');
      }
    });

    test('job 은 두 확인 입력이 모두 true 일 때만 시작한다', () {
      final String cond = job['if'].toString();
      expect(cond, contains('confirm_version_code_19_unused == true'));
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
      expect(
          (job['environment'] as YamlMap)['name'], 'android-release-candidate');
    });

    test('concurrency 고정 그룹 + cancel-in-progress=false', () {
      final YamlMap conc = doc['concurrency'] as YamlMap;
      expect(conc['group'], 'android-signed-release-candidate-19');
      expect(conc['cancel-in-progress'], isFalse,
          reason: '진행 중 서명 작업 취소는 반쪽 산출물을 남긴다');
    });

    test('job 수준 env 에서 runner 컨텍스트를 쓰지 않는다(가용 컨텍스트 아님)', () {
      // jobs.<id>.env 에서 ${{ runner.* }} 는 GitHub Actions 가 거부한다 —
      // workflow 전체가 실행 불능이 되는 회귀를 잡는다.
      final Object? jobEnv = job['env'];
      if (jobEnv is YamlMap) {
        for (final Object? v in jobEnv.values) {
          expect(v.toString(), isNot(contains(r'${{ runner.')),
              reason: 'runner 컨텍스트는 step 수준에서만 유효 — '
                  'GITHUB_ENV 주입 또는 \$RUNNER_TEMP 셸 변수를 쓸 것');
        }
      }
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

    test('버전·패키지·URL·테스트수 기대값 고정', () {
      expect(env['EXPECTED_PR'].toString(), '51');
      expect(env['EXPECTED_VERSION'].toString(), '1.0.0+19');
      expect(env['EXPECTED_VERSION_NAME'].toString(), '1.0.0');
      expect(env['EXPECTED_VERSION_CODE'].toString(), '19');
      expect(env['EXPECTED_APPLICATION_ID'], 'com.ssambership.edu');
      expect(env['EXPECTED_MIN_SDK'].toString(), '24');
      expect(env['EXPECTED_TARGET_SDK'].toString(), '36');
      expect(env['EXPECTED_TEST_COUNT'].toString(), '1507');
      expect(env['EXPECTED_SUPABASE_URL'], kProductionSupabaseUrl,
          reason: '.env 정확 일치·AAB 내장 판정의 기준값 — 변경은 의도적으로만');
    });

    test('checkout 은 정확히 1개이고 SOURCE_SHA 를 ref 로 쓴다', () {
      final List<YamlMap> checkouts = stepsUsing('actions/checkout@');
      expect(checkouts.length, 1,
          reason: '두 번째 checkout 은 SHA 검증 이후 임의 코드로 바꿔치기하는 '
              '우회 경로다 — 금지');
      final YamlMap w = checkouts.single['with'] as YamlMap;
      expect(w['ref'], r'${{ env.SOURCE_SHA }}',
          reason: 'workflow 정의 ref 와 빌드 대상(SOURCE_SHA)을 혼동하지 않는다');
      expect(w['persist-credentials'], isFalse,
          reason: '이후 step 은 git 자격증명이 불필요 — 토큰 잔존 금지');
    });

    test('external actions are pinned to immutable full commit SHAs', () {
      // 모든 job 의 모든 step 을 구조 순회 — raw 문자열 검색이 아니다.
      // 외부 action 참조는 `owner/action@<40자 소문자 hex SHA>` 만 허용한다
      // (tag·branch 는 mutable — supply-chain 재지정으로 secret 러너에 임의
      // 코드가 유입될 수 있다). 실행 정본은 SHA 이고 뒤 주석의 release tag 는
      // 가독성용이다(YAML 파서가 주석을 제거하므로 여기서는 SHA 만 보인다).
      final RegExp pinned = RegExp(r'^[^/\s]+/[^@\s]+@[0-9a-f]{40}$');
      final List<String> external = <String>[];
      for (final Object? j in (doc['jobs'] as YamlMap).values) {
        for (final YamlMap s
            in ((j! as YamlMap)['steps'] as YamlList).whereType<YamlMap>()) {
          final Object? uses = s['uses'];
          if (uses == null) continue;
          final String u = uses.toString();
          external.add(u);
          expect(pinned.hasMatch(u), isTrue,
              reason: '외부 action 은 40자 소문자 hex full SHA 로 고정해야 '
                  '한다(@vN·@main·@master·@latest·short SHA·대문자 금지): $u');
          final String ref = u.split('@').last;
          expect(ref.length, 40, reason: 'short SHA 금지: $u');
          expect(ref, isNot(matches(RegExp(r'[A-Z]'))),
              reason: '대문자 hex 금지: $u');
        }
      }
      expect(external.length, 4,
          reason: '외부 action 은 정확히 4개(checkout·setup-java·'
              'flutter-action·upload-artifact) — 추가·제거는 의도적 변경으로만');
      for (final String mutableRef in <String>[
        '@v4',
        '@v2',
        '@main',
        '@master',
        '@latest',
      ]) {
        for (final String u in external) {
          expect(u.endsWith(mutableRef), isFalse,
              reason: 'mutable ref 금지($mutableRef): $u');
        }
      }
    });

    test('bundletool 은 버전+checksum 고정(latest 금지)', () {
      expect(env['BUNDLETOOL_VERSION'].toString(),
          matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(env['BUNDLETOOL_SHA256'].toString(),
          matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(raw, isNot(contains('/latest/')),
          reason: 'latest URL 은 공급망 고정 위반');
      expect(runBodies, contains('sha256sum -c'),
          reason: '다운로드 후 checksum 검증이 실행 경로에 있어야 한다');
    });
  });

  group('secret·서명 안전 계약', () {
    test('금지 문자열이 파일 어디에도 없다(주석 포함 — 가장 엄격)', () {
      expect(raw, isNot(contains('printenv')));
      expect(raw, isNot(contains('cat .env')));
      expect(raw, isNot(contains('cat android/key.properties')));
      expect(raw.contains('allowInsecureSigning'), isFalse,
          reason: 'debug 서명 폴백 옵트인 금지 — keystore 없으면 실패해야 한다');
    });

    test('shell 트레이스(xtrace) 변형이 실행 본문에 없다', () {
      // set -x / set -euxo / set -o xtrace / bash -x 전부 — secret 원문이
      // 트레이스로 노출되는 경로를 변형 포함해 차단한다.
      expect(runBodies, isNot(matches(RegExp(r'set\s+-[a-zA-Z]*x'))));
      expect(runBodies, isNot(contains('xtrace')));
      expect(runBodies, isNot(matches(RegExp(r'bash\s+-x\b'))));
    });

    test('Play Console 업로드 step 이 없다', () {
      for (final String marker in <String>[
        'upload-google-play',
        'r0adkll',
        'androidpublisher',
        'play_store',
        'fastlane',
        'publishReleaseBundle',
      ]) {
        expect(raw.toLowerCase(), isNot(contains(marker.toLowerCase())),
            reason: '이 workflow 는 검증 전용 — 업로드 step 추가 금지($marker)');
      }
    });

    test('upload-artifact 는 정확히 1개 — secret 파일 없음·retention 3일', () {
      final List<YamlMap> uploads = stepsUsing('actions/upload-artifact@');
      expect(uploads.length, 1,
          reason: '두 번째 artifact step 은 secret 유출 우회 경로다 — 금지');
      final YamlMap w = uploads.single['with'] as YamlMap;
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

    test('cleanup 은 마지막 step 이고 always() 로 secret 파일을 지운다', () {
      final YamlMap last = steps.whereType<YamlMap>().last;
      expect((last['name'] ?? '').toString(), contains('cleanup'),
          reason: 'cleanup 뒤에 step 이 오면 secret 파일이 재생성될 수 있다');
      expect(last['if'].toString(), contains('always()'),
          reason: '실패 경로에서도 secret 파일이 남으면 안 된다');
      final String run = last['run'].toString();
      expect(run, contains(r'rm -f .env android/key.properties "$KS"'),
          reason: '.env·key.properties·keystore 삭제 명령이 있어야 한다');
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

    test('flutter test gate uses actual numeric reporter footer', () {
      // run 31106224905 회귀: 1,469건 전부 통과 후 stale 문구('All tests
      // passed!' — 로컬 compact reporter 전용) 고정 검색으로 거짓 실패했다.
      // 성공 판정은 exit code + 실제 reporter footer 의 숫자("N tests
      // passed.") 파싱 + EXPECTED_TEST_COUNT 대조여야 한다. 주석이 아닌
      // 실제 step run 본문을 검사한다.
      final YamlMap testStep = steps.whereType<YamlMap>().firstWhere(
          (YamlMap s) =>
              (s['name'] ?? '').toString().startsWith('flutter test'));
      final String run = testStep['run'].toString();
      expect(run, contains('set -euo pipefail'));
      expect(run, contains('flutter test 2>&1 | tee /tmp/test.log'));
      // 숫자 footer 파싱 게이트 존재.
      expect(run, contains(r"grep -aoE '[0-9]+ tests passed\.'"),
          reason: '실제 reporter footer("N tests passed.")에서 숫자를 읽어야 한다');
      expect(run, contains(r'if [ -z "$COUNT" ]'),
          reason: '통과 수를 읽지 못하면 실패하는 게이트가 있어야 한다');
      expect(run, contains(r'"$COUNT" != "$EXPECTED_TEST_COUNT"'),
          reason: 'EXPECTED_TEST_COUNT 와의 대조가 있어야 한다');
      // stale 문구 의존 금지(실행 본문 기준).
      expect(run, isNot(contains('All tests passed!')),
          reason: '로컬 compact reporter 전용 문구 — CI(github reporter)에서 '
              '거짓 실패를 만든다');
      // flutter test 명령 자체를 성공으로 강제하는 || true 금지
      // (footer 추출 서브셸의 빈 결과 처리용 || true 만 허용).
      expect(run, isNot(matches(RegExp(r'flutter test[^\n]*\|\|\s*true'))),
          reason: 'flutter test 실패가 exit code 로 반드시 드러나야 한다');
    });

    test('게이트가 실행 본문(run)에 실제로 배선돼 있다 — 주석으로는 불충분', () {
      expect(runBodies, contains('BLOCKED_APP_PR_HEAD_MOVED'));
      expect(runBodies, contains('dart run tool/validate_release_env.dart'));
      expect(runBodies, contains('jarsigner -verify'));
      expect(runBodies, contains('validate --bundle'));
      expect(runBodies, contains('Android Debug'),
          reason: 'debug 인증서 검출 로직이 실행 경로에 있어야 한다');
      expect(runBodies, contains('This jar contains unsigned entries'),
          reason: 'unsigned entry 게이트(정확 문구 매치)가 있어야 한다');
      expect(runBodies, contains('cp .env.example .env'),
          reason: 'analyze·test 는 자리표시 .env 로 실행(운영 secret 은 '
              '테스트 이후에만 디스크에 존재)');
      expect(runBodies, contains('flutter build appbundle --release'));
    });
  });

  group('문서 정본 계약', () {
    // 공백 정규화 — 문서 리라핑(줄바꿈 위치 변경)에 과민하지 않게 비교한다.
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

    test('런북에 기본 브랜치 병합 전제·Environment 필수 전제가 있다', () {
      final String runbook =
          norm(File('docs/ANDROID_BUILD.md').readAsStringSync());
      expect(runbook, contains('signed release-candidate workflow'));
      expect(runbook, contains('기본 브랜치(master)에 병합된 이후에만'),
          reason: 'workflow_dispatch 의 기본 브랜치 전제를 런북에 명시(§C 계약)');
      expect(runbook, contains('android-release-candidate'));
      expect(runbook, contains('BLOCKED_APP_PR_HEAD_MOVED'));
      expect(runbook, contains('required reviewers'),
          reason: 'Environment approval 없이는 secret 노출 경로가 열린다');
      expect(runbook, contains('deployment branch policy'),
          reason: '임의 ref 의 변형 정의 dispatch 를 막는 필수 전제');
    });

    test('workflow 주석에도 기본 브랜치 전제가 명시돼 있다', () {
      expect(norm(raw), contains('기본 브랜치(master)에 병합된 이후에만'));
    });
  });
}
