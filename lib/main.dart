import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:webview_flutter/webview_flutter.dart';

import 'app/app.dart';
import 'core/auth/auth_service.dart';
import 'core/observability/crash_reporting.dart';
import 'core/supabase/supabase_client.dart';
import 'core/deeplink/deep_link_service.dart';
import 'core/version_gate/version_gate_controller.dart';
import 'core/web_bridge/web_session_hygiene.dart';

/// 진입점.
/// - .env 로드(없어도 앱은 구동) → Supabase 초기화(키 있으면) → 딥링크/푸시 자리 초기화.
/// - 어떤 단계가 실패해도 '빈 앱'은 켜진다(읽기 중심·Commerce-Zero).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 로드(자산). 없으면 무시하고 진행.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env 미존재 — 연결 없이 빈 앱만 구동.
  }

  // G3: 크래시 리포팅(Sentry)은 .env 직후 **가장 먼저** 기동한다 — 이후의
  // Supabase 초기화·인증 부팅·딥링크·버전 게이트에서 나는 예외까지 전역
  // 핸들러가 잡아야 하기 때문(리뷰 후속: 부팅 구간 관측 공백 제거).
  // SENTRY_DSN 없으면(개발·CI) appRunner 만 그대로 실행된다.
  await bootstrapCrashReporting(appRunner: () async {
    // Supabase 초기화(자격값이 있을 때만).
    await SupabaseInit.ensureInitialized();

    // WebView 쿠키 정리 구현 등록(로그아웃·계정 전환·숏폼 작성 화면 여닫이에서 호출).
    // 실기기 전용 플러그인이라 여기서 주입한다 — 테스트/미지원 플랫폼은 자동 no-op.
    WebSessionHygiene.register(() async {
      await WebViewCookieManager().clearCookies();
    });

    // 인증/세션 부팅: 세션 복원 + 프로필(role·계정상태·구독) 로드 + auth 변화 구독.
    await AuthService.instance.bootstrap();

    // 알림 딥링크 컨트롤러 초기화. ★ App-F0: OS 푸시(FCM)는 출시 범위가 아니라
    // 외부 payload 생산자를 붙이지 않는다 — Firebase 초기화·토큰 등록 0회.
    // 앱 내 알림함에서의 이동은 알림함 화면이 직접 라우팅한다.
    await DeepLinkService.instance.initialize();

    // 최소 지원 버전 게이트: runApp 전에 검사를 '시작'만 한다(await 하지 않음 —
    // 첫 프레임을 네트워크에 묶지 않는다). 셸(VersionGateShell)이 checking 동안
    // 진입을 보류하고, 결과(pass/forceUpdate/recommend/fetchFailed)에 따라 그린다.
    // anon RPC 라 로그인 전에도 동작한다. android/ios 외 플랫폼은 스스로 건너뛴다.
    unawaited(VersionGateController.instance.start());

    runApp(const SsambershipApp());
  });
}
