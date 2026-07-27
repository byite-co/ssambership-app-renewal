import 'package:ssambership_app/core/version_gate/version_gate_ports.dart';
import 'package:ssambership_app/core/version_gate/version_policy.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 실제 Supabase/PackageInfo 없이 주입할 가짜 포트(호출 기록만 — mocktail 미사용).

/// 가짜 버전 정책 포트. [failing]=true 면 조회 실패를 흉내낸다(재시도 상태 유도).
class FakeVersionPolicyPort implements VersionPolicyPort {
  FakeVersionPolicyPort({required this.policy, this.failing = false});

  VersionPolicy policy;
  bool failing;

  int fetchCount = 0;
  final List<String> sentPlatforms = <String>[];

  @override
  Future<VersionPolicy> fetch(String platform) async {
    fetchCount++;
    sentPlatforms.add(platform);
    if (failing) {
      throw const AppError('버전 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
    return policy;
  }
}

/// 테스트용 정책 빌더(기본: 비차단 — min=1, latest=1).
VersionPolicy policyOf({
  String platform = 'android',
  int min = 1,
  int latest = 1,
  String minimumVersionName = '',
  String storeUrl = '',
  String message = '',
}) {
  return VersionPolicy(
    platform: platform,
    minSupportedBuild: min,
    latestBuild: latest,
    minimumVersionName: minimumVersionName,
    storeUrl: storeUrl,
    message: message,
  );
}
