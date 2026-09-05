import 'package:flutter/material.dart';

import 'web_bridge.dart';

/// 화면용 웹 브릿지 동선 헬퍼 — 모든 관리/정보성 웹 링크 버튼이 여기만 호출한다(통일).
///
/// ★ Commerce-Zero: 앱은 결제하지 않는다. 웹을 열거나(설정 완료 시) 안내만 한다(미확정 시).
///   [bridge] 는 테스트 주입용(기본: 실제 WebBridge — WebBridgeConfig 사용).
/// ★ 구매 유도 헬퍼(구독 신청·캐시 충전)는 두지 않는다 — P0-3 死배선 정리(2026-07-12).
///   실수 재배선 방지를 위해 삭제됐으므로 되살리려면 정책 판단부터 확정할 것.

Future<void> openBillingManageWeb(BuildContext context,
    {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openBillingManage();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '결제·구독 관리는 웹에서 할 수 있어요. (준비 중)');
}

Future<void> openPayoutManageWeb(BuildContext context,
    {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openPayoutManage();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '정산 관리는 웹에서 할 수 있어요. (준비 중)');
}

Future<void> openProfileEditWeb(BuildContext context,
    {WebBridge? bridge}) async {
  final WebOpenResult r = await (bridge ?? WebBridge()).openProfileEdit();
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '프로필 편집은 웹에서 할 수 있어요. (준비 중)');
}

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

/// 개별질문 신규 등록 — 경계 확정(2026-08-05): 네이티브 등록 화면 진입 제거, 웹 전용.
/// [mentorId] 가 있으면 멘토 지정형 등록 라우트로 연결한다.
Future<void> openIqCreateWeb(BuildContext context,
    {String? mentorId, WebBridge? bridge}) async {
  final WebOpenResult r =
      await (bridge ?? WebBridge()).openIqCreate(mentorId: mentorId);
  if (r == WebOpenResult.opened || !context.mounted) return;
  _showNotice(context, r, '개별질문 등록은 웹에서 진행할 수 있어요. (준비 중)');
}

/// 안내 스낵바(미확정: 준비 중 / 실패: 재시도 안내). 호출부에서 mounted 확인 후 호출.
void _showNotice(
    BuildContext context, WebOpenResult result, String notConfiguredMsg) {
  final String msg = result == WebOpenResult.failed
      ? '웹 페이지를 열 수 없어요. 잠시 후 다시 시도해 주세요.'
      : notConfiguredMsg;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
