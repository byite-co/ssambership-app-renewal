import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/version_gate/version_gate_decision.dart';
import 'package:ssambership_app/core/version_gate/version_policy.dart';

import 'version_gate_fakes.dart';

/// decide — 순수 판정 함수 전수. ★ 비교는 정수 빌드번호로만 한다.
void main() {
  group('decide: 기본 판정', () {
    test('현재 스테이징 시드(min=1, latest=1)에서 빌드 1은 정상 통과', () {
      final VersionGateDecision d =
          decide(currentBuild: 1, policy: policyOf(min: 1, latest: 1));
      expect(d, isA<GatePass>());
    });

    test('최소 지원 빌드 미만(min=5, current=1)이면 강제 업데이트', () {
      final VersionGateDecision d =
          decide(currentBuild: 1, policy: policyOf(min: 5, latest: 5));
      expect(d, isA<GateForceUpdate>());
      expect((d as GateForceUpdate).policy.minSupportedBuild, 5);
    });

    test('최소는 충족하지만 최신이 더 높으면(min=1, latest=9) 권장 업데이트', () {
      final VersionGateDecision d =
          decide(currentBuild: 1, policy: policyOf(min: 1, latest: 9));
      expect(d, isA<GateRecommendUpdate>());
      expect((d as GateRecommendUpdate).policy.latestBuild, 9);
    });

    test('최신과 같으면 통과(권장 없음)', () {
      expect(decide(currentBuild: 9, policy: policyOf(min: 1, latest: 9)),
          isA<GatePass>());
    });
  });

  group('decide: 정수 비교 계약', () {
    test('빌드 9 vs min 10 → 강제 업데이트(정수 비교: 9 < 10)', () {
      // 문자열 비교였다면 '9' > '10' 으로 오판했을 케이스 — 정수라서 안전.
      expect(decide(currentBuild: 9, policy: policyOf(min: 10, latest: 10)),
          isA<GateForceUpdate>());
    });

    test('빌드 10 vs min 9 → 통과(정수 비교: 10 >= 9)', () {
      expect(decide(currentBuild: 10, policy: policyOf(min: 9, latest: 10)),
          isA<GatePass>());
    });

    test('latest 10 vs 현재 9 → 권장(정수 비교: 10 > 9)', () {
      expect(decide(currentBuild: 9, policy: policyOf(min: 1, latest: 10)),
          isA<GateRecommendUpdate>());
    });

    test('버전명 문자열은 판정에 절대 개입하지 않는다(표기 전용)', () {
      // minimumVersionName='1.10' 처럼 문자열 비교('1.10' < '1.9')로 오판할 수
      // 있는 값을 넣어도, decide 는 정수 빌드번호만 보므로 결과가 변하지 않는다.
      // (decide 시그니처 자체가 버전명을 받지 않는다 — 구조적 차단.)
      final VersionGateDecision d = decide(
        currentBuild: 19, // 앱 버전명이 '1.9' 인 빌드라고 가정
        policy: policyOf(min: 1, latest: 1, minimumVersionName: '1.10'),
      );
      expect(d, isA<GatePass>());
    });
  });

  group('decide: 알 수 없는 빌드번호(fail-open)', () {
    test('currentBuild=null 이면 min 이 높아도 차단하지 않는다', () {
      // 로컬 buildNumber 파싱 실패가 앱을 벽돌로 만들면 안 된다.
      expect(decide(currentBuild: null, policy: policyOf(min: 99, latest: 99)),
          isA<GatePass>());
    });
  });

  group('VersionPolicy.fromJson: 파싱 방어', () {
    test('정수 필드 정상 파싱', () {
      final VersionPolicy p = VersionPolicy.fromJson(<String, dynamic>{
        'platform': 'android',
        'min_supported_build': 5,
        'latest_build': 9,
        'minimum_version_name': '1.2.0',
        'store_url': 'https://play.google.com/store/apps/details?id=x',
        'message': '업데이트해 주세요.',
      });
      expect(p.minSupportedBuild, 5);
      expect(p.latestBuild, 9);
      expect(p.minimumVersionName, '1.2.0');
    });

    test('숫자 필드 누락/형 불일치는 1(비차단 기본값)로 — 파싱 실패가 앱을 잠그지 않는다', () {
      final VersionPolicy p = VersionPolicy.fromJson(<String, dynamic>{
        'platform': 'android',
        'min_supported_build': '1.10', // 버전명 문자열이 섞여 와도
        'latest_build': null,
      });
      expect(p.minSupportedBuild, 1); // 정수가 아니면 비차단 기본값
      expect(p.latestBuild, 1);
    });
  });
}
