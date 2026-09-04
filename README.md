# 쌤버십 모바일 앱 — 리뉴얼 저장소 (`ssambership-app-renewal`)

학습 멘토링 서비스 **쌤버십**의 Flutter 앱. 이 저장소는 2026-09 부터 진행하는 **앱 리뉴얼**의 작업 공간이다.
기존 앱 저장소(`byite-co/ssambership-app`)를 `--mirror` 로 복제해 시작했고, **같은 앱의 새 버전**으로 배포한다
(Android `com.ssambership.edu` · iOS `com.ssambership.app` — 번들 ID 불변).

## 목적과 범위

- **범위**: 캐시 충전을 제외한 전 기능을 앱에서 지원한다. 종전의 "읽기 중심 · Commerce-Zero(앱 내 결제 없음)"
  전제는 리뉴얼로 뒤집힌다(`pubspec.yaml` description 갱신 완료). 캐시 충전만 웹에서 한다.
- **방침**: 범위는 넓게, 되돌아오지 않게, 충돌·버그는 최소화. 그래서 **골격(라우팅·상태관리) 교체 전에 회귀 방어선
  (골든 테스트·CI)** 을 먼저 세운다.
- **백엔드**: 기존 웹과 공유하는 Supabase 1개. 앱이 호출하는 RPC/테이블/버킷의 전체 집합은 계약 테스트
  (`test/contracts/outbound_api_manifest_test.dart`)가 잠근다 — 서버 표면을 추가·제거하면 매니페스트를 함께 갱신한다.

## 원본 저장소와의 관계

| | `ssambership-app` (원본) | `ssambership-app-renewal` (이 저장소) |
|---|---|---|
| 역할 | 2026-07~08 출시 준비 코드의 정본. **읽기 전용 참조** | 리뉴얼 개발·배포 |
| 이력 | — | 원본 `master` 전체 커밋 이력을 그대로 승계(2026-09-04 기준 `635ae73`) |
| 브랜치 | 그대로 | `master` + 미병합 커밋이 있는 브랜치만 유지. 정리 기록: `docs/renewal/branch-archive-2026-09-04.md` |
| 문서 | 그대로 | 7~8월 문서는 `docs/legacy/` 로 이동(2026-07 기준, 리뉴얼 전 상태). 리뉴얼 문서는 `docs/renewal/` |

원본 저장소는 수정·푸시하지 않는다.

## 개발 환경

- Flutter **3.44.6 stable** (CI 고정 버전 — `.github/workflows/flutter-ci.yml`) · Dart 3.12 · JDK 17(Android).
- `.env` 는 커밋하지 않는다. 로컬 개발·테스트는 자리표시 값으로 충분하다:

```bash
cp .env.example .env
flutter pub get
flutter analyze          # 게이트: error/warning 0 (info 는 비차단)
flutter test             # 전체 스위트(골든 포함), DB·네트워크 불필요
```

- 운영 DB 접속은 개발·테스트에 필요하지 않다. 테스트는 전부 손코딩 fake 를 주입한다(mock 패키지 없음).

## 골든 테스트 (화면을 PNG 로 본다)

기기·계정 없이 대표 화면을 렌더해 `test/goldens/images/*.png` 에 고정한다. 디자인이 골격을 벗어나면 CI 가 잡고,
실패 시 기대·실제·diff 이미지를 artifact(`golden-failures`)로 올린다. 기준 이미지 자체도 매 실행 `golden-screens`
artifact 로 올라간다.

```bash
flutter test test/goldens                   # 비교
flutter test test/goldens --update-goldens  # 기준 이미지 갱신 (Linux · Flutter 3.44.6 에서만)
```

- 기준 이미지는 **Linux · Flutter 3.44.6** 에서 생성한 것이 정본이다(CI 와 동일). macOS/Windows 에서는 안티에일리어싱
  차이로 미세하게 다를 수 있으므로, 로컬에서 갱신하지 말고 CI 의 diff 를 보고 판단한다.
- 화면 추가 방법: `test/goldens/golden_harness.dart` 의 `pumpGoldenScreen` 으로 감싸고 `expectScreenGolden(tester, '이름')`.
  픽스처·포트 fake 는 `golden_fixtures.dart` 에 모아 둔다. 네트워크·전역 싱글턴에 닿는 위젯은 렌더되지 않는다 —
  그 목록이 곧 골격 교체(A-2·A-3) 대상이다(`docs/renewal/bootstrap-report-2026-09-04.md`).

## 폴더 구조

```
lib/
  app/        GoRouter(4 라우트) · 루트앱 · 홈셸(하단 5탭) · 진입가드 · app_scope(수동 DI — AppDependencies/AppScope)
  core/       auth · supabase · entitlement · version_gate · web_bridge · deeplink · scan · ink · refresh · observability
  design/     색·타이포·간격 토큰 · 테마 · 공용 위젯
  features/   question_room · community · mentors · notifications · individual_question · mypage · auth · scan_annotation · dev
  data/       과목 한글 매핑
  shared/     상수 · 포맷터 · 에러 · 공용 위젯
test/
  goldens/    골든 테스트(대표 화면 PNG 14장) — flutter_test_config.dart 가 Pretendard 폰트를 로드하고, 하네스가 fake AppScope 로 감싼다
  contracts/  계약 테스트(아웃바운드 API 매니페스트 · iOS/Android 출시 설정 · 문서 정본)
  …           기능별 단위·위젯 테스트
docs/
  renewal/    리뉴얼 문서(기준선 · 브랜치 아카이브 · 단계 보고)
  legacy/     2026-07 기준, 리뉴얼 전 상태의 문서 보관
  *.md        계약 테스트가 경로로 읽는 런북 4개(ANDROID_BUILD · IOS_BUILD · IOS_RELEASE_RUNBOOK · S3E_…)
```

## CI

- `flutter-ci`: `master` push · PR · 수동 실행에서 `analyze` → `test`(골든 포함) → `appbundle`(파이프라인 확인용, 게이트 아님).
  시크릿 불필요. 로그는 `ci-logs` 브랜치로 발행.
- `Android Signed Release Candidate`: 수동 전용 서명 검증 워크플로. Environment `android-release-candidate` 와 시크릿이
  필요하며, 현재는 원본 저장소의 PR 번호·커밋에 고정돼 있어 이 저장소에서는 재고정 전까지 동작하지 않는다
  (`docs/renewal/bootstrap-report-2026-09-04.md` §CI).

## 기여 방법

1. `master` 에서 브랜치를 만들고 PR 로 합친다. CI(analyze · test · 골든)가 그린이어야 한다.
2. **바꾸지 않는 것**: 번들 ID · applicationId, `pubspec.yaml` 의 `version`(배포 시점에 정한다 — `test/app/build_version_test.dart`
   등 3곳이 잠근다), 운영 DB 스키마(앱 저장소에서 마이그레이션하지 않는다).
3. 서버 표면(RPC·테이블·버킷)을 바꾸면 `test/contracts/outbound_api_manifest_test.dart` 를 같은 PR 에서 갱신한다.
4. 골든이 깨지면 diff 를 보고 **의도한 변경일 때만** `--update-goldens` 로 갱신하고, 왜 바뀌었는지 PR 에 적는다.
5. **의존성은 `AppScope.of(context)` 로 읽는다.** 화면·위젯에서 `XxxService.instance`·`SupabaseInit.clientOrNull` 을 직접 부르지 않는다(A-2).
   새 의존성이 필요하면 `AppDependencies` 에 필드를 더하고 `golden_app_fakes.dart` 에 fake 를 짝으로 둔다. 인터페이스는 화면이 쓰는 멤버만.
6. 문서는 `docs/renewal/` 에 날짜를 붙여 쌓는다. 옛 문서는 지우지 않고 `docs/legacy/` 로 보낸다.

## 리뉴얼 단계

| 단계 | 내용 | 상태 |
|---|---|---|
| **A-1** 부트스트랩 | 저장소 정리 · 기준선 · 골든/CI 방어선 | 완료 — `docs/renewal/bootstrap-report-2026-09-04.md` |
| **A-2** 의존성 주입 전환 | 화면의 싱글턴·클라이언트 직접 참조 → `AppScope` 수동 DI · 골든 14장 · 폰트 결함 수정 | 완료 — `docs/renewal/di-report-2026-09-04.md` |
| A-3 라우팅 교체 | 라우트 4개 + 명령형 push 44곳 → 화면 수십 개를 감당하는 구조. AppScope 폴백 제거 | 예정 |
| A-4 기능 개방 | 캐시 충전 외 전 기능 | 예정 |
| A-5 연결노트 추가 전용 재설계 | | 예정 |
| A-6 디자인 통일 | | 예정 |
