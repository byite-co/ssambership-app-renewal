import 'dart:math';

/// RFC 4122 v4 UUID(무작위) — 외부 패키지 없이 [Random.secure] 로 만든다.
///
/// 자금 RPC 의 멱등 키(`p_idempotency_key`)용. 시도 단위로 하나 만들고,
/// 같은 시도의 재시도에는 **같은 키**를 다시 보낸다(이중 차감 방지).
String uuidV4({Random? random}) {
  final Random rng = random ?? Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) b.write('-');
    b.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
