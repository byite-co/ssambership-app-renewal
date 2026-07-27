import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/web_bridge/web_session_hygiene.dart';

void main() {
  tearDown(WebSessionHygiene.resetForTest);

  test('등록된 cleaner 를 clear 가 호출한다(로그아웃·계정 전환 훅)', () async {
    int calls = 0;
    WebSessionHygiene.register(() async => calls++);
    await WebSessionHygiene.clear();
    await WebSessionHygiene.clear();
    expect(calls, 2);
  });

  test('미등록이면 no-op(테스트·미지원 플랫폼 안전)', () async {
    await WebSessionHygiene.clear(); // throw 없음
  });

  test('cleaner 예외는 삼켜 흐름을 막지 않는다', () async {
    WebSessionHygiene.register(() async => throw StateError('플러그인 미가용'));
    await WebSessionHygiene.clear(); // throw 없음
  });
}
