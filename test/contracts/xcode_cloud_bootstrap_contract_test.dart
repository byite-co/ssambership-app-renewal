import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Xcode Cloud bootstrap 계약 (2026-08-05 — Xcode Cloud SwiftPM 빌드 실패 교정).
///
/// 배경: Xcode Cloud 는 clean clone 직후 Swift Package dependency resolution 을
/// 수행하는데, Runner 가 참조하는 FlutterGeneratedPluginSwiftPackage 는 Flutter
/// 가 생성하는 ignored/ephemeral 산출물이라 저장소에 없다. resolution 이전에
/// `ios/ci_scripts/ci_post_clone.sh` 가 Flutter 를 준비해 패키지를 생성해야 한다.
///
/// 이 테스트는 그 bootstrap 이 **의도 없이** 깨지는 회귀를 잡는다:
/// 스크립트 삭제·실행권한 소실·버전 핀 해제·fail-closed 완화·secret 로그·
/// ephemeral 산출물 커밋·SwiftPM 배선 제거 등.
///
/// 주의: Linux/CI 에서 실행 가능한 **정적 검증**만 한다. Xcode Cloud 실빌드나
/// macOS 검증을 대신하지 않는다(런북 §9 참조).

const String kCiPostClonePath = 'ios/ci_scripts/ci_post_clone.sh';
const String kPbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
const String kSchemePath =
    'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme';

/// Flutter 버전 핀 — flutter-ci.yml·런북과 함께 갱신한다.
const String kPinnedFlutterVersion = '3.44.6';

/// 운영 Supabase URL — 스크립트는 이 값 외의 URL 을 거부해야 한다(fail closed).
const String kExpectedProdSupabaseUrl =
    'https://lbeqxarxothkmzqvpudy.supabase.co';

String _read(String path) {
  final File f = File(path);
  expect(f.existsSync(), isTrue, reason: '$path 가 존재해야 한다');
  return f.readAsStringSync();
}

void main() {
  group('ci_post_clone.sh 존재·형식 계약', () {
    late String script;
    setUpAll(() => script = _read(kCiPostClonePath));

    test('git index 에 실행권한(100755)으로 등록되어 있다', () {
      // Xcode Cloud 는 clone 된 파일 모드로 실행 여부를 판단한다 — 로컬 chmod 가
      // 아니라 git index mode 가 계약이다.
      final ProcessResult r =
          Process.runSync('git', <String>['ls-files', '-s', kCiPostClonePath]);
      expect(r.exitCode, 0, reason: 'git ls-files 실행 실패: ${r.stderr}');
      final String out = (r.stdout as String).trim();
      expect(out, isNotEmpty,
          reason: '$kCiPostClonePath 가 git 에 추적되고 있어야 한다');
      expect(out, startsWith('100755'),
          reason: '실행권한 소실(100644) 시 Xcode Cloud 가 스크립트를 실행하지 '
              '않는다 — git update-index --chmod=+x 로 복구할 것');
    });

    test('shebang 으로 시작하고 fail-fast(set -eu)를 적용한다', () {
      expect(script, startsWith('#!/bin/sh'),
          reason: 'Xcode Cloud 는 shebang 없는 스크립트 실행을 보장하지 않는다');
      expect(script, contains('\nset -eu'),
          reason: '중간 단계 실패가 조용히 넘어가면 archive 단계에서 더 '
              '알아보기 어려운 오류로 표면화된다');
    });

    test('secret 노출 경로가 없다(set -x·key echo 금지)', () {
      // 주석은 제외하고 실제 명령 라인만 검사한다.
      final String commands = script
          .split('\n')
          .where((String l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(commands, isNot(contains('set -x')),
          reason: 'shell trace 는 .env 생성 시 anon key 를 로그에 남긴다');
      expect(RegExp(r'echo .*SUPABASE_ANON_KEY').hasMatch(script), isFalse,
          reason: 'anon key 를 echo 로 출력하면 빌드 로그에 secret 이 남는다');
      expect(script, isNot(contains(r'${#SUPABASE_ANON_KEY}')),
          reason: 'key 길이 출력도 금지(부분 정보 노출 습관 방지)');
    });
  });

  group('ci_post_clone.sh 동작 계약', () {
    late String script;
    setUpAll(() => script = _read(kCiPostClonePath));

    test('Flutter 버전을 $kPinnedFlutterVersion 으로 고정한다', () {
      expect(script, contains(kPinnedFlutterVersion),
          reason: 'CI 재현성: flutter-ci.yml 의 검증 버전과 동일하게 핀 — '
              '버전 상향은 양쪽·런북을 함께 갱신하는 의도적 변경으로만');
      expect(script, isNot(contains('--branch stable')),
          reason: '"stable 최신" 클론은 핀이 아니다 — 태그로 고정할 것');
    });

    test('의존성 해석과 iOS config 생성을 xcodebuild 이전에 수행한다', () {
      expect(script, contains('flutter pub get'));
      expect(script, contains('--config-only'),
          reason: 'post-clone 에서 실제 archive 를 돌리면 안 된다 — '
              'config/ephemeral 산출물 생성까지만(archive 는 Xcode Cloud 몫)');
    });

    test('생성된 Swift package 존재를 마지막에 검증한다', () {
      expect(
          script,
          contains('ios/Flutter/ephemeral/Packages/'
              'FlutterGeneratedPluginSwiftPackage/Package.swift'),
          reason: '이 검증이 빠지면 생성 실패가 Xcode dependency resolution '
              '단계의 불투명한 오류로 미뤄진다');
    });

    test('운영 .env 는 fail closed 로 생성한다', () {
      expect(script, contains(r'${SUPABASE_URL:?'),
          reason: 'SUPABASE_URL 미설정 시 즉시 실패해야 한다');
      expect(script, contains(r'${SUPABASE_ANON_KEY:?'),
          reason: 'SUPABASE_ANON_KEY 미설정 시 즉시 실패해야 한다');
      expect(script, contains(kExpectedProdSupabaseUrl),
          reason: '기대 production URL 과 다르면 거부해야 한다');
      expect(script, contains('localhost'));
      expect(script, contains('127.0.0.1'),
          reason: '로컬 dev URL 로 스토어 빌드가 만들어지는 사고를 차단');
    });

    test('스토어 빌드 기능 플래그 경계를 우회하지 않는다', () {
      // 플래그 기본값(false)은 컴파일 타임 계약 — bootstrap 에서 dart-define
      // 주입으로 뒤집으면 안 된다(iq_create_boundary_test 와 동일 경계).
      expect(script, isNot(contains('--dart-define')),
          reason: '스토어 빌드는 모든 기능 플래그 기본값 유지');
      for (final String forbidden in <String>[
        'IQ_CREATE_ENABLED=true',
        'SUBS_MANAGE_LINK_ENABLED=true',
        'PAYOUT_MANAGE_LINK_ENABLED=true',
      ]) {
        expect(script, isNot(contains(forbidden)),
            reason: '기능 플래그 강제 활성 금지: $forbidden');
      }
    });
  });

  group('ephemeral 산출물·비밀값 비추적 계약', () {
    test('Flutter 생성 산출물은 git 에 추적되지 않는다', () {
      for (final List<String> probe in <List<String>>[
        <String>['ls-files', 'ios/Flutter/ephemeral'],
        <String>['ls-files', 'ios/Flutter/Generated.xcconfig'],
        <String>['ls-files', '.env'],
        <String>['ls-files', '*FlutterGeneratedPluginSwiftPackage*'],
      ]) {
        final ProcessResult r = Process.runSync('git', probe);
        expect(r.exitCode, 0, reason: 'git ${probe.join(' ')} 실행 실패');
        expect((r.stdout as String).trim(), isEmpty,
            reason: '${probe.last} 는 Flutter 가 매 빌드 생성하는 산출물/비밀값 '
                '— 커밋 금지(bootstrap 스크립트가 CI 에서 생성한다)');
      }
    });
  });

  group('Runner SwiftPM 배선 계약(bootstrap 의 전제)', () {
    test('pbxproj: generated package 를 상대경로 local reference 로 참조한다', () {
      final String pbx = _read(kPbxprojPath);
      expect(pbx, contains('XCLocalSwiftPackageReference'),
          reason: 'SwiftPM 배선 제거는 CocoaPods 회귀 — 금지(작업 계약 §9)');
      expect(
          pbx,
          contains('relativePath = Flutter/ephemeral/Packages/'
              'FlutterGeneratedPluginSwiftPackage;'),
          reason: 'package 경로는 상대경로여야 clean clone 에서 해석된다');
      expect(pbx, isNot(contains('/Users/')),
          reason: '개발자 로컬 절대경로가 커밋되면 CI 에서 반드시 깨진다');
    });

    test('Runner scheme: Flutter prepare pre-action 이 공유 scheme 에 있다', () {
      final String scheme = _read(kSchemePath);
      expect(scheme, contains('xcode_backend.sh'),
          reason: 'Flutter 3.44 SwiftPM 구조 필수 pre-action — 제거 금지');
      expect(scheme, contains('prepare'));
    });
  });
}
