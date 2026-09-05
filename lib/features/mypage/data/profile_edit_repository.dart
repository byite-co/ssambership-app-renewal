import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';

/// 프로필 수정(안전 필드만) — **서버 RPC 단일 경로**(웹/앱/DB 계약 수렴).
///
/// 구 경로(users 테이블 직접 UPDATE)는 폐기됐다. 판정(역할·계정 상태·길이)은
/// 전부 `api_app_v1.user_profile_update_self` 가 수행하고, 앱은 그 결과를
/// 그대로 따른다. ★ 역할(role)·이메일·id 등 시스템/민감 필드는 계약에 없다.
///
/// 정본 계약(staging 마이그레이션):
///   api_app_v1.user_profile_update_self(p_nickname text default null,
///     p_grade_level text default null) returns jsonb
///   성공: {ok:true, contract_version:1, nickname, grade_level, updated_at}
///   실패: raise exception 'CODE' — PostgrestException.message 가 코드로 시작.
///
/// 파라미터 의미(서버 정본):
/// - 파라미터 생략(null) = 기존 값 유지
/// - p_grade_level '' (빈 문자열) = NULL 로 비우기(학생 전용)
/// - 멘토는 p_grade_level 을 **아예 보내지 않는다**(보내면 GRADE_LEVEL_NOT_ALLOWED)
abstract class ProfileEditBackend {
  Future<Object?> rpc(String fn, Map<String, dynamic> params);
}

/// Supabase 백엔드 — ★ schema() 를 생략하면 public 으로 나가 함수를 찾지
/// 못한다(PGRST202). 게시판 작성 RPC 와 같은 api_app_v1 스키마다.
class SupabaseProfileEditBackend implements ProfileEditBackend {
  const SupabaseProfileEditBackend();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) =>
      _client.schema('api_app_v1').rpc(fn, params: params);
}

/// 서버 오류 코드 → 사용자용 한글 문구(코드·원문 비노출).
/// 계정 상태 문구는 커뮤니티/qna 매퍼와 동일 문장으로 통일한다.
String? profileUpdateErrorMessage(Object e) {
  final String? code = profileUpdateErrorCode(e);
  if (code == null) return null;
  switch (code) {
    case 'AUTH_REQUIRED':
      return '로그인이 필요해요.';
    case 'ROLE_NOT_ALLOWED':
      return '현재 회원 유형으로는 프로필을 수정할 수 없어요.';
    case 'ACCOUNT_BANNED':
    case 'ACCOUNT_SUSPENDED':
      return '계정 이용이 제한된 상태예요. 자세한 내용은 문의해 주세요.';
    case 'ACCOUNT_NOT_ACTIVE':
      return '현재 계정 상태에서는 이 기능을 사용할 수 없어요.';
    case 'ACCOUNT_DELETION_IN_PROGRESS':
      return '탈퇴 처리 중에는 프로필을 수정할 수 없어요.';
    case 'NICKNAME_REQUIRED':
      return '표시명을 입력해 주세요.';
    case 'NICKNAME_TOO_LONG':
      return '표시명은 30자 이내로 입력해 주세요.';
    case 'GRADE_LEVEL_NOT_ALLOWED':
      return '멘토 계정은 학년을 설정할 수 없어요.';
    case 'GRADE_LEVEL_TOO_LONG':
      return '학년은 20자 이내로 입력해 주세요.';
  }
  return null;
}

/// 예외에서 프로필 오류코드 토큰만 추출(대문자+밑줄, message 선두 일치).
/// PostgrestException 이 아니거나 코드 형태가 아니면 null.
String? profileUpdateErrorCode(Object e) {
  if (e is! PostgrestException) return null;
  final RegExpMatch? m =
      RegExp(r'^[A-Z][A-Z0-9_]+').firstMatch(e.message.trim());
  return m?.group(0);
}

/// 알려진 코드면 AppError(한글)로 변환, 아니면 원본 그대로(qna 매퍼와 동일 규약).
Object mapProfileUpdateError(Object e) {
  final String? msg = profileUpdateErrorMessage(e);
  return msg == null ? e : AppError(msg, cause: e);
}

class ProfileEditRepository {
  const ProfileEditRepository({ProfileEditBackend? backend})
      : _backendOverride = backend;

  final ProfileEditBackend? _backendOverride;

  ProfileEditBackend get _backend =>
      _backendOverride ?? const SupabaseProfileEditBackend();

  /// 표시명(nickname)·학년(grade_level) 갱신 — RPC 단일 경로.
  ///
  /// - [nickname] null = 유지(파라미터 미전송). 값이 있으면 항상 전송.
  /// - [gradeLevel] null = **파라미터 자체를 생략**(유지 — 멘토는 항상 이 경로).
  ///   '' = 비우기(학생 전용 — 서버가 NULL 로 저장), 값 = 그 값으로 저장.
  /// 성공 봉투(ok·contract_version) 를 strict 검증한다 — 계약 밖 응답을
  /// 성공으로 처리하지 않는다(fail-closed). 로컬 선반영 없음(호출부 규약).
  Future<void> updateProfile({String? nickname, String? gradeLevel}) async {
    final Map<String, dynamic> params = <String, dynamic>{
      if (nickname != null) 'p_nickname': nickname,
      if (gradeLevel != null) 'p_grade_level': gradeLevel,
    };
    if (params.isEmpty) return; // 바뀐 것 없음 — 호출 자체를 생략.
    final Object? data;
    try {
      data = await _backend.rpc('user_profile_update_self', params);
    } catch (e) {
      throw mapProfileUpdateError(e);
    }
    if (data is! Map || data['ok'] != true || data['contract_version'] != 1) {
      throw const AppError('프로필 저장 결과를 확인하지 못했어요. 다시 시도해 주세요.');
    }
  }
}
