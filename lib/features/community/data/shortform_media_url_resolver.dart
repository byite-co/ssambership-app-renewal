import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';

/// 숏폼 미디어 Storage 백엔드 포트(App-SF1).
///
/// ★ IQ·질문방 URL 리졸버와 같은 '포트 + 실구현' 규약: 참조 파싱·TTL 캐시·
///   single-flight 는 [ShortformMediaUrlResolver] 가 갖고, Supabase 구체 호출은
///   이 포트 뒤로 숨긴다 → 테스트는 fake 포트 + 가짜 시계로 계약을 검증한다.
abstract class ShortformMediaBackend {
  /// 캐시 키 분리용 현재 사용자 id(계정 전환 시 이전 사용자 캐시 미재사용).
  /// 미로그인이면 null — 숏폼은 공개 열람이라 비로그인 발급도 허용된다
  /// (`sfv_public_read` 가 anon SELECT 를 허용하는 서버 정책과 일관).
  String? get currentUserId;

  /// bucket 을 제외한 object path(`{userId}/{objectName}`) → 서명 URL 발급.
  Future<String> createSignedUrl(String objectPath, int expiresInSeconds);
}

/// 해석 결과 상태 — 문자열 하나로 모든 상태를 뭉개지 않는다(§4-5).
enum ShortformMediaStatus {
  /// 저장값이 비어 있음(영상 없는 행). 실패가 아니므로 재시도 대상도 아니다.
  absent,

  /// 재생 가능한 절대 http(s) URL 로 수렴(정본 참조 서명 또는 legacy URL).
  resolved,

  /// 일시 실패(서명 발급 실패·백엔드 미초기화 등) — 수동 재시도 대상.
  failed,

  /// 참조 자체가 계약 위반(경로 형상 불일치·허용 외 스킴·traversal 등).
  /// 재시도해도 결과가 달라지지 않는다. ★ '영상 없음'으로 조용히 바꾸지
  /// 않는다 — 접근 권한 통제가 아니라 참조 무결성 판정이다(서버 정책이
  /// 실제 권한 경계를 담당).
  invalidReference,
}

/// 숏폼 미디어 해석 결과. ★ [toString] 에 URL·토큰을 싣지 않는다 — 서명
/// URL 이 로그·예외 문자열로 새는 것을 타입 차원에서 막는다(§4-4).
class ShortformMediaResolution {
  const ShortformMediaResolution._(this.status, this.uri);

  const ShortformMediaResolution.absent()
      : this._(ShortformMediaStatus.absent, null);

  const ShortformMediaResolution.failed()
      : this._(ShortformMediaStatus.failed, null);

  const ShortformMediaResolution.invalidReference()
      : this._(ShortformMediaStatus.invalidReference, null);

  ShortformMediaResolution.resolved(Uri playableUri)
      : this._(ShortformMediaStatus.resolved, playableUri);

  final ShortformMediaStatus status;

  /// [ShortformMediaStatus.resolved] 일 때만 non-null.
  final Uri? uri;

  @override
  String toString() => 'ShortformMediaResolution(${status.name})';
}

/// 숏폼 영상 표시용 서명 URL 리졸버 — 짧은 TTL·메모리 캐시 전용.
///
/// 저장 정본(웹 finalize)은 `shortform-videos/{userId}/{uuid}.{ext}` 형태의
/// Storage 참조이고, legacy 행만 http(s) 절대 URL 이다. 이 리졸버는
/// - 정본 참조를 엄격히 파싱해(§4-2) private 버킷의 짧은 TTL(기본 10분)
///   signed URL 을 발급하고 메모리에서만 캐시한다(§4-4).
/// - 캐시 키는 `currentUserId + storedRef` — 계정 전환 시 이전 사용자 키로
///   발급한 URL 을 재사용하지 않는다.
/// - [safetyMargin] 만큼 '일찍' 만료로 취급해 만료 직전 URL 로 재생 초기화가
///   실패하는 경계를 피한다. 발급 실패는 캐시하지 않는다(다음 호출이 재시도).
/// - 같은 키의 동시 요청은 single-flight 로 합쳐 중복 발급을 막고,
///   `forceRefresh` 는 세대(`_resolverRequestEpoch`)를 전진시켜 이전 in-flight
///   결과가 캐시에 반영되지 않게 한다(§4-4-A).
/// - legacy http(s) 절대 URL 은 발급 없이 그대로 통과시킨다(§4-3). 이 호환
///   분기는 새 외부 URL 을 DB 에 저장할 권한을 의미하지 않는다.
///
/// ★ signed URL·query token 을 로그·예외 문자열·DB·SharedPreferences 에
///   절대 넣지 않는다. 반환도 [ShortformMediaResolution] 상태 타입으로만 한다.
class ShortformMediaUrlResolver {
  ShortformMediaUrlResolver(
    this._backend, {
    Duration ttl = const Duration(minutes: 10),
    Duration safetyMargin = const Duration(seconds: 60),
    DateTime Function()? now,
  })  : _ttl = ttl,
        _safetyMargin = safetyMargin,
        _now = now ?? DateTime.now;

  /// 운영 기본 구현(Supabase Storage — private `shortform-videos` 버킷).
  factory ShortformMediaUrlResolver.supabase() =>
      ShortformMediaUrlResolver(const SupabaseShortformMediaBackend());

  /// 숏폼 영상 정본 버킷(웹 `SHORTFORM_VIDEO_BUCKET` 과 동일 리터럴).
  static const String videoBucket = 'shortform-videos';

  final ShortformMediaBackend _backend;
  final Duration _ttl;
  final Duration _safetyMargin;
  final DateTime Function() _now;

  final Map<String, _CachedUrl> _cache = <String, _CachedUrl>{};
  final Map<String, Future<String>> _inFlight = <String, Future<String>>{};

  /// 리졸버 요청 세대(§4-4-B resolverRequestEpoch) — 키별 최신 세대만 캐시에
  /// 기록할 수 있다. 화면 계층의 로드 세대(viewLoadGeneration)와는 다른 층.
  final Map<String, int> _resolverRequestEpoch = <String, int>{};

  /// 저장값(정본 Storage 참조 또는 legacy 절대 URL)을 재생 가능한 상태로
  /// 해석한다. 절대 throw 하지 않고 [ShortformMediaResolution] 로만 답한다.
  ///
  /// [forceRefresh] 가 true 면 캐시를 무시하고 정확히 1회 새로 발급하며,
  /// 진행 중이던 이전 요청의 결과는 캐시에 반영되지 않는다(§4-4-A).
  Future<ShortformMediaResolution> resolve(
    String? storedValue, {
    bool forceRefresh = false,
  }) async {
    final String raw = storedValue?.trim() ?? '';
    if (raw.isEmpty) return const ShortformMediaResolution.absent();

    final Uri? legacy = _legacyPlayableUrl(raw);
    if (legacy != null) {
      // legacy 절대 URL 은 발급 대상이 아니다(signer 0회, §4-3).
      return ShortformMediaResolution.resolved(legacy);
    }

    final String? objectPath = _canonicalObjectPath(raw);
    if (objectPath == null) {
      return const ShortformMediaResolution.invalidReference();
    }

    final String key = '${_backend.currentUserId ?? ''}::$raw';
    try {
      final String signed =
          await _signedUrl(key, objectPath, forceRefresh: forceRefresh);
      final Uri? uri = Uri.tryParse(signed);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        return const ShortformMediaResolution.failed();
      }
      return ShortformMediaResolution.resolved(uri);
    } catch (_) {
      // 발급 실패 원문(URL·토큰이 섞일 수 있음)은 상태에 싣지 않는다(§4-4).
      return const ShortformMediaResolution.failed();
    }
  }

  /// 서명 URL 발급 — 만료 전 캐시 재사용 + single-flight + forceRefresh 세대.
  Future<String> _signedUrl(
    String key,
    String objectPath, {
    required bool forceRefresh,
  }) {
    if (!forceRefresh) {
      final _CachedUrl? cached = _cache[key];
      if (cached != null && _now().isBefore(cached.expiresAt)) {
        return Future<String>.value(cached.url);
      }
      final Future<String>? running = _inFlight[key];
      if (running != null) return running; // 진행 중 요청에 합류(중복 발급 0)
    } else {
      // 명시적 무효화: 캐시 폐기 + 세대 전진. 이전 in-flight 는 자기 합류자
      // 에게만 결과를 주고, 늦게 도착해도 캐시에는 반영되지 않는다(§4-4-A).
      _cache.remove(key);
      _resolverRequestEpoch[key] = (_resolverRequestEpoch[key] ?? 0) + 1;
    }

    final int epoch = _resolverRequestEpoch[key] ??= 0;
    late final Future<String> request;
    request = () async {
      try {
        final String url =
            await _backend.createSignedUrl(objectPath, _ttl.inSeconds);
        if (_resolverRequestEpoch[key] == epoch) {
          // 실제 만료(ttl)보다 safetyMargin 일찍 버린다. 실패 시 여기 도달하지
          // 않아 캐시가 오염되지 않는다(다음 호출이 재시도).
          _cache[key] = _CachedUrl(url, _now().add(_ttl - _safetyMargin));
        }
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

  /// legacy 재생 허용 URL 검증(§4-3): http/https + 절대 URL + host 존재 +
  /// user-info 없음. `https:video.example.com/a.mp4`, `https:///a.mp4`,
  /// `https://user:pass@host/a.mp4` 는 모두 거부된다.
  Uri? _legacyPlayableUrl(String raw) {
    final Uri? u = Uri.tryParse(raw);
    if (u == null) return null;
    if (!(u.isScheme('http') || u.isScheme('https'))) return null;
    if (!u.isAbsolute) return null;
    if (u.host.isEmpty) return null;
    if (u.userInfo.isNotEmpty) return null;
    return u;
  }

  /// 정본 참조 파싱(§4-2): `shortform-videos/{userId}/{objectName}` 형상만
  /// 허용하고, Supabase 호출에 넘길 `{userId}/{objectName}` 을 돌려준다.
  /// 위반이면 null(→ invalidReference). 다른 bucket·중첩 경로·traversal·
  /// 제어문자·query·fragment·빈 확장자는 모두 거부한다.
  String? _canonicalObjectPath(String raw) {
    const String prefix = '$videoBucket/';
    if (!raw.startsWith(prefix)) return null;
    final String rest = raw.substring(prefix.length);
    final List<String> segments = rest.split('/');
    if (segments.length != 2) return null; // 중첩 경로·빈 경로 거부
    final String userId = segments[0];
    final String objectName = segments[1];
    if (!_uuidPattern.hasMatch(userId)) return null;
    if (!_validObjectName(objectName)) return null;
    return '$userId/$objectName';
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// 단일 파일명 검증: `.`/`..`/구분자/제어문자/query/fragment 금지,
  /// percent-decoding 후 traversal(`%2e%2e`, `%2f`, `%5c`)도 거부,
  /// 확장자·파일명은 비어 있지 않아야 한다.
  bool _validObjectName(String name) {
    if (name.isEmpty || name == '.' || name == '..') return false;
    if (name.contains('..')) return false;
    for (final int code in name.codeUnits) {
      if (code < 0x20 || code == 0x7f) return false; // 제어문자
    }
    if (name.contains('/') || name.contains(r'\')) return false;
    if (name.contains('?') || name.contains('#')) return false;
    String decoded = name;
    try {
      decoded = Uri.decodeComponent(name);
    } catch (_) {
      return false; // 손상된 percent-encoding
    }
    if (decoded != name &&
        (decoded.contains('/') ||
            decoded.contains(r'\') ||
            decoded.contains('..') ||
            decoded == '.')) {
      return false; // decoding 후 traversal
    }
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return false; // 빈 이름·빈 확장자
    return true;
  }
}

class _CachedUrl {
  const _CachedUrl(this.url, this.expiresAt);
  final String url;
  final DateTime expiresAt;
}

/// Supabase Storage 백엔드(숏폼 영상 버킷 — private, 서버 `sfv_public_read`
/// SELECT 정책 하에서 서명 발급).
class SupabaseShortformMediaBackend implements ShortformMediaBackend {
  const SupabaseShortformMediaBackend();

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
        .from(ShortformMediaUrlResolver.videoBucket)
        .createSignedUrl(objectPath, expiresInSeconds);
  }
}

/// 앱 전역 공유 리졸버 — 메모리 캐시를 상세 화면 인스턴스 간 공유한다
/// (같은 세션에서 상세 재진입 시 만료 전 서명 URL 재사용). 테스트는 화면에
/// fake 리졸버를 직접 주입하므로 이 인스턴스를 건드리지 않는다.
final ShortformMediaUrlResolver sharedShortformMediaUrlResolver =
    ShortformMediaUrlResolver.supabase();
