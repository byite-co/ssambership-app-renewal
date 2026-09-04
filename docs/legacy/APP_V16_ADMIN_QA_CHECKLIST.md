# v16 관리자 통합 QA 체크리스트

> 상태: **서버측 행동 검증 PASS(§1.5) + ADMIN_QA_READY_NOT_EXECUTED(§2)** —
> 관리자 권한 경계는 staging DB 에서 rollback-only fixture 로 직접 실행해 검증 완료(§1.5).
> 관리자 계정 실로그인이 필요한 화면·웹 교차 항목(§2)만 미실행으로 남는다.

## 1. 정적 검증(이번 세션 코드 레벨 확인 — 완료)

- **관리자 로그인 정책**: `AuthService.computeAccess` 가 admin 역할을 **차단**한다
  (이 앱은 학생·멘토 전용 — `auth_service.dart`, `test/auth/auth_access_test.dart` 고정).
- **관리자 기능 누출 0**: 앱에 moderation/blind/신고 처리 UI 없음. 리뷰 moderation 필드
  (`is_hidden/is_blinded/moderation_state/moderated_*`)를 쓰는 코드 0
  (유일한 reviews 접근은 읽기 전용 집계 1곳 — `mentor_directory_repository.dart`).
- **블라인드 리뷰 미노출**: 통계 집계 쿼리가 `moderation_state='visible' AND
  is_hidden=false AND is_blinded=false` 필터를 서버 RLS 와 이중으로 적용.
- **보호필드 전송 0**: 서버 트리거(`reviews_enforce_update`)가 최종 방어 —
  앱은 리뷰 UPDATE 경로 자체가 없다.
- **민감 서류 URL**: 멘토 승인 서류 등은 앱 화면에 노출 경로 없음(관리자 웹 전용).
  실행 QA 에서 admin 계정으로 재확인할 것.

## 1.5 서버측 행동 검증 (2026-07-21 staging 실행 — 전부 PASS)

> 방식: staging(`lbeqxarxothkmzqvpudy`) 에서 MCP execute_sql 단일 트랜잭션,
> fixture 계정 4종(admin/mentor/student×2) + 리뷰 2건 생성 후
> `request.jwt.claims` + `set local role authenticated` 로 각 역할을 시뮬레이션.
> 마지막에 무조건 `raise exception` 으로 트랜잭션 전체를 중단시켜 **잔존 데이터 0**
> (실행 후 baseline 재조회로 fixture 사용자/리뷰/신고/오브젝트 0건 확인).
> 판정은 예외 문구만이 아니라 **row_count 를 함께 단언**한다(아래 A5 참고).

- [x] **A1** 관리자 리뷰 블라인드(1행) → 일반 사용자 조회 0건, 관리자 조회 1건
- [x] **A2** 관리자가 rating 등 보호필드 변경 시도 → `reviews: protected columns are immutable`
- [x] **A3** 관리자가 mentor_reply 변경 시도 → `reviews: admin must not change mentor reply fields`
- [x] **A4** 비관리자 언블라인드 시도 → RLS 0행(블라인드 유지)
- [x] **A5** 멘토 답글 1회 성공(1행) → 2회 시도 `mentor reply already set (one-time only)`,
      moderation 필드 시도 `mentor must not change moderation fields`, 최종 답글 = 첫 답글 유지
- [x] **A6** 신고(content_reports): 신고자 본인 조회 1건·상태 변경 0행, 타 사용자 조회 0건,
      관리자 조회 1건·상태 변경 1행
- [x] **A7** student-id-images(비공개 버킷): 소유자 조회 1건, 타 사용자 0건, 관리자 1건

**검증 중 확인된 서버 동작(결함 아님·기록)**: 리뷰가 블라인드되면 멘토 SELECT 정책이
없어(`public_visible` 은 비블라인드만, `admin` 은 관리자만) 멘토 본인의 UPDATE(답글 포함)도
RLS 에서 0행이 된다 — 블라인드된 리뷰에는 멘토가 답글을 달 수 없다는 의도된 격리로 판단.
앱은 블라인드 리뷰를 아예 렌더하지 않으므로 클라이언트 영향 없음. 최초 결합 fixture 가
이 상태에서 A5 를 실행해 오탐(FAIL)을 냈고, 답글 시나리오를 비블라인드 리뷰로 분리 +
row_count 단언 추가로 수정했다.

## 2. 실행 QA (관리자 계정 필요 — 웹 관리자 화면 + 앱 교차)

- [ ] 관리자 계정으로 앱 로그인 시도 → 차단 화면(관리자는 웹 사용 안내), 크래시 0
- [ ] 웹에서 리뷰 blind 처리 → 앱 멘토 통계에서 즉시 제외되는지
- [ ] 웹에서 리뷰 blind 해제 → 앱 통계 복귀
- [ ] 신고된 게시글/댓글 숨김 처리 → 앱 커뮤니티 목록 미노출
- [ ] 사용자 suspended(+해제 시각) 처리 → 앱 차단 화면 + 해제 예정일 표기
- [ ] banned 처리 → 앱 영구 차단 문구
- [ ] 탈퇴 job locked/purging 계정 → 앱 진입 차단(재시도 아님 문구)
- [ ] 멘토 미승인 계정 질문 시도 → MENTOR_NOT_APPROVED 안내
- [ ] 관리자 웹의 서류 검토 URL 이 앱 어디에도 렌더되지 않는지(딥링크 포함)
