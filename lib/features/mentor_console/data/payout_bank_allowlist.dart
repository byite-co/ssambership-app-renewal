/// 정산 계좌 은행 allowlist 17종 — 정본은 DB F13 함수 본문
/// (`api_web_v1.mentor_payout_account_update_self`, 189 `+iM뱅크`)이고 웹
/// `MentorPayoutAccountPanel.tsx` BANK_OPTIONS 와 바이트 단위 동일 문자열이다.
/// 서버에 은행 목록 RPC 가 없어 앱이 복제한다 — 밖의 값은 서버가
/// `PAYOUT_BANK_NAME_INVALID` 로 거부하므로 목록이 어긋나도 잘못 저장되진 않는다.
const List<String> kPayoutBankAllowlist = <String>[
  'KB국민은행',
  '신한은행',
  '우리은행',
  '하나은행',
  'NH농협은행',
  'IBK기업은행',
  '카카오뱅크',
  '토스뱅크',
  '케이뱅크',
  'SC제일은행',
  '씨티은행',
  'KDB산업은행',
  '수협은행',
  '신협',
  '새마을금고',
  '우체국',
  'iM뱅크',
];

/// 계좌번호 형식(F13 서버 정규식 `^[0-9]{8,24}$` 미러 — 사전 안내용).
final RegExp kPayoutAccountNumberPattern = RegExp(r'^[0-9]{8,24}$');

/// 입력값 → 숫자만. 하이픈·공백은 제거한다(웹 `digitsOnly` 와 동일).
String payoutAccountDigits(String raw) => raw.replaceAll(RegExp(r'\D'), '');
