# 전 기능 계약 수렴 프리플라이트 (앱) — 2026-08-04 세션

웹 저장소의 동명 문서(`ssambership_web/docs/audit/full_contract_convergence_preflight_20260804.md`)가
DB 실측·웹 인벤토리의 정본이다. 본 문서는 앱 측 기준점만 기록한다.

## 기준점

- 기본 브랜치: `master` @ `db20f21452c70273bcce9d8756f101e8e6ec1803` (알려진 기준과 일치)
- 작업 브랜치: `claude/ssambership-convergence-defect-closure-ckc2z2`
  (지시서의 `claude/full-contract-convergence-20260804` 대신 세션 지정 브랜치 사용 — 웹 문서 §1 참조)
- PR #41 (`1dc5e61`) 전체 병합 완료 — PR #38/#39/#40 개별 재병합 없음, 충돌 0
- **PR #41 실측 드리프트**: PR 설명은 Build 13(vc13)이나 HEAD 커밋은 vc13→**vc14** 재패키징
  (`Play Console rejected reused vc13`). pubspec 실측 `0.1.0+14`,
  `test/app/build_version_test.dart` 도 vc14 계약. 최종 버전 증가는 14→15 로 1회.

## PR #41 병합 후 확인 항목 (지시서 3.3)

| 항목 | 상태 |
|------|------|
| 앱 버전 | `0.1.0+14` (위 드리프트 — 코드 정본) |
| 게시판 direct INSERT 제거 | ✅ `api_app_v1.community_post_create` 단일 경로 |
| 게시판 update RPC | ✅ `api_app_v1.community_post_update` + strict 봉투 검증 |
| 이미지 resolver·목록·상세 배선 | ✅ `community_post_image_url_resolver.dart` + BoardPostCard/BoardDetailScreen |
| 질문방 `ACCOUNT_NOT_ACTIVE` 매핑 | ✅ qna_error_mapper + community_post_error_mapper |
| 잔액 소멸 동의 분기 | ✅ account_delete_screen (FORFEIT_CONSENT_REQUIRED/STALE) |
| 질문방 신고·차단 UI | ✅ room_safety_* |
| Firebase-free | ✅ 의존성 0 + 회귀 테스트 존재 |

## 앱 결함 (수렴 전 실측)

1. `profile_edit_repository.dart` — users 직접 UPDATE(nickname, grade_level) → M1 RPC 전환 대상
2. 멘토 찾기 — legacy RPC 3종(mentor_directory_list_v2 / mentor_profiles_for_directory_v2 /
   mentor_user_public_v2) 사용, full_name fallback 표시, 200명 상한, mentor_plans is_active 미필터
   (모델 기본값 true — 주석과 코드 불일치 실측)
3. 커뮤니티 읽기 — base table 직접 read, `deleted_at` 필터 부재 (soft-delete 노출)
4. 신고 target — 게시판 댓글 `comment` 전송(서버 allowlist 밖 → **현재 신고 실패**), 숏폼 글 `shortform`(모호)
5. IQ — Realtime 없음(one-shot fetch), 학생 후속 메시지 RPC(iq_append_message, 08-03 DB 적용) 미사용
6. 알림 — Realtime 없음, 서버 unread count 없음(페이지 내 카운트), 개별 읽음 direct UPDATE,
   딥링크 탭 수준만(상세 미연결)
7. 계정 삭제 — `p_cancelable_minutes`/`p_dry_run` 클라이언트 전송 (v2 전환 대상)

## 정상 확인 (보존 대상)

- 질문방 Realtime 3테이블 구독(thread_realtime.dart) + 낙관행 서버 교체(thread_messages_controller.dart)
- IQ 첨부 멱등 계약(40001 재시도·모호 결과 SELECT 수렴·등록 객체 자동삭제 금지)
- Commerce-Zero: 결제·충전·구독 진입점 0, commerce_policy.dart 게이트
- 버전 게이트: get_mobile_app_version_policy, min/latest 비교, fail-open(빌드번호 파싱 실패), 스토어 host allowlist
- web_bridge https·host allowlist, 알림 설정(행 없음=ON, optimistic rollback)
- 테스트 146파일, dart-define 모드: IQ_CREATE_ENABLED / SUBS_MANAGE_LINK_ENABLED /
  PAYOUT_MANAGE_LINK_ENABLED / WEB_BASE_URL

## 도구

Flutter SDK 는 이 환경에 없음 — 앱 analyze/test/AAB 는 설치 시도 후 불가 시 BLOCKED_ENV 기록.
