import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'board_post_media_gateway.dart';

/// 게시글 이미지 Storage 백엔드 포트.
///
/// ★ 숏폼·IQ·질문방 URL 리졸버와 같은 '포트 + 실구현' 규약: 참조 파싱·TTL
///   캐시·single-flight 는 [CommunityPostImageUrlResolver] 가 갖고, Supabase
///   구체 호출은 이 포트 뒤로 숨긴다 → 테스트는 fake 포트 + 가짜 시계로
///   계약을 검증한다.
abstract class CommunityPostImageReadBackend {
  /// 캐시 키 분리용 현재 사용자 id(계정 전환 시 이전 사용자 캐시 미재사용).
  /// 게시글 이미지는 공개 열람(서버 `cpi_public_read` 가 anon·authenticated
  /// SELECT 허용 — 스테이징 실측)이라 비로그인 발급도 허용된다.
  String? get currentUserId;

  /// bucket 을 제외한 object path(`{uid}/{object}`) → 서명 URL 발급.
  Future<String> createSignedUrl(String objectPath, int expiresInSeconds);
}

/// 게시글 이미지 표시용 서명 URL 리졸버 — 짧은 TTL·메모리 캐시 전용.
///
/// 저장 정본(웹·앱 공통)은 `community-post-images/{uid}/{object}` 형태의
/// Storage 참조다(community_posts.image_urls 실값 실측). 버킷은 private 이고
/// 서버 SELECT 정책(`cpi_public_read`: anon·authenticated)이 열람 권한
/// 경계를 담당하므로, 앱은 서명 URL 발급으로만 읽는다 — 버킷 공개 전환도
/// 정책 변경도 하지 않는다.
///
/// - TTL(기본 10분)에서 [safetyMargin] 만큼 '일찍' 만료로 취급해 만료 직전
///   URL 재사용을 피한다 — 화면 재진입 시 만료된 URL 은 재사용되지 않는다.
/// - 캐시 키는 `currentUserId + ref` — 계정 전환 시 이전 사용자 캐시 미재사용.
/// - 발급 실패는 캐시하지 않는다(다음 호출이 재시도). 같은 키 동시 요청은
///   single-flight 로 합쳐 중복 발급을 막는다.
/// - 계약 밖 ref(다른 버킷·세그먼트 부족·traversal 등)는 발급을 시도하지
///   않고 null — 화면은 중립 플레이스홀더를 그린다.
///
/// ★ signed URL·query token·원문 ref·UID 를 로그·예외 문자열·화면에
///   절대 싣지 않는다. 실패는 null 로만 답한다(절대 throw 하지 않는다).
class CommunityPostImageUrlResolver {
  CommunityPostImageUrlResolver(
    this._backend, {
    Duration ttl = const Duration(minutes: 10),
    Duration safetyMargin = const Duration(seconds: 60),
    DateTime Function()? now,
  })  : _ttl = ttl,
        _safetyMargin = safetyMargin,
        _now = now ?? DateTime.now;

  /// 운영 기본 구현(Supabase Storage — private `community-post-images` 버킷).
  factory CommunityPostImageUrlResolver.supabase() =>
      CommunityPostImageUrlResolver(
          const SupabaseCommunityPostImageReadBackend());

  final CommunityPostImageReadBackend _backend;
  final Duration _ttl;
  final Duration _safetyMargin;
  final DateTime Function() _now;

  final Map<String, _CachedUrl> _cache = <String, _CachedUrl>{};
  final Map<String, Future<String>> _inFlight = <String, Future<String>>{};

  /// 정본 ref → 표시용 서명 URL. 실패·계약 밖 ref 는 null(throw 없음) —
  /// 한 장의 실패가 다른 이미지·본문 표시를 막지 않게 호출부는 장별로 부른다.
  Future<Uri?> resolve(String ref) async {
    final String? objectPath = _displayObjectPath(ref);
    if (objectPath == null) return null;
    final String key = '${_backend.currentUserId ?? ''}::$ref';
    try {
      final String signed = await _signedUrl(key, objectPath);
      final Uri? uri = Uri.tryParse(signed);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        return null;
      }
      return uri;
    } catch (_) {
      // 발급 실패 원문(URL·토큰·경로가 섞일 수 있음)은 밖으로 내보내지 않는다.
      return null;
    }
  }

  /// 서명 URL 발급 — 만료 전 캐시 재사용 + single-flight.
  Future<String> _signedUrl(String key, String objectPath) {
    final _CachedUrl? cached = _cache[key];
    if (cached != null && _now().isBefore(cached.expiresAt)) {
      return Future<String>.value(cached.url);
    }
    final Future<String>? running = _inFlight[key];
    if (running != null) return running; // 진행 중 요청에 합류(중복 발급 0)

    late final Future<String> request;
    request = () async {
      try {
        final String url =
            await _backend.createSignedUrl(objectPath, _ttl.inSeconds);
        // 실제 만료(ttl)보다 safetyMargin 일찍 버린다. 실패 시 여기 도달하지
        // 않아 캐시가 오염되지 않는다(다음 호출이 재시도).
        _cache[key] = _CachedUrl(url, _now().add(_ttl - _safetyMargin));
        return url;
      } finally {
        if (identical(_inFlight[key], request)) {
          _inFlight.remove(key);
        }
      }
    }();
    _inFlight[key] = request;
    return request;
  }

  /// 표시용 참조 파싱 — 쓰기 계약 파서([communityPostImageObjectPath]) 위에
  /// traversal·제어문자·query/fragment 거부를 더한다(표시 경로 안전 강화).
  String? _displayObjectPath(String ref) {
    final String raw = ref.trim();
    final String? path = communityPostImageObjectPath(raw);
    if (path == null) return null;
    if (path.contains('..')) return null;
    if (path.contains('?') || path.contains('#') || path.contains(r'\')) {
      return null;
    }
    for (final int code in path.codeUnits) {
      if (code < 0x20 || code == 0x7f) return null; // 제어문자
    }
    return path;
  }
}

class _CachedUrl {
  const _CachedUrl(this.url, this.expiresAt);
  final String url;
  final DateTime expiresAt;
}

/// Supabase Storage 백엔드(게시글 이미지 버킷 — private, 서버 `cpi_public_read`
/// SELECT 정책 하에서 서명 발급).
class SupabaseCommunityPostImageReadBackend
    implements CommunityPostImageReadBackend {
  const SupabaseCommunityPostImageReadBackend();

  @override
  String? get currentUserId => SupabaseInit.clientOrNull?.auth.currentUser?.id;

  @override
  Future<String> createSignedUrl(
    String objectPath,
    int expiresInSeconds,
  ) async {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c.storage
        .from(kCommunityPostImagesBucket)
        .createSignedUrl(objectPath, expiresInSeconds);
  }
}

/// 앱 전역 공유 리졸버 — 메모리 캐시를 상세 화면 인스턴스 간 공유한다
/// (같은 세션에서 상세 재진입 시 만료 전 서명 URL 재사용, 만료 후엔 재발급).
/// 테스트는 화면에 fake 리졸버를 직접 주입하므로 이 인스턴스를 건드리지 않는다.
final CommunityPostImageUrlResolver sharedCommunityPostImageUrlResolver =
    CommunityPostImageUrlResolver.supabase();
