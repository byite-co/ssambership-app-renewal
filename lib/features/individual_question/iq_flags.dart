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
/// ★ 경계 확정(2026-08-05): 네이티브 등록 화면(IqCreateScreen) 진입은 production
///   그래프에서 제거됐다 — 이 플래그가 켜져도 CTA 는 **웹 등록 페이지**
///   (core/web_bridge)로만 연결된다. 조회·답변·첨부·첨삭은 플래그와 무관하게 유지.
/// ★ A안(2026-07) 유지 — 첫 스토어 제출 빌드는 기본 off. dev/내부 테스트는
///   `--dart-define=IQ_CREATE_ENABLED=true` 로 켠다(컴파일 타임 주입).
///   on 전환 게이트 = docs/PLAY_STORE_REVIEW_PLAN.md 의 결제 정책 검토 완료.
const bool kIndividualQuestionCreateEnabled =
    bool.fromEnvironment('IQ_CREATE_ENABLED', defaultValue: false);
