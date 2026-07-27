# 앱 ↔ Supabase 데이터/유저플로우 구조 결함 검토 (2026-07-27)

`SUPABASE_SQL_AUDIT_2026-07.md`(경로 전수조사)의 후속 — 수집한 경로 위에서
**누락·충돌·오경로**를 깊게 검토한 결과. DB 함수 본문(pg_get_functiondef)과
앱 코드를 계약 단위로 대조했고, 운영 데이터(잡/outbox 실측 행)도 확인했다.

표기: 🔴 플로우가 실제로 끊기거나 잘못 감 · 🟠 조건부 오동작/충돌 · 🟡 잠재 결함(현재는 우연히 동작)

---

## 🔴 1. 구독 자격 정의 불일치 — 앱 `{active, cancel_scheduled}` vs 서버 `active` 단독

앱의 자격 정본은 `cancel_scheduled`(해지 예약, 잔여기간 유효)를 포함한다
(`lib/core/entitlement/subscription_status.dart:19` — "오너 확정 2" 주석,
`entitlement.dart`, `subscription_summary.dart` 공유). 그러나 **서버의 모든 게이트는
`status='active'`만** 구독으로 인정한다:

- `qna_create_question_thread` / `qt_direct_write_guard`: `active` 구독이 없으면
  **무료 질문 경로로 폴백**한다. cancel_scheduled 학생이 질문을 만들면
  ① 가입 7일 이내면 무료 질문권을 몰래 소모(`used_free_quota=true`),
  ② 7일이 지났으면 `FREE_QUOTA_EXPIRED`로 질문 자체가 거절된다.
  → **잔여 기간이 남은 유료 구독자가 질문을 못 하거나 무료권을 오소모**한다.
- `get_weekly_question_usage`: `active`만 조회 → cancel_scheduled 는 limit=0,
  can_ask=false. 앱의 사전검사(`question_room_read_repository.dart:88`)와
  마이페이지 구독 카드 사용량 표시가 모두 0으로 나온다.
- `get_mentor_student_nicknames`: `active` 구독 또는 방 존재 — 방이 있으면 완화되나 기준은 동일하게 어긋남.

앱은 "구독 중" UI(무료 CTA 숨김, 질문방 진입)를 보여주는데 서버는 무료 사용자로
취급하는 **이중 정의**다. 서버 게이트 3곳의 상태 집합을 `('active','cancel_scheduled')`
로 넓히거나, 앱 정본에서 cancel_scheduled 를 빼는 양자택일이 필요하다(전자가 주석의
"오너 확정"과 부합).

## 🔴 2. 워커/스케줄러 부재 — 서버 사가·outbox·정산 파이프라인이 모두 막다른 길

실측: **pg_cron·pg_net 미설치, Edge Function 0개**, 'scheduler' Supabase 프로젝트는
INACTIVE. 즉 DB에 준비된 워커용 RPC(claim/advance/reclaim 계열)를 **호출하는 주체가
어디에도 없다**. 그 결과:

- **계정삭제 사가 정지**: 앱은 `account_deletion_request_self`로 잡을 만들고
  (`account_deletion_jobs`에 pending 1건 실재) 이후 상태만 폴링한다. 잡을 전진시킬
  `account_deletion_claim`/`advance` 호출자가 없어 **탈퇴가 영구 pending** —
  개인정보 파기 시한 관점의 컴플라이언스 리스크.
- **알림 전달 정지**: `notification_outbox` 14건 전원 pending, `notification_deliveries`
  0행. 인앱 알림함(notifications 직접 insert)은 동작하지만 푸시 전달 단계는 미가동.
  앱 쪽도 `register_device_token` 미배선(`lib/core/push/`에 포트 정의만, device_tokens 0행)
  — **푸시가 서버·앱 양쪽에서 이중으로 끊겨 있음**.
- **멘토 정산 요약 공백**: `refresh_subscription_settlement_items` 호출 주체 없음 →
  `subscription_settlement_items` 0행 → 멘토 마이페이지 정산 카드
  (`mypage_repository.dart:168`)가 항상 비어 있다.
- **IQ 에스크로 잔류**: answered 후 학생이 확정(release)하지 않으면 자동 release 가
  없고(멘토는 회수 수단 없음), open 질문이 `expires_at`을 지나도 자동 refund 가 없다
  (학생 수동 refund 만 가능). → **캐시가 무기한 홀드될 수 있는 상태 기계**
  (통상 'N일 후 자동 확정' 크론이 담당할 몫이 비어 있음).

## 🔴 3. 개별질문(IQ) 데드락 — `answered` 상태에서 학생 refund 불가 + 자동 종결 부재

`refund_individual_question`은 `('escrowed','open','assigned','claimed')`에서만 환불을
허용하고, `release_individual_question_payout`은 `answered`에서만 지급을 허용한다.
2와 결합하면: 멘토가 답변한 뒤 학생이 아무 행동도 안 하면 **그 돈은 어느 쪽으로도
영원히 이동 불가**(환불 불가·지급 보류). 앱 UI가 확정을 유도해도 강제 수단이 없다.
자동 확정(worker) 또는 관리자 종결 경로가 계약상 필요하다.

## 🟠 4. 멘토 디렉터리가 미승인·정지 멘토를 그대로 노출 → 막다른 CTA

`mentor_directory_list_v2`는 `users.role='mentor'` 전원을 반환한다 —
`mentor_profiles.verification_status`·`users.status`(banned/suspended) 필터가 없고,
앱(`mentor_directory_repository.dart`, `mentors_screen.dart`)도 걸러내지 않는다
(`isVerified`는 뱃지 표시에만 사용). 반면 질문 생성·IQ claim 은
`individual_question_user_is_approved_mentor()`로 승인 멘토만 통과시킨다.
→ 학생이 미승인/정지 멘토 상세까지 들어가 질문을 시도하면 그제야
`MENTOR_NOT_APPROVED`로 거절되는 **발견-경로와 실행-경로의 게이트 불일치**.
(승인 시점에야 `mp_seed_default_plans_on_approval`로 플랜이 생기므로 가격 없는
카드가 노출되는 부수 효과도 동일 원인.)

## 🟠 5. 정지(suspended) 사용자 가드 비대칭 — 스레드 생성만 막고 대화는 못 막음

- 생성: `qna_create_question_thread`/`qt_direct_write_guard`는 banned+suspended 모두 차단.
- 이후: `qna_append_message`·`qna_register_attachment`는 **banned 만** 차단 —
  suspended 사용자가 기존 스레드에서 메시지·첨부를 계속 보낼 수 있다.
- `user_blocks` 검사도 생성 시 1회뿐 — 스레드 생성 후 차단해도 기존 스레드 대화는 계속된다
  (IQ 쪽 `answer_individual_question`·`iqm` 계열도 차단 검사 없음).

의도가 "정지=새 활동만 금지"라면 문서화가 필요하고, 아니라면 append/register에 동일
가드를 넣어야 한다.

## 🟠 6. 무료 질문권 한도의 삼중 정의 (7회 vs 15회 vs 문서)

- DB 강제(정본): RPC와 `check_free_question_usage_limits` 트리거 모두 **총 7회**·멘토당 3회·가입 후 7일.
- `free_question_usage` 테이블 comment 는 "**학생 전체 15회**·멘토당 3회"로 문서화 — DB 자체 문서와 코드가 불일치.
- 별개로 `fqu_insert_own` INSERT 정책이 열려 있어 클라이언트가 임의 사용 행을 직접
  삽입할 수 있다(RPC 경유가 정본인데 직접 경로가 병존). 이득은 없지만(자기 질문권
  소진) 사용량 집계의 무결성 구멍이다.

## 🟠 7. legacy RLS 정책이 실효 접근 범위를 확장 — 최악 사례는 qual=true

RLS 는 OR 결합이라 구(舊) 정책이 남아 있으면 신 정책의 제한이 무효화된다. 실측 qual:

- `custom_order_messages` · "누구나 메시지 읽기" · **qual=`true`, role={public}** →
  로그인한 누구나(정책상 anon 포함) **남의 맞춤의뢰 1:1 채팅 전체를 읽을 수 있다**.
  앱은 이 테이블을 읽지 않지만 PostgREST API 로는 열려 있는 실제 노출 경로다.
- `custom_order_deliverables` "누구나 납품 읽기", `custom_request_applications`
  "누구나 지원서 읽기" 등 동일 패턴 다수(전수 목록은 감사 문서 §6·§7 참고).
- 커뮤니티 계열(`community_posts`·`favorites`·`post_reactions`)의 구정책은 신정책과
  범위가 거의 같아 실해는 없으나 정리 대상.

## 🟡 8. notifications — RLS 정책·RPC·앱이 서로 다른 컬럼 집합을 본다

수신자 판별 컬럼이 7개(user_id, recipient_id, student_id, mentor_id, target_user_id,
owner_id, recipient_user_id) 공존하는데:

- RLS(select/update)는 **recipient_user_id 를 빼고** 6컬럼 OR,
- `mark_all_notifications_read`는 7컬럼 OR,
- 정본 쓰기(`record_domain_notification`)는 recipient_user_id + user_id 미러,
- 앱 `markRead`(`notifications_repository.dart:144`)는 **user_id 단독** eq.

현재는 user_id 미러 덕에 전부 동작하지만(실측 user_id null 0행), recipient_user_id 만
채우는 쓰기 경로가 하나라도 생기면 그 알림은 **앱에 보이지만 읽음 처리 실패**
(RLS update 는 통과해도 앱 필터 불일치) 또는 아예 안 보이는(정책 누락) 상태가 된다.
정책에 recipient_user_id 추가 + 컬럼 통폐합이 필요하다.

## 🟡 9. 차단 관리 화면의 표시명 경로가 구조적으로 사문화

`UserBlocksRepository.myBlockedUsers()`(`user_blocks_repository.dart:74-93`)가 차단한
상대의 이름을 `users` 테이블에서 읽지만, `users` SELECT RLS 는 본인+관리자뿐이라
**항상 0행** → 모든 차단 사용자가 '사용자'로 표시된다. 에러가 아닌 빈 결과라 앱의
폴백도 이를 결함으로 감지하지 못한다. (닉네임 공개 조회는
`get_mentor_student_nicknames`처럼 위생 RPC 로 뚫는 것이 기존 패턴.)

## 🟡 10. 방(mentor_student_rooms) 생성 경로가 앱 밖에만 존재

방 INSERT 정책 없음(서버 전용) + 구독·결제·충전·출금 전부 웹 전용(Commerce-Zero,
`entitlement.dart:23`) → 앱 단독 신규 사용자는 방이 없어 무료 질문 CTA 가
`roomMissing`으로 영구 비활성(`free_question_entry.dart:69` — WAITING_SERVER_GATE 로
문서화된 의도적 게이트). 결함이라기보다 **앱 핵심 플로우의 시작점이 외부 시스템
가용성에 전적으로 의존**한다는 구조 리스크로 기록한다. 웹 게이트 다운 시 앱은
질문 생성이 전면 불가하며 앱 내 안내 외 대체 경로가 없다.

---

## 검토했고 이상 없음(정합 확인 목록)

- **27개 RPC 전부 파라미터명·타입·반환 형태가 앱 파서와 일치** (qna 6종, IQ 7종,
  계정삭제 4종, 디렉터리 3종, 알림 1종, 조회수 2종, 버전 1종, 기타). 특히
  `create_individual_question_as_student`(direct=서버 가격표/open=클라 금액),
  `add_individual_question_attachment`(멱등 on-conflict + message 소속 검증),
  `qna_register_attachment`(경로 접두사=room/thread + storage owner 검증)의 방어 계약은 견고.
- **Realtime**: 앱 구독 3테이블(thread_id/id 필터) = publication 등록 3테이블, RLS 통과 행만 수신.
- **댓글 이원화**: 앱 payload(board→`comments{post_id,author_id,content}`,
  shortform→`community_comments{post_type,post_id,author_id,body,status}`)가
  `comments_write_guard`/`cc_write_guard`의 보호필드 계약과 정확히 맞물림. 모델은
  content/body 양쪽 폴백으로 읽어 브리지 행도 안전.
- **에스크로 원장**: hold/release/refund 가 idempotency_key(`iq_refund:`/`iq_payout:`)
  상호 배타 검사로 이중지급·이중환불을 차단(§3의 '갇힘'은 별개 문제).
- **첨부 보상삭제**: 업로드 후 등록 실패 시 `qra_storage_delete_unregistered_owner`/
  `iqa_storage_delete_unregistered_owner` 정책으로 본인·미등록 객체만 삭제 — 앱 보상 로직과 일치.
- **가입 동기화**: `handle_new_auth_user`(role 화이트리스트 student/mentor, admin 봉쇄)
  ↔ 앱 로그인 후 role 읽기 경로 정합. reviews 집계 컬럼(moderation_state 등) 실재 확인.

## 우선순위 제안

| 순위 | 항목 | 방향 |
|---|---|---|
| 1 | §1 cancel_scheduled | 서버 게이트 3곳 상태 집합 확장(마이그레이션 1건) |
| 2 | §2·§3 워커 부재 | 스케줄러 1개(외부 크론→RPC 호출)로 삭제 사가·outbox·자동확정 일괄 해소 |
| 3 | §7 qual=true 정책 | legacy 정책 DROP(특히 custom_order_messages/deliverables/applications) |
| 4 | §4 디렉터리 노출 | `mentor_directory_list_v2`에 approved+active 필터 추가 |
| 5 | §5·§6·§8·§9 | 가드 대칭화·한도 문서 정정·notifications 정책 보강·차단목록 위생 RPC |
