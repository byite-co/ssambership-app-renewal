/// 커머스 제로 정책 — 결제 유도(스티어링) 단일 소스.
///
/// ★ 앱은 결제/구매를 유도하지 않는다(스토어 정책). 구독·충전의 '구매 유도' 진입점은
///   안내로 대체한다. 관리 링크(구독 관리·정산 관리)는 스토어 빌드에서 숨긴다
///   (각 플래그 dart-define 주입으로 가역 — 아래 참고).
///   정책이 바뀌면 [kInAppPaymentSteeringEnabled] 한 곳으로 재개 여부를 제어한다.
library;

/// 앱 내 결제 유도(구독·충전 '구매' 진입점) 노출 여부. false = 안내로 대체.
const bool kInAppPaymentSteeringEnabled = false;

/// '구독 관리 (웹)' 링크 노출 여부 — P0-3 옵션1 확정(2026-07).
///
/// ★ 스토어 빌드 기본 off: 구독 관리 웹(`/subscriptions`)은 결제 수단 변경 등
///   결제성 화면에 닿을 수 있어 Play 결제 정책 판단 확정 전까지 숨긴다.
///   dev/내부 테스트는 `--dart-define=SUBS_MANAGE_LINK_ENABLED=true`.
const bool kSubscriptionManageLinkEnabled =
    bool.fromEnvironment('SUBS_MANAGE_LINK_ENABLED', defaultValue: false);

/// 구독 관리 링크 off 시 대체 안내(웹 언급 없이 — 죽은 버튼·빈 공백 방지).
const String kSubscriptionManageNoticeText = '구독 변경·해지는 웹 계정에서 관리돼요';

/// '정산 관리 (웹)' 링크 노출 여부 — P0-3 잔존 처리(2026-07-12).
///
/// ★ 스토어 빌드 기본 off: 정산 관리 웹(`/mentor/payouts`)은 지급(payout) 관리라
///   소비자 결제와 성격이 다르지만, 결제 인접 링크로서 정책 판단 확정 전까지
///   구독 관리와 동일하게 숨긴다(2026-07-12 재판정).
///   dev/내부 테스트는 `--dart-define=PAYOUT_MANAGE_LINK_ENABLED=true`.
const bool kPayoutManageLinkEnabled =
    bool.fromEnvironment('PAYOUT_MANAGE_LINK_ENABLED', defaultValue: false);

/// 정산 관리 링크 off 시 대체 안내 — 사실 안내만(A-4a 이후 정산 계좌·요금제·내역은
/// 앱 정산 탭에 있다). 마이페이지 요약에서만 쓰고 정산 탭 본문에서는 표시하지 않는다.
const String kPayoutManageNoticeText = '정산 계좌·요금제·정산 내역은 정산 탭에서 볼 수 있어요';

/// 구독 유도 대체 안내(웹 언급 없이).
const String kSubscribeNoticeText = '구독 사용자 전용이에요';

/// 캐시 충전 유도 대체 안내(웹 언급 없이).
const String kRechargeNoticeText = '캐시 충전은 앱에서 지원하지 않아요';
