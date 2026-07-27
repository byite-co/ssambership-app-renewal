import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'individual_question_repository.dart';

/// IQ 첨부 Storage 서명 URL 백엔드 포트(P3-6).
///
/// ★ 질문방 AttachmentUrlResolver 패턴 재현(IQ 버킷은 다르다): 캐시/만료
///   로직은 [IqAttachmentUrlResolver] 가 갖고, Supabase 구체 호출은 이 포트
///   뒤로 숨긴다 → 테스트는 fake 포트 + 가짜 시계로 캐시·만료를 검증한다.
abstract class IqAttachmentUrlBackend {
  /// 캐시 키 분리용 현재 사용자 id(계정 전환 시 이전 사용자 캐시 미재사용).
  /// 미로그인이면 null.
  String? get currentUserId;

  /// storage_path → 서명 URL(만료 [expiresInSeconds]).
  Future<String> createSignedUrl(String storagePath, int expiresInSeconds);
}

/// IQ 첨부 표시용 서명 URL 리졸버 — 만료 전 재사용(메모리 캐시).
///
/// - 같은 storage_path 는 발급 URL 을 만료 전까지 재사용한다(리빌드마다
///   createSignedUrl 재요청하던 상세 화면의 낭비 제거).
/// - 캐시 키에 사용자 id 를 포함한다 — 계정이 바뀌면 이전 사용자 키로 발급한
///   URL 을 재사용하지 않는다(당사자 storage RLS 와 일관).
/// - [safetyMargin] 만큼 '일찍' 만료로 취급한다 — 만료 직전 URL 로 이미지
///   로드가 실패하는 경계를 피한다.
/// - 발급 실패는 캐시하지 않는다(성공 시에만 기록) — 다음 호출이 그대로 재시도.
class IqAttachmentUrlResolver {
  IqAttachmentUrlResolver(
    this._backend, {
    Duration ttl = const Duration(hours: 1),
    Duration safetyMargin = const Duration(seconds: 60),
    DateTime Function()? now,
  })  : _ttl = ttl,
        _safetyMargin = safetyMargin,
        _now = now ?? DateTime.now;

  /// 운영 기본 구현(Supabase Storage — IQ 첨부 버킷).
  factory IqAttachmentUrlResolver.supabase() =>
      IqAttachmentUrlResolver(const SupabaseIqAttachmentUrlBackend());

  final IqAttachmentUrlBackend _backend;
  final Duration _ttl;
  final Duration _safetyMargin;
  final DateTime Function() _now;

  final Map<String, _CachedUrl> _cache = <String, _CachedUrl>{};

  /// 서명 URL(만료 전이면 캐시 재사용). 만료(안전 여유 포함) 이후엔 재발급.
  Future<String> signedUrl(String storagePath) async {
    final String key = '${_backend.currentUserId ?? ''}::$storagePath';
    final _CachedUrl? cached = _cache[key];
    if (cached != null && _now().isBefore(cached.expiresAt)) {
      return cached.url;
    }
    final String url =
        await _backend.createSignedUrl(storagePath, _ttl.inSeconds);
    // 실제 만료(ttl)보다 safetyMargin 일찍 버린다. 실패 시 여기 도달하지 않아
    // 캐시가 오염되지 않는다(다음 호출이 재시도).
    _cache[key] = _CachedUrl(url, _now().add(_ttl - _safetyMargin));
    return url;
  }
}

class _CachedUrl {
  const _CachedUrl(this.url, this.expiresAt);
  final String url;
  final DateTime expiresAt;
}

/// Supabase Storage 백엔드(IQ 첨부 버킷 — 당사자 storage RLS).
class SupabaseIqAttachmentUrlBackend implements IqAttachmentUrlBackend {
  const SupabaseIqAttachmentUrlBackend();

  @override
  String? get currentUserId => SupabaseInit.clientOrNull?.auth.currentUser?.id;

  @override
  Future<String> createSignedUrl(
    String storagePath,
    int expiresInSeconds,
  ) async {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c.storage
        .from(IndividualQuestionRepository.attachmentBucket)
        .createSignedUrl(storagePath, expiresInSeconds);
  }
}
