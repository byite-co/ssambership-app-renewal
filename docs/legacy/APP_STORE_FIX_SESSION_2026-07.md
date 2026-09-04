# 스토어 심사 수정 세션 플랜 (P0 · P1) — 2026-07

> `ssambership_app` v0.1.0+1 최초심사 제출 대비 수정 세션 정의서.
> 근거: `docs/APP_STORE_REVIEW_VERIFICATION_2026-07`(사전검증) + 코드 직접 확인.
> 이 문서는 **수정 세션의 단일 작업 목록**이다. 각 항목은 독립 배치로 처리하고,
> 완료 시 `상태`를 `[x]` 로 바꾸고 커밋 해시를 적는다.

## 범위·원칙 (수정 세션 그라운드 룰)

- **Commerce-Zero 불변:** 어떤 수정도 앱 내 가격 노출·구매 CTA·인앱 결제를 새로 만들지 않는다.
- **격리:** 앱 코드는 `ssambership_app`, 웹/법무/콘솔 작업은 담당 표기로 분리한다. 앱 세션은 웹 레포를 건드리지 않는다.
- **날조 금지:** 미확정 값(가격·URL·법적 문구)은 만들지 않는다. 없으면 안내 폴백을 유지한다.
- **표시 규칙:** 화면에 내부 DB명·UUID·영문 코드·딥링크 경로 노출 금지(기존 규약 유지).
- **담당 분류:** `앱`(이 레포 코드) · `웹`(ssambership_web) · `콘솔`(Play/App Store Connect) · `사람`(키스토어·법무·계정 등 수작업).

## 우선순위 요약

| ID | 항목 | 담당 | 스토어 축 | 상태 |
|----|------|:---:|-----------|:---:|
| P0-1 | 법적 고지(약관·개인정보) "초안" 해소 | 웹·사람 | Play/Apple 공통 | [ ] |
| P0-2 | 미성년자 보호·연령등급 처리 | 웹·앱·콘솔 | Kids/Families | [ ] |
| P0-3 | iOS UGC(1.2): 댓글 신고 + 게시 전 EULA 게이트 | 앱 | Apple 1.2 / Play UGC | [x] 배치1 |
| P0-4 | 심사용 데모계정 + 심사노트(멀티플랫폼·삭제경로) | 사람·콘솔 | Apple 2.1 / Play 접근 | [ ] |
| P1-5 | Android 릴리즈 서명 최종 확인 | 사람 | Play 무결성 | [ ] |
| P1-6 | Data Safety 양식 + 계정삭제 URL 등록 | 콘솔 | Play Data Safety | [ ] 문서초안은 #28로 완료, 콘솔 제출 잔여 |
| P1-7 | 번들ID 단일 확정 + iOS 표시명 통일 | 앱·사람 | 메타데이터 정합 | [x] 배치1 (com.ssambership.app 확정) |
| P1-8 | 스토어 빌드 플래그 무주입 재확인(가드) | 앱 | Commerce-Zero 유지 | [x] 가드 기존존재 |
| P1-9 | 죽은 커머스 코드 삭제 | 앱 | 재위반 방지 | [x] 배치1 |

> **배치 1(앱 코드) 구현 완료 — 2026-07-14.** P0-3·P1-9·P1-7(표시명)·P1-8(가드 확인). 상세는 문서 하단 "배치 1 구현 기록" 참조.

---

# P0 — 반려 직결 (제출 전 필수)

## P0-1 · 법적 고지(약관·개인정보) "초안" 배너 해소  ‹담당: 웹 · 사람(법무)›

**문제.** 앱은 `web_bridge`로 웹 `/legal/terms`·`/legal/privacy`를 연다. 두 페이지는 실존하나 `PolicyDraftBanner`("초안/안내 초안")가 붙어 있고, 실제 수집항목·보유기간·제3자 제공 고지가 미완이다. 약관 본문은 4개 불릿 수준으로 최초심사에는 불충분.

**근거.**
- 앱 링크: `lib/core/web_bridge/web_bridge_config.dart` `termsPath='/legal/terms'`, `privacyPath='/legal/privacy'`.
- 웹: `app/(public)/legal/terms/page.tsx`, `app/(public)/legal/privacy/page.tsx` → `PolicyDraftBanner` 노출.

**조치.**
1. (웹·법무) 약관·개인정보처리방침 **정식본** 작성 — 최소: 수집 개인정보 항목(이메일·이름/닉네임·학년·사진/첨부), 이용목적, 보유·파기(익명화 후 거래기록 보존), 제3자 제공/처리위탁(Supabase·토스), 이용자 권리, 문의처.
2. (웹) `PolicyDraftBanner` 제거, 시행일자 명기.
3. (콘솔) 개인정보처리방침 URL을 Play Console·App Store Connect에 등록.

**수용기준.** 두 페이지에 초안 배너 없음 · 시행일 표기 · 수집/보유/제3자 항목 명시 · 콘솔에 정책 URL 등록 완료.

**앱 측 확인.** 앱 코드 변경 없음(링크만 유지). 링크가 운영 도메인으로 정상 열리는지 스모크만 수행.

---

## P0-2 · 미성년자 보호 · 연령등급 처리  ‹담당: 웹 · 앱 · 콘솔›

**문제.** 학생 대상 교육 서비스로 **미성년(14세 미만 포함) 이용 가능성**이 높다. 웹 `/legal/minor-consent`(14세 미만 보호자 동의)는 **정책 문구만 있고 검증 플로우 미배선**("백엔드·법무 확정 후 연결"). Apple Kids/Google Families 및 개인정보보호법(만14세 미만 법정대리인 동의) 리스크.

**근거.**
- 웹: `app/(public)/legal/minor-consent/page.tsx`(초안 플레이스홀더), `users.grade_level` 컬럼 존재.
- 앱: 인앱 가입 없음(가입=웹). 앱은 연령 게이트 없음.

**조치(택1 후 실행).**
- **옵션 A(권장·안전):** 서비스 대상을 **만 14세 이상**으로 정책 확정 → 가입(웹)에 연령 확인, 연령등급 문진을 그에 맞게 작성. 앱은 별도 아동 기능 없음을 유지.
- **옵션 B:** 14세 미만 허용 시 → (웹) 법정대리인 동의 플로우 **실제 배선**, (콘솔) Apple Kids Category / Google Families 정책 준수(광고·데이터 수집 제약), 앱 데이터수집 최소화 재점검.
1. (콘솔) **연령등급 설문 정확 작성** — UGC(커뮤니티) 존재를 반영.
2. (앱, 옵션 B 시) 필요 시 온보딩에 대상연령 안내.

**수용기준.** 대상연령 정책 문서 확정 · 연령등급 문진이 실제 기능(UGC 포함)과 일치 · (옵션 B면) 보호자 동의 플로우 동작.

---

## P0-3 · iOS UGC(1.2): 댓글 신고 경로 + 게시 전 EULA 동의 게이트  ‹담당: 앱›

**문제.** Apple 1.2/Play UGC는 (a)필터 (b)신고+조치 (c)차단 (d)공개연락처 + **EULA 동의**를 요구한다. 현재:
- 차단은 강력(피드 필터 포함) ✅
- 게시글·숏폼 신고 작동 ✅ / **댓글 신고 경로 없음(차단만)** ❌
- **최초 게시 전 약관/금칙 콘텐츠 동의 게이트 없음** ❌
- 클라이언트 사전 필터 없음(즉시 게시)

**근거.**
- 신고 UI/사유: `lib/features/community/ui/widgets/report_sheet.dart`(reasons: inappropriate/spam/external_contact/copyright/etc), 저장 `lib/features/community/data/community_write_repository.dart` `report()`(→ `content_reports`, status `pending`).
- 신고 호출부: `board_detail_screen.dart`(community_post), `shortform_detail_screen.dart`(shortform). **댓글은 없음** — `lib/features/community/ui/widgets/comment_tile.dart` 팝업메뉴에 '차단'만 있고 '신고' 없음.
- 게시 무게이트: `board_write_screen.dart`(제목/본문 비어있음만 검증, 힌트 텍스트 "커뮤니티 가이드에 맞게 작성해 주세요."만), `community_write_repository.dart` `createPost()` `status='published'` 즉시 공개, `addComment()` 즉시.

**조치(앱 코드).**
1. **댓글 신고 추가:** `comment_tile.dart` 팝업메뉴에 '신고' 항목 추가 → 기존 `showReportSheet()` 재사용 → `report(targetType: 'community_comment', targetId: <commentId>)` 호출. (질문방/개별질문 UGC도 동일 패턴 검토 — 최소 커뮤니티 3종 신고 일원화.)
2. **게시 전 콘텐츠 정책 동의 게이트:** 최초 작성 진입 시 1회 동의 — "타인을 비방/불법/음란 콘텐츠 게시 금지, 위반 시 삭제·제재" 요지의 동의 체크 + 약관 링크. `SharedPreferences` 등에 동의 플래그 저장(재노출 방지). 게시글·댓글·(향후 업로드) 공통 진입에 적용.
3. **신고 후 즉시 숨김(선택·권장):** 신고한 사용자에게는 해당 콘텐츠를 로컬에서 즉시 가림(차단 필터와 동일 메커니즘 확장) — Apple '신고에 대한 조치' 신호 강화.

**수용기준.** 댓글에서 신고 가능(→ content_reports 적재) · 최초 게시 전 동의 게이트 1회 노출·저장 · 위젯 테스트로 신고 다이얼로그·게이트 노출 검증.

**주의.** 서버 측 조치(검수·제재)는 웹/관리자 콘솔 소관 — 앱은 신고 접수·차단·게이트까지. `docs/UGC_MODERATION_PROCESS.md`(미작성) 작성 권장.

---

## P0-4 · 심사용 데모계정 + 심사노트  ‹담당: 사람 · 콘솔›

**문제.** 인앱 가입·비밀번호 재설정이 없어(가입=웹) 리뷰어가 자력으로 계정을 만들 수 없다. 또한 계정삭제가 외부 브라우저로 이동하고, 커머스가 웹으로 나가므로 **오해 소지**가 있다.

**근거.**
- 로그인: `lib/features/auth/login_screen.dart`(이메일+비번 단독, 가입 안내 텍스트만), 비밀번호 재설정 코드 없음.
- 계정삭제: `settings_section.dart` 회원 탈퇴 → `openAccountDeleteWeb` → 웹 `/account/delete`.
- 커머스 유입 표식: `web_bridge.dart` 각 URL에 `src=app` 부착.

**조치.**
1. (사람) **학생·멘토 테스트 계정** 생성(학생은 열람 가능한 구독·질문방 데이터, 멘토는 질문방+정산 화면 확인 가능 데이터).
2. (콘솔) App Store Connect **App Review 정보**·Play Console **앱 액세스**에 계정 등록.
3. (콘솔) **심사노트** 작성:
   - "웹에서 구입한 구독을 열람하는 **멀티플랫폼 서비스 컴패니언**(App Store 3.1.3(b))이며, 앱 내 결제·가격·구매 CTA 없음."
   - 멘토 '정산 관리'는 **소비자 결제가 아닌 정산(출금)** 화면임을 명시.
   - **계정삭제 경로**: 로그인 → 마이페이지 → 설정 → '회원 탈퇴' → 웹 삭제 완결. (발견 경로 캡처 첨부 권장.)

**수용기준.** 두 콘솔에 유효 데모계정 등록 · 심사노트에 멀티플랫폼·정산·삭제경로 3점 기재.

---

# P1 — 강력 권장 (제출 품질/무결성)

## P1-5 · Android 릴리즈 서명 최종 확인  ‹담당: 사람›

**문제.** `key.properties` 부재 시 **debug 서명으로 폴백**한다(빌드는 유지되나 스토어 업로드 부적격).

**근거.** `android/app/build.gradle.kts` — `hasReleaseKeystore` 없으면 `signingConfigs.getByName("debug")`.

**조치.** (사람) keytool로 릴리즈 키스토어 생성 → `android/key.properties` 작성(커밋 금지, `.gitignore` 확인) → Play App Signing 등록 → AAB가 **릴리즈 키 서명**인지 확인(`flutter build appbundle` 후 서명 검증).

**수용기준.** 업로드 AAB가 debug 서명이 아님 확인 · 키/비밀번호 미커밋.

---

## P1-6 · Data Safety 양식 + 계정삭제 URL 등록  ‹담당: 콘솔›

**문제.** ~~`docs/DATA_SAFETY_FORM.md` 미작성~~(→ **초안 작성 완료** — PR #28, 2026-07-16 머지: 수집 항목별 코드 근거·콘솔 입력 체크리스트 포함), Play Data Safety/Apple 영양성분표는 여전히 미제출(콘솔 작업 잔여).

**조치.**
1. (콘솔) **Play Data Safety / Apple App Privacy** 작성 — 수집: 이메일·이름/닉네임·학년(계정), 사진/첨부(사용자 콘텐츠). 목적: 앱 기능. **공유 없음·추적 없음·판매 없음.** HTTPS 암호화 전송.
2. (콘솔) Play Console **데이터 삭제 URL**에 `https://<운영도메인>/account/delete` 등록.
3. (문서) `docs/DATA_SAFETY_FORM.md`로 근거 스냅샷 남김.

**근거(무추적 확증).** `pubspec.lock`에 analytics/ads/tracking SDK **0**. iOS `NSUserTrackingUsageDescription` 없음(ATT 불요).

**수용기준.** 두 스토어 프라이버시 양식 제출 · 삭제 URL 등록 · 문서화.

---

## P1-7 · 번들ID 단일 확정 + iOS 표시명 통일  ‹담당: 앱 · 사람›

**문제.** 번들/패키지 ID가 문서마다 3종. iOS 표시명 불일치.
- `com.ssambership.ssambership_app`(android/app/build.gradle.kts `applicationId`/`namespace`)
- `com.ssambership.ssambershipApp`(docs/IOS_BUILD.md)
- 권장 `com.ssambership.app`(HANDOFF.md)
- `ios/Runner/Info.plist` `CFBundleDisplayName`="Ssambership App" vs 런처명 `strings.xml`="쌤버십".

**조치.** (사람) 최종 번들ID 1개 확정. (앱) Android `applicationId`/iOS `PRODUCT_BUNDLE_IDENTIFIER`를 확정값으로 통일, 관련 문서 정정. iOS `CFBundleDisplayName`을 "쌤버십"으로 통일(홈 화면 표기 일치).

**수용기준.** Android/iOS 번들ID 동일 계열로 확정 · 문서 3곳 정정 · iOS 홈 표시명 "쌤버십".

---

## P1-8 · 스토어 빌드 플래그 무주입 가드  ‹담당: 앱›

**문제.** dart-define을 켜면 Commerce-Zero가 깨진다.
- `SUBS_MANAGE_LINK_ENABLED=true` → 학생 '구독 관리(웹)' 외부링크 부활(`student_subscription_section.dart` `openBillingManageWeb`).
- `IQ_CREATE_ENABLED=true` → 인앱 캐시 차감·예치 단가노출 플로우 부활(`iq_create_screen.dart` 예치 확인 다이얼로그).

**근거.** `lib/**/commerce_policy.dart`·`iq_flags.dart` — 둘 다 `bool.fromEnvironment(..., defaultValue:false)`.

**조치.** (앱)
1. 릴리즈 빌드 절차 문서에 "**dart-define 무주입 = 스토어 구성**" 명문화(HANDOFF와 정합).
2. CI/스모크: 두 플래그 OFF 상태에서 구매 관리 링크·IQ 생성 진입점이 **숨겨짐**을 검증하는 테스트 유지/추가.

**수용기준.** 무주입 빌드에서 '구독 관리(웹)'·'새 개별질문'·멘토 상세 'IQ 하기' 미노출 테스트 통과.

---

## P1-9 · 죽은 커머스 코드 삭제  ‹담당: 앱›

**문제.** `openSubscribeWeb`/`openRechargeWeb`는 **호출부 0**(죽은 코드). 향후 재배선 시 컴플라이언스 재위반 위험.

**근거.** `lib/core/web_bridge/web_bridge_actions.dart`의 `openSubscribeWeb`(정의만)·`openRechargeWeb`(정의만) + 하위 `web_bridge.dart` `openSubscribe`/`openRecharge` — grep 결과 UI 호출부 없음. (QA-09 기존 지적과 일치.)

**조치.** (앱) `openSubscribeWeb`·`openRechargeWeb` 및 미사용 `WebBridge.openSubscribe`/`openRecharge`·관련 config path(`subscribePath`·`rechargePath`) 삭제. 삭제로 깨지는 테스트 정리.

**수용기준.** 미사용 커머스 진입 함수 제거 · `flutter analyze` 0 error · 테스트 통과.

---

# 배치 순서(권장)

1. **앱 코드 배치(이 세션에서 즉시 가능):** P0-3 → P1-9 → P1-8 → P1-7(앱 부분). 한 배치로 묶어 `flutter analyze`/테스트 통과 후 커밋.
2. **웹/법무 배치:** P0-1 → P0-2(웹 부분). (별도 웹 세션)
3. **사람/콘솔 배치:** P0-4 → P1-5 → P1-6 → P0-2(콘솔) → P1-7(확정).

# 제출 전 최종 게이트 체크리스트

- [ ] 약관·개인정보 정식본 게시(초안 배너 제거) + 콘솔 URL 등록 (P0-1)
- [ ] 대상연령 정책 확정 + 연령등급 문진 정확 (P0-2)
- [ ] 댓글 신고 + 게시 전 EULA 게이트 동작 (P0-3)
- [ ] 데모계정 등록 + 심사노트(멀티플랫폼·정산·삭제경로) (P0-4)
- [ ] 릴리즈 키 서명 AAB 확인 (P1-5)
- [ ] Data Safety/영양성분표 제출 + 삭제 URL 등록 (P1-6)
- [ ] 번들ID·표시명 통일 (P1-7)
- [ ] 무주입 빌드 = Commerce-Zero 테스트 통과 (P1-8)
- [ ] 죽은 커머스 코드 제거 (P1-9)
- [ ] (기존 유지) INTERNET 단일권한·추적 SDK 0·개발도구 릴리즈 차단·시크릿 미커밋·targetSDK 36

---

# 배치 1 구현 기록 (앱 코드 · 2026-07-14)

## P0-3 · iOS UGC — 댓글 신고 + 게시 전 정책 동의 게이트
- 신규 `lib/features/community/ui/widgets/content_policy_gate.dart` — 세션 스코프 동의 게이트(의존성 추가 없음). 게시글·댓글 공통, 최초 게시 동선에서 1회 동의.
- `comment_tile.dart` — `onReport` 콜백 추가, ⋯ 메뉴에 '신고' 노출('차단'과 병존).
- `board_detail_screen.dart`·`shortform_detail_screen.dart` — `_reportComment()` 추가(`target_type='community_comment'`, 웹 관리자 검수와 정합), 댓글에 `onReport` 배선, `_send()`에 동의 게이트 삽입.
- `board_write_screen.dart` — `_submit()`에 동의 게이트 삽입.
- 신규 테스트 `test/community/content_policy_gate_test.dart` — 동의 게이트 노출/저장/취소 + 댓글 '신고' 메뉴 검증.

## P1-9 · 죽은 커머스 코드 삭제
- `web_bridge.dart`에서 `openSubscribe`/`openRecharge` 제거, `web_bridge_actions.dart`에서 `openSubscribeWeb`/`openRechargeWeb` 제거, `web_bridge_config.dart`에서 `subscribePath`/`rechargePath` 제거.
- 관련 테스트(`test/web_bridge/*`)를 존속 메서드(`openBillingManage` 등)로 재작성.

## P1-7 · 번들ID 단일 확정 + iOS 표시명 통일
- `ios/Runner/Info.plist` `CFBundleDisplayName` "Ssambership App" → "쌤버십"(런처명·스토어명 일치).
- **번들ID `com.ssambership.app` 로 통일 확정(사용자 결정, 2026-07-14):**
  - Android `build.gradle.kts` `applicationId`·`namespace` → `com.ssambership.app`, `MainActivity.kt` 를 `com/ssambership/app/` 패키지로 이동.
  - iOS `project.pbxproj` `PRODUCT_BUNDLE_IDENTIFIER`(RunnerTests 포함) → `com.ssambership.app`.
  - 문서 정정: `IOS_BUILD.md`·`HANDOFF.md`·`QA_RUN_RESULT_2026-07.md`·`MANUAL_QA_HUMAN_2026-07.md`·`capture-screenshots.md` 의 구 번들ID 전부 갱신.
  - ★ 스토어 최초 등록 시 이 식별자로 App ID(Apple)·패키지(Play)를 생성해야 하며, 등록 후 변경 불가.

## P1-8 · 무주입 빌드 가드
- 기존 가드 테스트 확인: `test/mypage/subs_manage_link_flag_test.dart`, `test/individual_question/iq_create_flag_test.dart`. 별도 추가 불필요.

> ~~⚠️ **검증 한계:** 이 실행 환경에 Flutter/Dart SDK가 없어 `flutter analyze`/`flutter test`를 로컬 실행하지 못했다.~~
> **정정(2026-07-16):** 위 한계는 해소됐다 — 이후 별도 검증 세션에서 실 툴체인(Flutter 3.44.6 stable · Dart 3.12.2)으로 `flutter pub get`·`flutter analyze`(에러·경고 0, info 린트만)·`flutter test`(331개 전부 통과)를 실제 실행해 확인했다(상세: `docs/ANDROID_SUBMISSION_READINESS_2026-07.md` 부록 B — 단, 해당 런의 베이스는 `c1b005f`라 이 배치1 코드 자체는 미포함). 배치1 포함 최종 그린은 머지된 master 에서 `flutter analyze && flutter test` 재실행으로 확정한다.

---

_생성: 2026-07-14 · 사전검증 보고서 기반. 값·URL·법적 문구는 확정 전까지 만들지 않는다(날조 금지)._
