import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_post_image_url_resolver.dart';

/// 게시글 이미지 서명 URL 리졸버 — 참조 파싱·TTL 캐시·single-flight 계약.
/// Storage 를 실제로 호출하지 않는다(가짜 백엔드 + 가짜 시계).

const String _uid = 'c04a191c-fa59-49a7-8fa4-6819e65580fb';
const String _ref = 'community-post-images/$_uid/1234_a.png';

class _FakeBackend implements CommunityPostImageReadBackend {
  _FakeBackend({this.userId = 'viewer-1'});

  String? userId;
  Object? error;
  int calls = 0;
  String? lastPath;
  int? lastExpiresIn;
  String urlPrefix = 'https://signed.example/';
  Completer<String>? gate; // 지정 시 완료될 때까지 발급 대기(single-flight 검증)

  @override
  String? get currentUserId => userId;

  @override
  Future<String> createSignedUrl(String objectPath, int expiresInSeconds) {
    calls++;
    lastPath = objectPath;
    lastExpiresIn = expiresInSeconds;
    if (error != null) return Future<String>.error(error!);
    final Completer<String>? g = gate;
    if (g != null) return g.future;
    return Future<String>.value('$urlPrefix$objectPath?token=t$calls');
  }
}

void main() {
  group('참조 파싱 — 정본 ref 만 발급 대상', () {
    test('정본 ref → 버킷 접두사를 뗀 object path 로 발급한다', () async {
      final _FakeBackend backend = _FakeBackend();
      final CommunityPostImageUrlResolver resolver =
          CommunityPostImageUrlResolver(backend);
      final Uri? uri = await resolver.resolve(_ref);
      expect(uri, isNotNull);
      expect(backend.calls, 1);
      expect(backend.lastPath, '$_uid/1234_a.png');
      expect(backend.lastExpiresIn, const Duration(minutes: 10).inSeconds);
    });

    test('계약 밖 ref 는 발급을 시도하지 않고 null', () async {
      final _FakeBackend backend = _FakeBackend();
      final CommunityPostImageUrlResolver resolver =
          CommunityPostImageUrlResolver(backend);
      for (final String bad in <String>[
        '',
        'other-bucket/$_uid/a.png',
        'community-post-images/only-one-segment',
        'community-post-images/$_uid/',
        'community-post-images/$_uid/../secret.png',
        'community-post-images/$_uid/a.png?token=x',
        'community-post-images/$_uid/a.png#frag',
        'community-post-images/$_uid/a\\b.png',
        'http://evil/community-post-images/$_uid/a.png',
      ]) {
        expect(await resolver.resolve(bad), isNull, reason: bad);
      }
      expect(backend.calls, 0);
    });
  });

  group('실패 — throw 없이 null, 캐시 오염 없음', () {
    test('발급 실패는 null 로 답하고, 다음 호출이 재시도한다', () async {
      final _FakeBackend backend = _FakeBackend()..error = Exception('denied');
      final CommunityPostImageUrlResolver resolver =
          CommunityPostImageUrlResolver(backend);
      expect(await resolver.resolve(_ref), isNull);
      expect(backend.calls, 1);
      backend.error = null;
      expect(await resolver.resolve(_ref), isNotNull); // 실패 미캐시 — 재발급
      expect(backend.calls, 2);
    });

    test('http(s) 가 아닌 발급 결과는 null(신뢰하지 않는다)', () async {
      final _FakeBackend backend = _FakeBackend()..urlPrefix = 'file:///tmp/';
      final CommunityPostImageUrlResolver resolver =
          CommunityPostImageUrlResolver(backend);
      expect(await resolver.resolve(_ref), isNull);
    });
  });

  group('TTL 캐시 — 만료된 URL 은 재사용하지 않는다', () {
    test('만료 전 재호출은 캐시 재사용(발급 1회), 만료 후엔 재발급', () async {
      DateTime now = DateTime(2026, 8, 2, 12, 0, 0);
      final _FakeBackend backend = _FakeBackend();
      final CommunityPostImageUrlResolver resolver =
          CommunityPostImageUrlResolver(
        backend,
        ttl: const Duration(minutes: 10),
        safetyMargin: const Duration(seconds: 60),
        now: () => now,
      );

      final Uri? first = await resolver.resolve(_ref);
      expect(backend.calls, 1);

      // 만료 전(재진입 흉내) — 같은 URL 재사용, 발급 0회 추가.
      now = now.add(const Duration(minutes: 5));
      final Uri? again = await resolver.resolve(_ref);
      expect(backend.calls, 1);
      expect(again.toString(), first.toString());

      // safetyMargin 포함 만료 후(재진입 흉내) — 낡은 URL 을 재사용하지 않는다.
      now = now.add(const Duration(minutes: 5));
      final Uri? fresh = await resolver.resolve(_ref);
      expect(backend.calls, 2);
      expect(fresh.toString(), isNot(first.toString()));
    });

    test('계정 전환 시 이전 사용자 캐시를 재사용하지 않는다', () async {
      final _FakeBackend backend = _FakeBackend(userId: 'user-a');
      final CommunityPostImageUrlResolver resolver =
          CommunityPostImageUrlResolver(backend);
      await resolver.resolve(_ref);
      expect(backend.calls, 1);
      backend.userId = 'user-b';
      await resolver.resolve(_ref);
      expect(backend.calls, 2); // 키가 달라 새로 발급
    });
  });

  group('single-flight — 동시 요청 중복 발급 없음', () {
    test('같은 ref 동시 요청은 발급 1회로 합쳐진다', () async {
      final _FakeBackend backend = _FakeBackend()
        ..gate = Completer<String>();
      final CommunityPostImageUrlResolver resolver =
          CommunityPostImageUrlResolver(backend);

      final Future<Uri?> a = resolver.resolve(_ref);
      final Future<Uri?> b = resolver.resolve(_ref);
      backend.gate!.complete('https://signed.example/joined?token=1');
      final List<Uri?> got = await Future.wait(<Future<Uri?>>[a, b]);
      expect(backend.calls, 1);
      expect(got[0].toString(), got[1].toString());
    });
  });
}
