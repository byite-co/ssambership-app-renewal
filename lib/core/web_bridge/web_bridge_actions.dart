import 'package:flutter/material.dart';

import 'web_bridge.dart';

/// 화면용 웹 브릿지 동선 헬퍼 — 정보 페이지·본인인증·회원 탈퇴 폴백만 남는다(A-4b ⑩).
///
/// [bridge] 는 테스트 주입용(기본: 실제 WebBridge — WebBridgeConfig 사용).
/// ★ 구독·해지·환불·정산·요금제·프로필·개별질문 헬퍼는 삭제됐다 — 앱이 직접 처리한다.

Future<void> openTermsWeb(BuildContext context, {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openTerms();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '이용약관은 웹에서 확인할 수 있어요. (준비 중)');
}

Future<void> openPrivacyWeb(BuildContext context, {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openPrivacy();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '개인정보처리방침은 웹에서 확인할 수 있어요. (준비 중)');
}

Future<void> openSupportWeb(BuildContext context, {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openSupport();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '고객지원은 웹에서 확인할 수 있어요. (준비 중)');
}

Future<void> openReviewsWeb(BuildContext context, {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openReviews();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '리뷰는 웹에서 확인할 수 있어요. (준비 중)');
}

/// 본인인증(웹 위임) — A-4b 이후에도 남는 웹 진입 둘 중 하나(다른 하나는 충전 안내).
Future<void> openIdentityVerifyWeb(BuildContext context,
    {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openIdentityVerify();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '본인인증은 웹에서 할 수 있어요. (준비 중)');
}

Future<void> openAccountDeleteWeb(BuildContext context,
    {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openAccountDelete();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '회원 탈퇴는 웹에서 진행돼요. (준비 중)');
}

/// 안내 스낵바(미확정: 준비 중 / 실패: 재시도 안내). 호출부에서 mounted 확인 후 호출.
void _showNotice(
    BuildContext context, WebOpenResult result, String notConfiguredMsg) {
  final String msg = result == WebOpenResult.failed
      ? '웹 페이지를 열 수 없어요. 잠시 후 다시 시도해 주세요.'
      : notConfiguredMsg;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
