import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS 출시 설정 계약 (2026-08-04 수렴 — docs/IOS_RELEASE_RUNBOOK.md 가 정본).
///
/// 목적: iOS 네이티브 설정(Info.plist·PrivacyInfo·pbxproj)과 버전·문서 정본이
/// **의도 없이** 바뀌는 회귀를 잡는다. 의도된 변경(버전 증가, reason 추가 등)은
/// 이 테스트와 런북을 함께 갱신해야 통과한다.
///
/// 주의: 이 테스트는 Linux/CI 에서 실행 가능한 **정적 검증**만 한다.
/// Xcode 빌드·아카이브 privacy report 등 macOS 전용 검증을 대신하지 않는다
/// (그 절차는 런북 §9 — 여기서 PASS 라고 macOS 검증이 끝난 것이 아니다).

const String kInfoPlistPath = 'ios/Runner/Info.plist';
const String kPrivacyManifestPath = 'ios/Runner/PrivacyInfo.xcprivacy';
const String kPbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
const String kPodfilePath = 'ios/Podfile';
const String kRunbookPath = 'docs/IOS_RELEASE_RUNBOOK.md';

/// 버전 고정(§7 런북 버전 규약). Play Console 실측(2026-08-06)상 build 16·17 이
/// 이미 사용돼 출시 후보를 `1.0.0+18` 로 올렸다 — 근거와 재상향 규칙은
/// `test/app/build_version_test.dart` 주석 참조. 실제 업로드용 release 커밋에서
/// 다시 올릴 때 이 상수를 함께 갱신한다.
const String kPinnedPubspecVersion = 'version: 1.0.0+18';

/// iOS 번들 ID 계약(HANDOFF §3-6, 2026-07-22 패키지 계약).
/// App Store Connect 첫 업로드 후 변경 불가 — 변경은 오너 결정으로만(런북 §3).
const String kIosBundleId = 'com.ssambership.app';

/// canLaunchUrl 조회 스킴 allowlist — web_bridge.isAllowedUri 가 https 를
/// 강제하므로 https 하나면 충분하다(런북 §5-1). 스킴 추가는 의도적 변경으로만.
const Set<String> kAllowedQuerySchemes = <String>{'https'};

/// 앱 수준 매니페스트의 required-reason 카테고리 allowlist.
/// 현재는 **비어 있어야 한다**(1st-party 코드 직접 사용 없음 — 엔진·플러그인은
/// 각자 매니페스트로 선언, 런북 §6). ITMS-91053 으로 Apple 이 지목한 카테고리를
/// 추가할 때만 이 집합과 매니페스트를 함께 갱신한다.
const Set<String> kAllowedAppReasonCategories = <String>{};

/// 앱이 실제로 수집(사용자 입력·생성물을 서버로 전송)하는 데이터 유형 —
/// TN3184 기준, 코드 인벤토리(감사 문서 D2)와 1:1. 수집 표면이 바뀌면
/// 인벤토리·매니페스트·이 집합·App Privacy 설문을 함께 갱신한다.
const Set<String> kExpectedCollectedDataTypes = <String>{
  'NSPrivacyCollectedDataTypeEmailAddress', // 로그인 이메일
  'NSPrivacyCollectedDataTypeUserID', // user id·닉네임(스크린네임)
  'NSPrivacyCollectedDataTypePhotosorVideos', // 사진·촬영본 업로드
  'NSPrivacyCollectedDataTypeOtherUserContent', // 질문·답변·댓글·PDF·필기
  'NSPrivacyCollectedDataTypeOtherDataTypes', // 학년(선택 입력)
};

/// 근거 없이 선언되면 안 되는 유형(결제 입력은 웹 전용·실명 수집 없음 등).
const Set<String> kForbiddenCollectedDataTypes = <String>{
  'NSPrivacyCollectedDataTypePaymentInfo',
  'NSPrivacyCollectedDataTypePurchaseHistory',
  'NSPrivacyCollectedDataTypeName',
  'NSPrivacyCollectedDataTypePreciseLocation',
  'NSPrivacyCollectedDataTypeCoarseLocation',
  'NSPrivacyCollectedDataTypeContacts',
  'NSPrivacyCollectedDataTypeDeviceID',
  'NSPrivacyCollectedDataTypeAdvertisingData',
};

/// Apple 이 정의한 수집 목적 전체(형식 상한). 현재 앱은 AppFunctionality 만
/// 사용한다 — 분석·광고 목적은 해당 SDK 도입 근거 없이는 추가 금지.
const Set<String> kApplePurposes = <String>{
  'NSPrivacyCollectedDataTypePurposeAppFunctionality',
  'NSPrivacyCollectedDataTypePurposeAnalytics',
  'NSPrivacyCollectedDataTypePurposeProductPersonalization',
  'NSPrivacyCollectedDataTypePurposeDeveloperAdvertising',
  'NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising',
  'NSPrivacyCollectedDataTypePurposeOther',
};

const Set<String> kAllowedPurposes = <String>{
  'NSPrivacyCollectedDataTypePurposeAppFunctionality',
};

/// Apple 이 정의한 required-reason 카테고리 전체(형식 검증용 상한).
const Set<String> kAppleReasonCategories = <String>{
  'NSPrivacyAccessedAPICategoryFileTimestamp',
  'NSPrivacyAccessedAPICategorySystemBootTime',
  'NSPrivacyAccessedAPICategoryDiskSpace',
  'NSPrivacyAccessedAPICategoryActiveKeyboards',
  'NSPrivacyAccessedAPICategoryUserDefaults',
};

String _read(String path) {
  final File f = File(path);
  expect(f.existsSync(), isTrue, reason: '$path 가 존재해야 한다');
  return f.readAsStringSync();
}

int _count(String haystack, Pattern needle) =>
    needle.allMatches(haystack).length;

void main() {
  group('Info.plist 계약', () {
    late String plist;
    setUpAll(() => plist = _read(kInfoPlistPath));

    test('표시명은 쌤버십(Android 라벨·스토어 등록명과 일치)', () {
      expect(
        plist,
        contains(
            '<key>CFBundleDisplayName</key>\n\t<string>쌤버십</string>'),
      );
    });

    test('CFBundleName·버전 placeholder 는 Flutter 규약 그대로', () {
      expect(plist, contains('<string>ssambership_app</string>'));
      expect(plist, contains(r'<string>$(FLUTTER_BUILD_NAME)</string>'));
      expect(plist, contains(r'<string>$(FLUTTER_BUILD_NUMBER)</string>'));
      expect(plist, contains(r'<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>'));
    });

    test('수출규정 키: ITSAppUsesNonExemptEncryption=false 정확히 1회', () {
      expect(
          _count(plist, '<key>ITSAppUsesNonExemptEncryption</key>'), 1);
      expect(
        plist,
        contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
        reason: '면제 근거(OS TLS + JWT 서명검증)는 런북 §7 — true 로 바꾸려면 '
            '비면제 암호화 도입 근거와 함께 런북·이 테스트를 갱신할 것',
      );
    });

    test('LSApplicationQueriesSchemes 는 allowlist 와 정확히 일치', () {
      final RegExp block = RegExp(
          r'<key>LSApplicationQueriesSchemes</key>\s*<array>(.*?)</array>',
          dotAll: true);
      final RegExpMatch? m = block.firstMatch(plist);
      expect(m, isNotNull, reason: 'canLaunchUrl 조회 스킴 선언이 없으면 '
          'web_bridge 웹 링크가 iOS 에서 전부 조용히 실패한다(런북 §5-1)');
      final Set<String> declared = RegExp(r'<string>([^<]+)</string>')
          .allMatches(m!.group(1)!)
          .map((RegExpMatch e) => e.group(1)!)
          .toSet();
      expect(declared, kAllowedQuerySchemes,
          reason: '스킴 추가/제거는 의도적 변경으로만(allowlist 동시 갱신)');
    });

    test('web_bridge 는 여전히 https 만 열어준다(스킴 allowlist 의 전제)', () {
      final String bridge = _read('lib/core/web_bridge/web_bridge.dart');
      expect(bridge, contains("if (uri.scheme != 'https') return false;"),
          reason: 'isAllowedUri 의 https 강제가 사라지면 '
              'LSApplicationQueriesSchemes(https 단독) 전제가 깨진다 — '
              '코드와 plist 를 함께 재검토할 것');
      expect(bridge, contains('await canLaunchUrl(uri)'),
          reason: 'canLaunchUrl 사전 확인을 제거(직접 launchUrl)하는 리팩터링을 '
              '하면 스킴 선언 필요성 자체가 바뀐다 — 런북 §5-1 재판정 필요');
    });

    test('ATS 는 로컬 네트워킹 예외만(전면 해제 금지)', () {
      expect(plist, contains('<key>NSAllowsLocalNetworking</key>'));
      expect(plist, isNot(contains('NSAllowsArbitraryLoads')),
          reason: 'ATS 전면 해제는 심사 사유 요구 대상 — 도입 금지');
    });

    test('권한 문구(사진·카메라·마이크)는 유지 — 키+비어있지 않은 문구 쌍으로 검사', () {
      // ★ contains(키) 단독 검사는 주석 처리·빈 <string/> 회귀를 못 잡는다
      //   (PrivacyInfo 테스트의 '주석 오탐 차단'과 동일 원칙). 키 바로 다음
      //   줄의 <string> 값이 비어 있지 않은 '실제 선언'만 인정한다.
      for (final String key in <String>[
        'NSPhotoLibraryUsageDescription',
        'NSCameraUsageDescription',
        // 숏폼 WebView 영상 촬영은 마이크 권한을 함께 요구한다 — 키가 빠지면
        // '촬영' 선택 순간 TCC 강제 종료(2026-08 실기기 크래시 교정, 런북 §2).
        'NSMicrophoneUsageDescription',
      ]) {
        expect(
          RegExp('^\\t<key>$key</key>\\n\\t<string>[^<]+</string>',
                  multiLine: true)
              .hasMatch(plist),
          isTrue,
          reason: '$key: 주석 밖 + 비어있지 않은 사용 사유 문구가 필요하다'
              '(빈 문구는 심사·런타임 문제, 키 부재는 해당 기능 진입 시 크래시)',
        );
      }
    });
  });

  group('PrivacyInfo.xcprivacy 계약', () {
    late String manifest;
    setUpAll(() => manifest = _read(kPrivacyManifestPath));

    test('추적 없음 선언(NSPrivacyTracking=false, 추적 도메인 없음)', () {
      expect(manifest,
          contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
      expect(manifest,
          contains('<key>NSPrivacyTrackingDomains</key>\n\t<array/>'));
    });

    test('수집 데이터 선언은 코드 인벤토리와 정확히 일치(TN3184 — 런북 §6-1)', () {
      // NSPrivacyCollectedDataTypes 블록 추출 — 다음 최상위 키(AccessedAPITypes)
      // 전까지 슬라이스(내부 Purposes <array> 와의 중첩 오매칭 방지).
      final int start =
          manifest.indexOf('<key>NSPrivacyCollectedDataTypes</key>');
      final int end =
          manifest.indexOf('<key>NSPrivacyAccessedAPITypes</key>');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start),
          reason: '매니페스트 키 순서 계약: CollectedDataTypes → AccessedAPITypes');
      final String block = manifest.substring(start, end);

      // dict 단위 파싱.
      final List<String> dicts = RegExp(r'<dict>(.*?)</dict>', dotAll: true)
          .allMatches(block)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();
      expect(dicts, isNotEmpty,
          reason: '앱이 이메일·콘텐츠 등을 실제 수집하므로 빈 배열은 계약 위반'
              '(과거 빈 배열 상태는 2026-08-04 교정으로 폐기)');

      final List<String> declaredTypes = <String>[];
      for (final String d in dicts) {
        // 필수 키 4종.
        for (final String requiredKey in <String>[
          '<key>NSPrivacyCollectedDataType</key>',
          '<key>NSPrivacyCollectedDataTypeLinked</key>',
          '<key>NSPrivacyCollectedDataTypeTracking</key>',
          '<key>NSPrivacyCollectedDataTypePurposes</key>',
        ]) {
          expect(d, contains(requiredKey),
              reason: 'TN3184: dictionary 필수 키 누락 — $requiredKey');
        }
        final String type = RegExp(
                r'<key>NSPrivacyCollectedDataType</key>\s*<string>([^<]+)</string>')
            .firstMatch(d)!
            .group(1)!;
        declaredTypes.add(type);
        // Linked/Tracking 은 plist boolean 태그여야 한다(코드 인벤토리상
        // 전 항목 계정 연결 수집 → Linked=true, 추적 SDK 0건 → Tracking=false).
        expect(
            RegExp(r'<key>NSPrivacyCollectedDataTypeLinked</key>\s*<true/>')
                .hasMatch(d),
            isTrue,
            reason: '$type: Linked 는 <true/> (전 수집이 계정 기반)');
        expect(
            RegExp(r'<key>NSPrivacyCollectedDataTypeTracking</key>\s*<false/>')
                .hasMatch(d),
            isTrue,
            reason: '$type: Tracking 은 <false/> — 최상위 NSPrivacyTracking'
                '=false 와의 모순 금지(추적 도입 시 양쪽·ATT 재검토)');
        // purposes: 비어 있지 않고, Apple 목록 내이며, 현재는 AppFunctionality 만.
        final List<String> purposes = RegExp(r'<string>([^<]+)</string>')
            .allMatches(d)
            .map((RegExpMatch m) => m.group(1)!)
            .where((String s) => s.startsWith(
                'NSPrivacyCollectedDataTypePurpose'))
            .toList();
        expect(purposes, isNotEmpty, reason: '$type: purposes 비어 있음');
        expect(purposes.toSet().difference(kApplePurposes), isEmpty,
            reason: '$type: Apple 정의 밖 purpose 금지(오타 방지)');
        expect(purposes.toSet().difference(kAllowedPurposes), isEmpty,
            reason: '$type: 분석·광고 목적은 해당 SDK 실측 근거와 함께만 추가');
      }

      // 중복 0 + 기대 집합과 정확히 일치.
      expect(declaredTypes.length, declaredTypes.toSet().length,
          reason: '같은 데이터 유형 중복 선언 금지');
      expect(declaredTypes.toSet(), kExpectedCollectedDataTypes,
          reason: '선언 집합은 코드 인벤토리(감사 문서 D2)와 1:1 — '
              '수집 표면 변경 시 인벤토리·설문과 함께 갱신');
      // 근거 없는 유형 금지(결제수단 입력 웹 전용·실명 수집 없음 등).
      expect(
          declaredTypes.toSet().intersection(kForbiddenCollectedDataTypes),
          isEmpty,
          reason: '수집 사실이 없는 유형의 "안전상" 선언 금지');
    });

    test('required-reason 선언은 앱 수준 allowlist 와 일치(현재: 없음)', () {
      final Set<String> declared =
          RegExp(r'NSPrivacyAccessedAPICategory[A-Za-z]+')
              .allMatches(manifest)
              .map((RegExpMatch m) => m.group(0)!)
              .toSet();
      // 주석 안의 언급까지 포함해 스캔하므로, '선언'은 <string> 태그 안만 센다.
      final Set<String> declaredStrings =
          RegExp(r'<string>(NSPrivacyAccessedAPICategory[A-Za-z]+)</string>')
              .allMatches(manifest)
              .map((RegExpMatch m) => m.group(1)!)
              .toSet();
      expect(declaredStrings, kAllowedAppReasonCategories,
          reason: '엔진·플러그인이 자체 선언하는 API 를 앱 매니페스트에 중복하지 '
              '않는다. ITMS-91053 지목 시에만 allowlist 와 함께 추가(런북 §6)');
      expect(declared.difference(kAppleReasonCategories), isEmpty,
          reason: 'Apple 카테고리 집합 밖의 식별자 금지(오타 방지)');
      // reason 코드 형식(XXXX.N) 검증 — 선언이 생기면 자동으로 적용된다.
      for (final RegExpMatch m
          in RegExp(r'<string>([A-Z0-9]{4}\.\d)</string>')
              .allMatches(manifest)) {
        expect(m.group(1), matches(RegExp(r'^[A-Z0-9]{4}\.\d$')));
      }
    });
  });

  group('project.pbxproj 계약', () {
    late String pbx;
    setUpAll(() => pbx = _read(kPbxprojPath));

    test('PrivacyInfo 는 Runner Resources 에 정확히 한 번 배선', () {
      // PBXBuildFile 정의 1 + Resources files 목록 1 = 'in Resources' 주석 2회.
      expect(_count(pbx, 'PrivacyInfo.xcprivacy in Resources'), 2,
          reason: '0회=미포함(심사 미반영), 3회 이상=중복 포함(빌드 경고)');
      // PBXFileReference 정의는 정확히 1회.
      expect(
          _count(
              pbx,
              RegExp(r'PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference')),
          1);
      // BuildFile 의 fileRef 가 FileReference UUID 와 일치.
      final RegExpMatch? fileRef = RegExp(
              r'([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference')
          .firstMatch(pbx);
      expect(fileRef, isNotNull);
      expect(
          pbx,
          contains(RegExp('fileRef = ${fileRef!.group(1)!} '
              r'/\* PrivacyInfo\.xcprivacy \*/')));
    });

    test('번들 ID 불변: Runner 3구성 + RunnerTests 3구성', () {
      expect(
          _count(pbx,
              'PRODUCT_BUNDLE_IDENTIFIER = $kIosBundleId.RunnerTests;'),
          3);
      final int runnerOnly =
          _count(pbx, RegExp('PRODUCT_BUNDLE_IDENTIFIER = '
              '${RegExp.escape(kIosBundleId)};'));
      expect(runnerOnly, 3,
          reason: '번들 ID 변경은 오너 결정으로만(첫 업로드 후 변경 불가 — 런북 §3)');
      expect(_count(pbx, 'PRODUCT_BUNDLE_IDENTIFIER'), 6,
          reason: '허용된 6곳 외의 번들 ID 설정 금지');
    });

    test('배포 타깃 13.0 고정(전 구성)', () {
      final int total = _count(pbx, 'IPHONEOS_DEPLOYMENT_TARGET');
      expect(total, greaterThanOrEqualTo(3));
      expect(_count(pbx, 'IPHONEOS_DEPLOYMENT_TARGET = 13.0;'), total,
          reason: '타깃 상향/하향은 Podfile platform 과 함께 의도적으로만');
    });

    test('구조 건전성: 중괄호·괄호 균형', () {
      expect(_count(pbx, '{'), _count(pbx, '}'));
      expect(_count(pbx, '('), _count(pbx, ')'));
    });

    test('서명 스타일 Automatic 유지', () {
      expect(pbx, contains('CODE_SIGN_STYLE = Automatic;'));
    });
  });

  group('Podfile·버전·비밀값 계약', () {
    test('Podfile: platform 13.0 = pbxproj 배포 타깃과 일치', () {
      final String podfile = _read(kPodfilePath);
      expect(podfile, contains("platform :ios, '13.0'"));
    });

    test('pubspec 버전 고정(수렴 PR 은 버전 불변 — 런북 §7)', () {
      final String pubspec = _read('pubspec.yaml');
      expect(pubspec, contains(kPinnedPubspecVersion),
          reason: '업로드용 release 커밋에서만 함께 갱신할 것');
    });

    test('.env·서명 비밀은 git 무시 대상이고 저장소에 실물이 없다', () {
      final String gitignore = _read('.gitignore');
      expect(gitignore, contains('.env'));
      expect(gitignore, contains('**/*.keystore'));
      // 서명·API 키 실물 금지(ios/ 아래 전수 스캔 — 확장자 기준).
      final List<String> leaked = Directory('ios')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((File f) => f.path)
          .where((String p) =>
              p.endsWith('.p8') ||
              p.endsWith('.p12') ||
              p.endsWith('.mobileprovision') ||
              p.endsWith('.cer') ||
              p.endsWith('GoogleService-Info.plist'))
          .toList();
      expect(leaked, isEmpty,
          reason: '인증서·프로비저닝·푸시 설정 파일은 커밋 금지(.gitignore 유지)');
    });
  });

  group('iOS 문서 정본 계약', () {
    test('정본 런북이 존재하고 핵심 게이트를 다룬다', () {
      final String runbook = _read(kRunbookPath);
      for (final String requiredSection in <String>[
        '번들 ID',
        'PrivacyInfo',
        'ITSAppUsesNonExemptEncryption',
        'App Privacy',
        '계정 삭제',
        'no-codesign',
        '처리 매트릭스',
      ]) {
        expect(runbook, contains(requiredSection),
            reason: '런북 필수 절 누락: $requiredSection');
      }
    });

    test('구식 문서는 정본과 충돌하지 않는다', () {
      // IOS_BUILD_PLAN.md(#23 초안)는 만들지 않는다 — 정본은 런북 하나.
      expect(File('docs/IOS_BUILD_PLAN.md').existsSync(), isFalse,
          reason: 'iOS 출시 문서 정본은 docs/IOS_RELEASE_RUNBOOK.md 하나로 수렴');
      // IOS_BUILD.md 는 런북으로 안내하는 스텁만 유지.
      final String stub = _read('docs/IOS_BUILD.md');
      expect(stub, contains('IOS_RELEASE_RUNBOOK.md'));
      expect(stub, isNot(contains('com.ssambership.ssambershipApp')),
          reason: '폐기된 번들 ID 가 문서에 남으면 안 된다');
    });
  });
}
