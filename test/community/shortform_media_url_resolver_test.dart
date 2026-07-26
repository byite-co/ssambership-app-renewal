import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/shortform_media_url_resolver.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// App-SF1 — 숏폼 미디어 리졸버 계약: 정본 참조 파싱(§4-2)·legacy 통과(§4-3)·
/// TTL/캐시/사용자 전환/single-flight/forceRefresh(§4-4·§4-4-A)·상태 구분(§4-5).
/// fake 백엔드 + 가짜 시계(주입형)로 실네트워크 없이 검증한다.
const String _uid = '3f2b8a4e-1c5d-4e6f-8a9b-0c1d2e3f4a5b';
const String _file = 'e0a1b2c3-d4e5-4f60-8a9b-1c2d3e4f5a6b.mp4';
const String _ref = 'shortform-videos/$_uid/$_file';

/// 즉시 응답 fake — 발급 횟수·마지막 path/TTL 기록, 1회성 오류 주입 가능.
class _FakeBackend implements ShortformMediaBackend {
  String? userId = 'user-1';
  int signCount = 0;
  String? lastObjectPath;
  int? lastExpiresIn;
  Object? nextError;

  @override
  String? get currentUserId => userId;

  @override
  Future<String> createSignedUrl(
      String objectPath, int expiresInSeconds) async {
    final Object? error = nextError;
    if (error != null) {
      nextError = null; // 1회성 실패 — 다음 호출은 성공(재시도 검증용).
      throw error;
    }
    signCount++;
    lastObjectPath = objectPath;
    lastExpiresIn = expiresInSeconds;
    return 'https://signed.example/$objectPath?token=t$signCount';
  }
}

/// 지연 응답 fake — 호출마다 Completer 를 쌓아 동시성 계약을 검증한다.
class _DeferredBackend implements ShortformMediaBackend {
  String? userId = 'user-1';
  int signCount = 0;
  final List<Completer<String>> pending = <Completer<String>>[];

  @override
  String? get currentUserId => userId;

  @override
  Future<String> createSignedUrl(String objectPath, int expiresInSeconds) {
    signCount++;
    final Completer<String> c = Completer<String>();
    pending.add(c);
    return c.future;
  }
}

void main() {
  group('정본 참조 → 서명 발급·TTL 캐시', () {
    test('bucket 제거 path 로 1회 발급 + TTL 초 전달 + resolved(https)', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      final ShortformMediaResolution res = await resolver.resolve(_ref);
      expect(res.status, ShortformMediaStatus.resolved);
      expect(res.uri!.isScheme('https'), isTrue);
      expect(backend.signCount, 1);
      expect(backend.lastObjectPath, '$_uid/$_file'); // bucket prefix 제거
      expect(backend.lastExpiresIn, 600); // 기본 TTL 10분
    });

    test('만료 전엔 캐시 재사용, 안전 여유(60초) 진입 후엔 재발급', () async {
      final _FakeBackend backend = _FakeBackend();
      DateTime now = DateTime(2026, 7, 26, 12);
      final ShortformMediaUrlResolver resolver = ShortformMediaUrlResolver(
        backend,
        now: () => now,
      );

      final Uri u1 = (await resolver.resolve(_ref)).uri!;
      expect(backend.signCount, 1);

      // 8분 59초 뒤 — 아직 (ttl 10분 - 여유 60초) 전 → 캐시 재사용.
      now = now.add(const Duration(minutes: 8, seconds: 59));
      final Uri u2 = (await resolver.resolve(_ref)).uri!;
      expect(backend.signCount, 1);
      expect(u2, u1);

      // 9분 30초 시점 — 실제 만료(10분) 전이지만 안전 여유(60초) 안 → 재발급.
      now = now.add(const Duration(seconds: 31));
      final Uri u3 = (await resolver.resolve(_ref)).uri!;
      expect(backend.signCount, 2);
      expect(u3, isNot(u1));

      // 재발급분은 다시 만료 전까지 재사용된다.
      final Uri u4 = (await resolver.resolve(_ref)).uri!;
      expect(backend.signCount, 2);
      expect(u4, u3);
    });

    test('사용자 전환 시 같은 ref 라도 재발급(캐시 키에 uid 포함)', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      final Uri u1 = (await resolver.resolve(_ref)).uri!;
      expect(backend.signCount, 1);

      backend.userId = 'user-2'; // 계정 전환
      final Uri u2 = (await resolver.resolve(_ref)).uri!;
      expect(backend.signCount, 2);
      expect(u2, isNot(u1));

      backend.userId = null; // 로그아웃(미로그인 키)도 별도 키
      await resolver.resolve(_ref);
      expect(backend.signCount, 3);
    });

    test('발급 실패는 failed 상태·미캐시 — 다음 호출이 재시도해 성공', () async {
      final _FakeBackend backend = _FakeBackend()
        ..nextError = const AppError('백엔드에 연결되어 있지 않아요.');
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      final ShortformMediaResolution failed = await resolver.resolve(_ref);
      expect(failed.status, ShortformMediaStatus.failed);
      expect(failed.uri, isNull);
      expect(backend.signCount, 0); // 실패 — 발급 기록 없음

      final ShortformMediaResolution ok = await resolver.resolve(_ref);
      expect(ok.status, ShortformMediaStatus.resolved);
      expect(backend.signCount, 1);

      // 성공분은 캐시 재사용(실패가 캐시를 오염시키지 않았다는 증거).
      final ShortformMediaResolution again = await resolver.resolve(_ref);
      expect(again.uri, ok.uri);
      expect(backend.signCount, 1);
    });

    test('forceRefresh 는 신선한 캐시도 무시하고 재발급·새 값 캐시', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      final Uri u1 = (await resolver.resolve(_ref)).uri!;
      expect(backend.signCount, 1);

      final Uri u2 = (await resolver.resolve(_ref, forceRefresh: true)).uri!;
      expect(backend.signCount, 2);
      expect(u2, isNot(u1));

      // 이후 일반 호출은 forceRefresh 가 캐시한 새 값을 재사용.
      final Uri u3 = (await resolver.resolve(_ref)).uri!;
      expect(u3, u2);
      expect(backend.signCount, 2);
    });
  });

  group('legacy 절대 URL(§4-3)', () {
    test('http/https 절대 URL 은 signer 0회로 그대로 통과', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      const String https = 'https://cdn.example.com/v.mp4';
      final ShortformMediaResolution r1 = await resolver.resolve(https);
      expect(r1.status, ShortformMediaStatus.resolved);
      expect(r1.uri, Uri.parse(https));

      const String http = 'http://cdn.example.com/v.mp4';
      final ShortformMediaResolution r2 = await resolver.resolve(http);
      expect(r2.status, ShortformMediaStatus.resolved);

      expect(backend.signCount, 0);
    });

    test('legacy 거부 세트 — host 없음·빈 host·user-info 포함', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      const List<String> rejected = <String>[
        'https:video.example.com/a.mp4', // scheme 만 있고 host 없음
        'https:///a.mp4', // 빈 host
        'https://user:pass@example.com/a.mp4', // user-info
      ];
      for (final String value in rejected) {
        final ShortformMediaResolution res = await resolver.resolve(value);
        expect(res.status, ShortformMediaStatus.invalidReference,
            reason: 'expected reject: $value');
        expect(res.uri, isNull);
      }
      expect(backend.signCount, 0);
    });

    test('허용 외 스킴(file/data/javascript/intent/ftp) 거부', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      const List<String> rejected = <String>[
        'file:///sdcard/a.mp4',
        'data:video/mp4;base64,AAAA',
        'javascript:alert(1)',
        'intent://play#Intent;scheme=https;end',
        'ftp://host/a.mp4',
      ];
      for (final String value in rejected) {
        final ShortformMediaResolution res = await resolver.resolve(value);
        expect(res.status, ShortformMediaStatus.invalidReference,
            reason: 'expected reject: $value');
      }
      expect(backend.signCount, 0);
    });
  });

  group('경로 형상 거부 세트(§4-2)', () {
    test('지시서 필수 거부 5종 — signer 0회 + invalidReference', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      const List<String> rejected = <String>[
        'shortform-videos/$_uid/a/b.mp4', // segment 3개(중첩 경로)
        'shortform-videos/not-a-uuid/a.mp4', // 첫 segment UUID 아님
        'shortform-videos/$_uid/a', // 확장자 없음
        'shortform-videos/$_uid/%2e%2e%2fx.mp4', // decoding 후 traversal
        'shortform-thumbnails/$_uid/a.jpg', // 다른 bucket
      ];
      for (final String value in rejected) {
        final ShortformMediaResolution res = await resolver.resolve(value);
        expect(res.status, ShortformMediaStatus.invalidReference,
            reason: 'expected reject: $value');
      }
      expect(backend.signCount, 0);
    });

    test('추가 형상 거부 — traversal·제어문자·query·fragment·빈 파일명 등', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      const List<String> rejected = <String>[
        'shortform-videos/', // path 없음
        'shortform-videos/$_uid', // 파일명 없음
        'shortform-videos/$_uid/', // 빈 파일명
        'shortform-videos/$_uid/..', // 상위 참조
        'shortform-videos/$_uid/.', // 현재 참조
        'shortform-videos/$_uid/a..b.mp4', // '..' 포함
        'shortform-videos/$_uid/.mp4', // 빈 이름(확장자만)
        'shortform-videos/$_uid/a.', // 빈 확장자
        'shortform-videos/$_uid/a.mp4?x=1', // query
        'shortform-videos/$_uid/a.mp4#f', // fragment
        'shortform-videos/$_uid/a\u0000b.mp4', // 제어문자(NUL)
        'shortform-videos/$_uid/a\nb.mp4', // 제어문자(개행)
        'shortform-videos/$_uid/a\\b.mp4', // 역슬래시
        'shortform-videos/$_uid/%2fetc.mp4', // decoding 후 슬래시
        'shortform-videos-evil/$_uid/a.mp4', // bucket 유사 접두
        'shortform-videos/$_uid/$_uid/a.mp4', // 중첩 경로 변형
      ];
      for (final String value in rejected) {
        final ShortformMediaResolution res = await resolver.resolve(value);
        expect(res.status, ShortformMediaStatus.invalidReference,
            reason: 'expected reject: $value');
      }
      expect(backend.signCount, 0);
    });

    test('빈 값·공백은 absent(실패 아님)·signer 0회', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      expect(
          (await resolver.resolve(null)).status, ShortformMediaStatus.absent);
      expect((await resolver.resolve('')).status, ShortformMediaStatus.absent);
      expect(
          (await resolver.resolve('   ')).status, ShortformMediaStatus.absent);
      expect(backend.signCount, 0);
    });
  });

  group('동시성 — single-flight × forceRefresh(§4-4-A)', () {
    test('동일 ref 동시 호출(forceRefresh=false) → signer 정확히 1회 합류', () async {
      final _DeferredBackend backend = _DeferredBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      final Future<ShortformMediaResolution> f1 = resolver.resolve(_ref);
      final Future<ShortformMediaResolution> f2 = resolver.resolve(_ref);
      expect(backend.signCount, 1); // 두 번째 호출은 in-flight 에 합류

      backend.pending[0].complete('https://signed.example/a?token=t1');
      final ShortformMediaResolution r1 = await f1;
      final ShortformMediaResolution r2 = await f2;
      expect(r1.uri, r2.uri);
      expect(backend.signCount, 1);
    });

    test('in-flight 중 forceRefresh=true → 신규 발급 정확히 1회 + 이전 결과 미캐시', () async {
      final _DeferredBackend backend = _DeferredBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      final Future<ShortformMediaResolution> f1 = resolver.resolve(_ref);
      expect(backend.signCount, 1);

      // forceRefresh — 진행 중 요청에 합류하지 않고 새 발급을 정확히 1회 생성.
      final Future<ShortformMediaResolution> f2 =
          resolver.resolve(_ref, forceRefresh: true);
      expect(backend.signCount, 2);

      // 신규(f2) 결과가 먼저 도착 → 캐시에는 이 값이 남아야 한다.
      backend.pending[1].complete('https://signed.example/a?token=new');
      final ShortformMediaResolution r2 = await f2;
      expect(r2.uri!.queryParameters['token'], 'new');

      // 이전 in-flight(f1) 결과가 '이후' 도착 — 자기 합류자에게는 전달되지만
      // 캐시에는 반영되지 않는다(§4-4-A).
      backend.pending[0].complete('https://signed.example/a?token=old');
      final ShortformMediaResolution r1 = await f1;
      expect(r1.uri!.queryParameters['token'], 'old');

      // 캐시 확인: 일반 호출이 신규 값을 재사용하고 발급 수는 그대로 2회.
      final ShortformMediaResolution r3 = await resolver.resolve(_ref);
      expect(r3.uri!.queryParameters['token'], 'new');
      expect(backend.signCount, 2);
    });
  });

  group('비노출 계약(§4-4)', () {
    test('결과 toString 에 서명 URL·token 이 노출되지 않는다', () async {
      final _FakeBackend backend = _FakeBackend();
      final ShortformMediaUrlResolver resolver =
          ShortformMediaUrlResolver(backend);

      final ShortformMediaResolution ok = await resolver.resolve(_ref);
      expect(ok.status, ShortformMediaStatus.resolved);
      expect(ok.toString(), isNot(contains('token')));
      expect(ok.toString(), isNot(contains('signed.example')));

      backend.nextError = Exception('http://leak.example/?token=SECRET');
      final ShortformMediaResolution failed =
          await resolver.resolve(_ref, forceRefresh: true);
      expect(failed.status, ShortformMediaStatus.failed);
      expect(failed.toString(), isNot(contains('SECRET')));
      expect(failed.toString(), isNot(contains('token')));
    });
  });
}
