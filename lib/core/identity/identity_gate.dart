import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 본인인증 게이트 플래그 — 웹 `IDENTITY_GATE_ENABLED` 와 같은 이름·같은 판정.
///
/// 웹(`lib/identity/identityGateFlag.ts`)은 서버 전용 env 라 앱이 원격으로 읽을 수
/// 없다. 앱은 `.env` 의 같은 키를 읽고 `'true'` 일 때만 ON 이다(미설정·그 외 = OFF).
/// DB 에는 가드가 없으므로(DB-4 §6-1) **웹 배포값과 앱 빌드값을 함께 맞춘다.**
///
/// 게이트 ON 이면 자금 진입점(구독 결제)에서 `users.identity_verified_at` 을 읽어
/// 미인증 학생을 웹 본인인증으로 보낸다. 판독 실패는 fail-closed(미인증 취급).
class IdentityGate {
  IdentityGate._();

  /// 테스트 주입(null = `.env` 판정).
  @visibleForTesting
  static bool? debugOverride;

  static bool get isEnabled {
    final bool? o = debugOverride;
    if (o != null) return o;
    return (dotenv.maybeGet('IDENTITY_GATE_ENABLED') ?? '').trim() == 'true';
  }
}
