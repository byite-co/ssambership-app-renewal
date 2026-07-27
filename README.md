# 쌤버십 모바일 앱 (ssambership_app)

기존 웹(Next.js, `D:\dev\ssambership_web`)의 **컴패니언 앱**. 단일 Flutter 코드베이스로 Android·iOS 동시 타깃.

## 핵심 원칙
- **Commerce-Zero:** 앱 안에 결제·가격·구매 버튼·외부 결제 링크 **없음**. 결제(구독·캐시 충전)가 필요하면 `web_bridge` 가 **웹 페이지만** 연다.
- **읽기 중심:** 백엔드는 기존 웹과 공유하는 **Supabase 1개**. 앱에서 새 백엔드·정산·결제 로직을 만들지 않는다.
- **제외(흔적 없이):** 맞춤의뢰(CR)·관리자·회원가입 폼. (개별질문(IQ)은 2026-07 하단 1급 탭으로 **승격** — `kIndividualQuestionEnabled`/`kIndividualQuestionCreateEnabled` 스위치 지배.)
- **표시 규칙:** 화면에 내부 DB명·UUID·이벤트코드·딥링크 경로·영문 코드값 노출 금지(과목은 한글 매핑 사용).

## ⚠️ 현재 상태 (S0 스캐폴드)
이 PC에 **Flutter/Dart/Android SDK 가 설치돼 있지 않아**, `flutter create` 로 생성되는 **네이티브 폴더(android/ , ios/)가 아직 없습니다.** `lib/` 구조·설정·문서만 손으로 작성된 상태입니다.

### Flutter 설치 후 1회 실행 (네이티브 폴더 생성)
```bash
cd D:\dev\ssambership_app
flutter create . --org com.ssambership --project-name ssambership_app --platforms=android,ios
flutter pub get
flutter analyze
flutter run            # 에뮬레이터/시뮬레이터 선택
```
- `flutter create .` 는 기존 `lib/`·`pubspec.yaml` 을 보존하고 `android/`·`ios/` 등 누락 폴더만 생성합니다.
- 앱 ID(현재 계약): Android package `com.ssambership.edu`, iOS 번들ID `com.ssambership.app` (`--org com.ssambership`).

## 환경 변수 (.env)
- 개발은 **로컬 Supabase** 를 사용합니다. `.env` 에 로컬 값만 둡니다.
- **Supabase URL 은 코드에서 플랫폼별로 분기**됩니다 (`lib/core/config/app_config.dart`):
  | 실행 환경 | URL |
  |---|---|
  | Android 에뮬레이터 | `http://10.0.2.2:54321` (자동 변환) |
  | iOS 시뮬레이터 / 데스크탑 | `http://127.0.0.1:54321` (`.env` `SUPABASE_URL`) |
  | **실기기** | PC의 LAN IP — `.env` 의 `SUPABASE_URL_LAN` 에 `http://192.168.x.x:54321` **직접 입력** |
- anon key(로컬, 공개 데모 키)는 `.env` `SUPABASE_ANON_KEY` 에 있습니다.
- 로컬 anon key 위치: `D:\dev\ssambership_web\.env.local` 또는 `npx supabase status` 출력.

### TODO — 출시(원격 production)
- 출시 시 `.env` 를 **원격 production** 값으로 교체:
  ```
  SUPABASE_URL=https://<project-ref>.supabase.co
  SUPABASE_ANON_KEY=<remote-anon-key>
  ```
- 원격이면 플랫폼 분기 없이 그대로 사용됩니다(코드 자동 처리).

## 폴더 구조
```
lib/
  app/        라우팅(router)·루트앱(app)·홈셸(5탭)·진입가드(entry_guard)
  core/       supabase/ · config/ · auth/ · entitlement/ · deeplink/ · push/   (자리)
  design/     tokens/(color·typography) · theme · widgets/(empty_screen)
  features/   onboarding/ auth/ question_room/ community/ mentors/ notifications/ mypage/ web_bridge/
  data/       models/ · repositories/(health_repository=연결점검) · mappings/(subject_labels 한글)
  shared/     constants/(app·plan) · format/ · errors/
```

## 상수 (미확정값 = 키만, 값 비움)
- **멘토 정산일 = 23** (확정).
- 요금제명·구독 가격·주간 문항수 = **키만, 값 비움(TODO)** — 특히 프리미엄 문항수 미확정(FUP). (`lib/shared/constants/plan_constants.dart`)
- 색 토큰: 스카이 단일 강조 + 시맨틱(page/surface/elevated, primary/secondary/muted, accent, success/warning/danger) — **hex 는 임시 placeholder**, 웹 다크+스카이 확정 후 교체. (`lib/design/tokens/color_tokens.dart`)
- web_bridge 의 웹 URL·경로 = **미확정(키만)**.

## 격리 규칙
- 이 앱은 **별도 폴더 + 별도 git 저장소**(`D:\dev\ssambership_app`)에서만 작업합니다.
- 기존 웹 저장소(`D:\dev\ssambership_web`)·정산 브랜치·색 토큰을 **절대 건드리지 않습니다.**
