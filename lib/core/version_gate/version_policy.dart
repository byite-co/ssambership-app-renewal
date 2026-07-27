/// 서버 RPC `get_mobile_app_version_policy` 응답 모델.
///
/// ★ 비교 계약: 버전 판정은 **정수 빌드번호**([minSupportedBuild]/[latestBuild])로만
///   한다. [minimumVersionName] 은 화면 표기용 문자열일 뿐 — '1.10' vs '1.9' 같은
///   문자열 비교 오판이 구조적으로 불가능하도록, 이 모델은 버전명 비교 API 를
///   아예 제공하지 않는다.
library;

class VersionPolicy {
  const VersionPolicy({
    required this.platform,
    required this.minSupportedBuild,
    required this.latestBuild,
    this.minimumVersionName = '',
    this.storeUrl = '',
    this.message = '',
  });

  /// 'android' | 'ios'.
  final String platform;

  /// 이 빌드번호 미만이면 강제 업데이트(정수 비교 전용).
  final int minSupportedBuild;

  /// 스토어 최신 빌드번호. 현재 빌드보다 크면 권장 업데이트(정수 비교 전용).
  final int latestBuild;

  /// 화면 표기용 버전명 — 비교에 절대 사용하지 않는다.
  final String minimumVersionName;

  /// 스토어 URL(서버 검증됨). 앱에서 열기 전 반드시 재검증한다(store_url_policy).
  final String storeUrl;

  /// 서버가 내려주는 안내 문구(없으면 빈 문자열 — 앱 기본 문구 사용).
  final String message;

  /// RPC jsonb 응답 파싱. 숫자 필드가 없거나 형이 어긋나면 1(비차단 기본값)로
  /// 간주한다 — 정책 파싱 실패가 앱을 잠그면 안 된다(서버의 '정책 없음' 기본값과 동일).
  factory VersionPolicy.fromJson(Map<String, dynamic> json) {
    return VersionPolicy(
      platform: _asString(json['platform']),
      minSupportedBuild: _asInt(json['min_supported_build'], fallback: 1),
      latestBuild: _asInt(json['latest_build'], fallback: 1),
      minimumVersionName: _asString(json['minimum_version_name']),
      storeUrl: _asString(json['store_url']),
      message: _asString(json['message']),
    );
  }

  static int _asInt(Object? v, {required int fallback}) {
    if (v is int) return v;
    // 문자열 버전명('1.10' 등)은 여기서 정수가 되지 못하고 기본값으로 떨어진다 —
    // 버전명 문자열이 비교 경로에 섞여 들어올 길을 차단.
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String _asString(Object? v) => v is String ? v : '';
}
