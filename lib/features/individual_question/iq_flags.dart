/// 개별질문(IQ) 기능 스위치.
///
/// ★ 스토어 정책 유의: 기충전 캐시를 앱 안에서 디지털 재화(개별질문)에 소비하는
///   것은 Google Play 결제 정책 검토 대상이다(docs/PLAY_STORE_REVIEW_PLAN.md).
///   조회·답변 확인은 소비가 아니므로 항상 유지한다.
library;

/// 개별질문 기능 전체 노출(목록·상세 포함).
const bool kIndividualQuestionEnabled = true;

/// 학생의 '새 개별질문 등록' CTA 노출.
///
/// ★ A-4a 개방(2026-09-05, 오너 결정 ②): 네이티브 등록 화면(IqCreateScreen)을
///   `/iq/new` 로 다시 연다. 등록 화면은 잔액을 먼저 보여주고 부족하면 "잔액이
///   부족해요" 사실 안내 + 등록 비활성까지만 — 충전 유도 0(Commerce-Zero).
///   릴리즈 워크플로는 dart-define 을 쓰지 않으므로 기본값을 on 으로 둔다.
///   내부 검증용 off 는 `--dart-define=IQ_CREATE_ENABLED=false`.
/// 조회·답변·첨부·첨삭은 플래그와 무관하게 유지.
const bool kIndividualQuestionCreateEnabled =
    bool.fromEnvironment('IQ_CREATE_ENABLED', defaultValue: true);
