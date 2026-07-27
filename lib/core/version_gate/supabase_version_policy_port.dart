import '../../shared/errors/app_error.dart';
import '../supabase/supabase_client.dart';
import 'version_gate_ports.dart';
import 'version_policy.dart';

/// Supabase RPC 구현 — `get_mobile_app_version_policy(p_platform)`.
///
/// EXECUTE 권한이 anon 에도 있어 로그인 전(스플래시)에도 동작한다.
/// 클라이언트 미초기화(clientOrNull == null)는 조회 실패로 취급한다
/// (컨트롤러가 '재시도' 상태로 표시 — 강제 업데이트로 오판하지 않는다).
class SupabaseVersionPolicyPort implements VersionPolicyPort {
  const SupabaseVersionPolicyPort();

  @override
  Future<VersionPolicy> fetch(String platform) async {
    final client = SupabaseInit.clientOrNull;
    if (client == null) {
      // 원문 비노출 규약: 화면에는 한글 안내만(friendly_error.dart 참고).
      throw const AppError('버전 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
    final dynamic data = await client.rpc(
      'get_mobile_app_version_policy',
      params: <String, dynamic>{'p_platform': platform},
    );
    if (data is Map<String, dynamic>) return VersionPolicy.fromJson(data);
    if (data is Map) {
      return VersionPolicy.fromJson(Map<String, dynamic>.from(data));
    }
    throw const AppError('버전 정보를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
  }
}
