# 브랜치 아카이브 — 2026-09-04

`--mirror` 복제로 넘어온 원격 브랜치 정리 기록. 기준: `origin/master` (`635ae738f134`).

- 조사 시점 원격 브랜치: **61개** (master 제외)
- master 에 완전 병합(ancestor) → **삭제 대상: 29개**. 커밋은 master 이력에 그대로 있으므로 지워도 잃는 것이 없다.
- ★ **삭제는 이 세션에서 실행되지 않았다.** `git push origin --delete …` 가 세션의 권한 정책(자동 모드 분류기)에 막혔다. 아래 `## 삭제 명령` 을 오너가 로컬에서 그대로 실행하면 된다(1분 이내). 표의 판정·SHA 는 실행 시점에 `git fetch --prune` 후 재확인할 것.
- master 에 없는 커밋이 있는 브랜치 → **삭제하지 않고 유지: 32개** (아래 표). 처리는 오너 판단.
- 병합 판정은 git 조상 관계다. squash 병합·재작성 브랜치는 내용이 master 에 있어도 '아니오'로 나온다 — 그런 경우를 돕기 위해 `PR`(master 병합 커밋 메시지에서 추출)과 '패치 동등 커밋' 수를 함께 적었다.
- 복구: `git fetch origin <SHA> && git checkout -b <이름> <SHA>` (GitHub 는 삭제된 브랜치의 커밋도 SHA 로 한동안 조회 가능. 확실히 하려면 오너가 원본 저장소 `ssambership-app` 에서 되찾는다 — 원본은 건드리지 않았다).

## 2026-09-04 A-2 재시도 기록

A-2 지시서("브랜치 삭제 권한이 열렸다")에 따라 같은 세션에서 `git push origin --delete <29개>` 를 다시 실행했으나
**세션의 자동 모드 권한 분류기가 재차 차단**했다. GitHub MCP 도구에도 브랜치 삭제 기능이 없어 우회하지 않았다.
원격 브랜치 수는 조사 시점과 동일하게 62개(master 포함, + 이 작업 브랜치 = 63)다. 아래 `## 삭제 명령` 을 오너가 실행하면 된다.

## 삭제 대상 브랜치 (master 에 완전 병합 — 미실행)

| 브랜치 | 마지막 커밋 | 마지막 커밋 날짜 | master 병합 | PR | 처리 |
|---|---|---|---|---|---|
| `ci/android-signed-release-candidate` | `b9215659aa62` | 2026-08-06 | 예 | #52 | **삭제 대상**(미실행 — 아래 참조) |
| `ci/fix-signed-workflow-test-footer` | `4645428c0298` | 2026-08-06 | 예 | #53 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/android-launcher-icon-build12-20260802` | `12189b37c1f8` | 2026-08-02 | 예 | #37 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/app-cache-state-withdrawal-banner-8bcvyk` | `0d90bdac62cb` | 2026-07-25 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/app-comm-iq-vc10-20260801` | `70de83bb2f25` | 2026-08-01 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/app-shortform-media-read-v1-wdwvav` | `150730f966d1` | 2026-07-26 | 예 | #35 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/build13-account-deletion-consent-20260802` | `8ec1a7fa63c5` | 2026-08-02 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/build13-app-integration-egqgrz` | `1dc5e61e4385` | 2026-08-02 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/build13-community-post-rpc-20260802` | `bd4bd49b25dc` | 2026-08-02 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/build13-question-room-safety-time-20260802` | `98f2927d7e42` | 2026-08-02 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/code-review-markdown-repos-g18cv7` | `e4b4c37d2867` | 2026-07-16 | 예 | #32 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/community-post-rpc-migration-1u6ga7` | `bd4bd49b25dc` | 2026-08-02 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/flutter-app-remediation-0r2k8p` | `42f9f97e7c2b` | 2026-07-26 | 예 | #33 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/flutter-app-v16-session-1-64m4ys` | `50d34091eac8` | 2026-07-17 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/ios-release-config-convergence-h5j6j8` | `30242c12cdfd` | 2026-08-04 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/iq-media-attribution-annotation-brand-fix-cu44qw` | `b701595a30a3` | 2026-08-04 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/positive-balance-deletion-fix-lmxpd5` | `8ec1a7fa63c5` | 2026-08-02 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `claude/sambership-play-doc-followup-ro27n4` | `e3df303721be` | 2026-07-27 | 예 | #34 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/sambership-session-handoff-7z5xdi` | `25c92172ef0e` | 2026-07-15 | 예 | #31 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/ssambership-app-store-review-l8zj97` | `1c036a2a7f91` | 2026-07-16 | 예 | #30 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/ssambership-convergence-defect-closure-ckc2z2` | `d08a858a6ff7` | 2026-08-03 | 예 | #42 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/ssambership-web-app-integration-q90u2r` | `a044213de641` | 2026-07-07 | 예 | #22 | **삭제 대상**(미실행 — 아래 참조) |
| `claude/store-submission-cleanup-suca29` | `4fc0cd042ff3` | 2026-07-12 | 예 | #28 | **삭제 대상**(미실행 — 아래 참조) |
| `fix/release-native-iq-create-boundary-20260805` | `eb08b161739e` | 2026-08-05 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `fix/xcode-cloud-project-package-resolved-20260805` | `b56202ed3747` | 2026-08-05 | 예 | #49 | **삭제 대상**(미실행 — 아래 참조) |
| `fix/xcode-cloud-workspace-package-resolved-20260805` | `cbbaf7852d0e` | 2026-08-05 | 예 | #48 | **삭제 대상**(미실행 — 아래 참조) |
| `fix/xv-attach-v2` | `2df065edbc9f` | 2026-07-12 | 예 | #27 | **삭제 대상**(미실행 — 아래 참조) |
| `release/prebuild-convergence-20260805` | `175b811169ea` | 2026-08-04 | 예 | — | **삭제 대상**(미실행 — 아래 참조) |
| `verify/cross-final-2026-07` | `557986e65b11` | 2026-07-16 | 예 | #26 | **삭제 대상**(미실행 — 아래 참조) |

## 유지 브랜치 (master 미병합 커밋 있음 — 오너 판단 필요)

| 브랜치 | 마지막 커밋 | 마지막 커밋 날짜 | master 병합 (+미병합 커밋) | PR | 처리·미병합 커밋 |
|---|---|---|---|---|---|
| `chore/release-config` | `305a781db442` | 2026-07-06 | 아니오 (+2) | — | **유지** — • 305a781 docs(release): 의사결정 기록 + QA-05/07 문서 정합 + Supabase 정체 명기<• d2825c6 feat(release): 결정 이행 — IQ 작성 기본 off(A안) + baseUrl 운영 확정(주입 구조) |
| `ci-logs` | `5a4e0a1fc602` | 2026-09-04 | 아니오 (+1) | — | **유지** — flutter-ci 가 매 실행 force-push 하는 일회용 로그 브랜치(원본 저장소 실행분). • 5a4e0a1 ci logs run=33833624237 sha=a0a1ff2679680d25d5b9262f4d427d6f29e062c6 |
| `claude/android-qa-manual-2026-07-vwzdgm` | `a5ada50a14ce` | 2026-07-12 | 아니오 (+1) | — | **유지** — 패치 동등 커밋 1건(이미 master 에 같은 변경). • a5ada50 docs(qa): 2026-07 실기기 QA 런 준비물 — 테스트 데이터·사람용 런북·결과 매트릭스 |
| `claude/api-app-v1-1-contract-20260729-v2` | `ad3def11e58b` | 2026-07-29 | 아니오 (+11) | — | **유지** — • ad3def1 docs(contract): 앱 v1.1을 새 웹 정본(48e64ee)으로 재동기 — M17 표면 소유·D-API-A 플랫폼 단계<• 5eab3c9 docs(contract): 앱 v1.1을 새 웹 정본(53120d0)으로 재동기 — F4 replay-first·보상 삭제 4분기·T-CONC-10b• 10fb9c6 docs(contract): add api_app_v1 contract v1.1<br>• … (+8) |
| `claude/app-contract-m13-resync-iu94hr` | `bc89de109b53` | 2026-07-30 | 아니오 (+12) | — | **유지** — • bc89de1 docs(contract): resync app contract with M13 comment canon<• ad3def1 docs(contract): 앱 v1.1을 새 웹 정본(48e64ee)으로 재동기 — M17 표면 소유·D-API-A 플랫폼 단계b• 5eab3c9 docs(contract): 앱 v1.1을 새 웹 정본(53120d0)으로 재동기 — F4 replay-first·보상 삭제 4분기·T-CONC-10<br>• … (+9) |
| `claude/app-rebuild-feature-review-oyewr0` | `cbed8b64dae4` | 2026-09-04 | 아니오 (+1) | — | **유지** — • cbed8b6 docs: 앱 재구축 검토 — 웹 동등(결제 제외) 범위·신설 기능 설계(2026-09) |
| `claude/app-supabase-integration-study-0xl2s4` | `56a60128683f` | 2026-07-27 | 아니오 (+1) | — | **유지** — • 56a6012 docs(app): 앱-Supabase 접합부 집중 학습 보고서 (2026-07-27) |
| `claude/file-update-adversarial-validation-26joaq` | `f4abb6493d2e` | 2026-08-08 | 아니오 (+6) | — | **유지** — • f4abb64 docs: 지도 v4 캠페인 마감 — 실기기 재QA 9건 PASS·출시 승격 반영<• e5b5f76 docs: build 22 내부 테스트 실기기 재QA 체크리스트 — PR #54 수정 9건b• 23b7cb1 release: 리포 버전을 스토어 현실(versionCode 22)에 정합 + 지도 v4 현행화<br>• … (+3) |
| `claude/flutter-app-structure-audit-h90fub` | `f68d1217f4b8` | 2026-09-01 | 아니오 (+1) | — | **유지** — • f68d121 docs(app-audit): 앱 구조 정본 감사 보고서 추가 (코드 변경 없음) |
| `claude/internal-test-aab-setup-bsjafb` | `e91f49776f93` | 2026-07-21 | 아니오 (+1) | — | **유지** — • e91f497 build(android): release 서명 부재 시 fail-fast — debug 서명 AAB 오업로드 차단 |
| `claude/ios-build-app-store-9kdi6s` | `7c547d55200c` | 2026-07-13 | 아니오 (+1) | — | **유지** — • 7c547d5 fix(ios): App Store 출시 준비 — 수출규정 키·개인정보 매니페스트·출시 가이드 |
| `claude/ios-build-session-expansion-sk4mi8` | `0ea56aee1c9c` | 2026-07-08 | 아니오 (+1) | — | **유지** — • 0ea56ae feat(ios): iOS 빌드 준비 — 웹 브릿지 P0 수정·Podfile·프라이버시 매니페스트 (S20) |
| `claude/logo-image-rendering-y7q106` | `f6993af3f7bd` | 2026-07-10 | 아니오 (+1) | — | **유지** — 패치 동등 커밋 1건(이미 master 에 같은 변경). • f6993af feat(brand): 앱 로고를 확정 심볼(졸업모자+말풍선)로 교체 |
| `claude/markdown-spec-patch-vtqvv7` | `63d0a6a9cf6c` | 2026-07-06 | 아니오 (+5) | — | **유지** — • 63d0a6a docs(status): 탭 개편·연결노트 필기 제거 현행화 (APP_FEATURE_STATUS)<• d197503 feat(notifications): 개별질문 알림 딥링크를 개별질문 탭으로 분리b• c467a3a docs(handoff): 하단 탭 개편·연결노트 필기 제거·테스트 250개 현행화<br>• … (+2) |
| `claude/s18-iq-annotation-niugro` | `728848cc4d4d` | 2026-07-07 | 아니오 (+4) | — | **유지** — • 728848c docs(db): ink.json upsert 용 스토리지 UPDATE 정책 기록 (운영 적용 완료)<• b46c4b0 docs(ink): S18 규약 확정 반영 — 기획안·인수인계·실기기 QA 체크리스트b• 9eb922d feat(iq): 개별질문 첨삭 — 학생 필기하기·멘토 첨삭하기 (S18, DB 변경 0)<br>• … (+1) |
| `claude/s2-2-app-transition-m17-gate4-afw0ag` | `1c5d6c019053` | 2026-07-30 | 아니오 (+13) | — | **유지** — • 1c5d6c0 feat(app): S2-2 api_app_v1 전환 — M17 View 읽기·F2~F6 wrapper·직접 쓰기 0건·Gate 4 로컬 검증<• bc89de1 docs(contract): resync app contract with M13 comment canonb• ad3def1 docs(contract): 앱 v1.1을 새 웹 정본(48e64ee)으로 재동기 — M17 표면 소유·D-API-A 플랫폼 단계<br>• … (+10) |
| `claude/s2-6-android-signed-release-8yym8y` | `03495f045630` | 2026-07-31 | 아니오 (+14) | — | **유지** — • 03495f0 docs(audit): record S2-6 signed release blocker<• 1c5d6c0 feat(app): S2-2 api_app_v1 전환 — M17 View 읽기·F2~F6 wrapper·직접 쓰기 0건·Gate 4 로컬 검증b• bc89de1 docs(contract): resync app contract with M13 comment canon<br>• … (+11) |
| `claude/s2-6r-android-signed-release-4rt9iu` | `ba5fe543f2d5` | 2026-07-31 | 아니오 (+15) | — | **유지** — • ba5fe54 docs(audit): record S2-6R owner-env signed release blocker evidence<• 03495f0 docs(audit): record S2-6 signed release blockerb• 1c5d6c0 feat(app): S2-2 api_app_v1 전환 — M17 View 읽기·F2~F6 wrapper·직접 쓰기 0건·Gate 4 로컬 검증<br>• … (+12) |
| `claude/s2-6r-android-signed-release-owner-0rd6q7` | `73a596dd0288` | 2026-07-31 | 아니오 (+17) | — | **유지** — • 73a596d docs(audit): S2-6R signed release owner-env evidence (PASS, RC 0.1.0+9)<• 28eaf7d chore(release): S2-6R RC — pubspec version 0.1.0+9 (versionCode 9)b• cd66918 docs(audit): record S2-6R signed release owner-env blocker<br>• … (+14) |
| `claude/schema-doc-verification-q876xf` | `02e1f7a51345` | 2026-07-29 | 아니오 (+8) | — | **유지** — • 02e1f7a docs(audit): 앱 동기화 지시서 rev 8 종결<• a595330 docs(audit): 앱 동기화 지시서 rev 7 최종 정합화b• 3ad1395 docs(audit): 앱 동기화 지시서 rev 6 — 보상 삭제 코드 제거 의무·HD-1 전면 잠금·승인 멘토 동결 반영<br>• … (+5) |
| `claude/ssambership-app-fixes-sta99j` | `e51748d37c82` | 2026-08-05 | 아니오 (+3) | #50 | **유지** — PR #50 병합 후 추가 커밋. • e51748d docs(ios)/test: 마이크 권한 런북 반영 + 권한 계약 검사 강화<• 502b5e8 fix(ios): 숏폼 영상 촬영 마이크 권한 + IQ 첨삭하기 진입 버튼 폐쇄b• e9f1311 fix(notes): 연결노트 저장 중복 행 내성 — maybeSingle 예외로 인한 영구 저장 실패 제거 |
| `claude/ssambership-app-supabase-interaction-gj79qr` | `b1329ec041b7` | 2026-08-07 | 아니오 (+2) | #54 | **유지** — PR #54 병합 후 추가 커밋. • b1329ec ci(android): 서명 워크플로를 vc22 후보(20ff0b8)로 재고정<• 20ff0b8 chore: bump version to 1.0.0+22 for iOS release |
| `claude/ssambeship-store-screenshot-setup-n8uuja` | `552419ebefe6` | 2026-08-08 | 아니오 (+1) | — | **유지** — • 552419e chore(store): Google Play 스토어 스크린샷 촬영 스크립트 추가 |
| `claude/supabase-sql-audit-qfys2f` | `f82940cdc0cc` | 2026-07-27 | 아니오 (+2) | — | **유지** — • f82940c docs: deep review of app<->Supabase flow defects; fix audit RPC omission<• e94c45a docs: add full Supabase <-> app interaction audit (tables, RPCs, storage, realtime, RLS) |
| `claude/xcode-cloud-flutter-swiftpm-bootstrap-o8ba0j` | `30b1a9bb422b` | 2026-08-05 | 아니오 (+1) | — | **유지** — 패치 동등 커밋 1건(이미 master 에 같은 변경). • 30b1a9b ci(ios): add Xcode Cloud post-clone bootstrap for Flutter SwiftPM |
| `docs/store-review-rebaseline` | `312bc0d8a38f` | 2026-07-06 | 아니오 (+1) | — | **유지** — 패치 동등 커밋 1건(이미 master 에 같은 변경). • 312bc0d docs(store): PLAY_STORE_REVIEW_PLAN 재기준화 — master 3792858 대조 재판정 |
| `feat/s16-scan-sources` | `ad5400223ef0` | 2026-07-07 | 아니오 (+4) | — | **유지** — • ad54002 test/docs(scan): S16 흐름 테스트 9케이스 + 문서 갱신<• 0721f39 chore(ios): NSCameraUsageDescription 추가 — 촬영 진입 크래시 방지 (S16)b• 7af022c feat(question_room): 첨부 소스 선택 바텀시트 — 촬영/갤러리/파일 (S16 §6-1)<br>• … (+1) |
| `feat/s17-iq-attachments` | `bc23e4aec4b4` | 2026-07-07 | 아니오 (+4) | — | **유지** — • bc23e4a docs(s17): 기획안 §7-3 'iq_attachments 신설' 폐기 — 기존 스키마 재사용 정정<• 7ad6932 feat(iq): 개별질문 첨부 파이프라인 + 작성·상세 화면 (S17)b• 8486d56 feat(scan): downscaleIfOversized 를 JPEG(품질85) 재인코딩으로 교체<br>• … (+1) |
| `feat/s19-pdf-scan` | `1a4e1fda8d1b` | 2026-07-07 | 아니오 (+4) | — | **유지** — • 1a4e1fd chore(deps): pubspec.lock 커밋 정책 전환 — 앱 저장소 표준<• 154c985 docs(scan): 다운스케일 캡 서술 정정 — 5MB 초과 재인코딩은 장변 2560b• cbd7171 docs(qa): 실기기 QA 실행 시트 신설 + 기획안·인수인계 S19 마감 정리<br>• … (+1) |
| `fix/qa-p1-batch` | `2c30a5614d44` | 2026-07-06 | 아니오 (+4) | — | **유지** — • 2c30a56 fix(errors): 리뷰 후속 — FutureBuilder 에러 분기의 raw 노출 16곳 추가 제거<• b399447 docs: 개별질문(IQ) '흔적 없이 제외' 서술 자기모순 정정 (QA-03)b• 85095eb fix(notifications): 읽음 처리에 본인(user_id) 필터 추가 (QA-04)<br>• … (+1) |
| `fix/store-track-p0` | `c2507fa1b5b2` | 2026-07-06 | 아니오 (+10) | — | **유지** — • c2507fa test(mypage): 구독 관리 링크 단언을 플래그 연동으로 보강<• 5f4bd61 docs(store): 배치 처리 결과 체크 + '사람이 해야 하는 것' 섹션 신설b• 875bc15 feat(mypage): 회원 탈퇴 확인 다이얼로그 — 웹 열기 전 재확인 (P0-1 앱측)<br>• … (+7) |
| `qa/full-app-audit` | `40e470039813` | 2026-07-06 | 아니오 (+3) | — | **유지** — • 40e4700 docs(qa): QA-10 오탐 철회 — 게스트 초기 탭 재검증 (P2 10→9)<• 1f4b990 chore: coverage/ 를 gitignore 에 추가b• 136eec4 test(qa): 전체 QA 감사 — 시나리오·경계 테스트 33케이스 + 리포트·수동 체크리스트 |

## 삭제 명령 (오너 실행용)

```bash
git fetch origin --prune
git push origin --delete \
  ci/android-signed-release-candidate \
  ci/fix-signed-workflow-test-footer \
  claude/android-launcher-icon-build12-20260802 \
  claude/app-cache-state-withdrawal-banner-8bcvyk \
  claude/app-comm-iq-vc10-20260801 \
  claude/app-shortform-media-read-v1-wdwvav \
  claude/build13-account-deletion-consent-20260802 \
  claude/build13-app-integration-egqgrz \
  claude/build13-community-post-rpc-20260802 \
  claude/build13-question-room-safety-time-20260802 \
  claude/code-review-markdown-repos-g18cv7 \
  claude/community-post-rpc-migration-1u6ga7 \
  claude/flutter-app-remediation-0r2k8p \
  claude/flutter-app-v16-session-1-64m4ys \
  claude/ios-release-config-convergence-h5j6j8 \
  claude/iq-media-attribution-annotation-brand-fix-cu44qw \
  claude/positive-balance-deletion-fix-lmxpd5 \
  claude/sambership-play-doc-followup-ro27n4 \
  claude/sambership-session-handoff-7z5xdi \
  claude/ssambership-app-store-review-l8zj97 \
  claude/ssambership-convergence-defect-closure-ckc2z2 \
  claude/ssambership-web-app-integration-q90u2r \
  claude/store-submission-cleanup-suca29 \
  fix/release-native-iq-create-boundary-20260805 \
  fix/xcode-cloud-project-package-resolved-20260805 \
  fix/xcode-cloud-workspace-package-resolved-20260805 \
  fix/xv-attach-v2 \
  release/prebuild-convergence-20260805 \
  verify/cross-final-2026-07 \
  ;
```

### 유지 브랜치 성격 요약

- **문서·감사 기록만 있는 브랜치**(코드 변경 0): `claude/api-app-v1-1-contract-*`·`claude/app-contract-m13-resync-*`·`claude/schema-doc-verification-*`·`claude/supabase-sql-audit-*`·`claude/app-supabase-integration-study-*`·`claude/flutter-app-structure-audit-*`·`claude/app-rebuild-feature-review-*`·`claude/file-update-adversarial-validation-*`·`claude/android-qa-manual-*`·`docs/store-review-rebaseline`·`chore/release-config`(docs+플래그 1건). 필요한 문서만 `docs/renewal/` 로 옮겨 담고 지우는 것을 권장.
- **기능 코드가 있는 오래된 작업 브랜치**(2026-07-06~07, 대부분 이후 다른 경로로 master 에 반영됨): `feat/s16-scan-sources`·`feat/s17-iq-attachments`·`feat/s19-pdf-scan`·`claude/s18-iq-annotation-*`·`fix/qa-p1-batch`·`fix/store-track-p0`·`qa/full-app-audit`·`claude/markdown-spec-patch-*`. master 에 같은 기능이 이미 있으므로(HANDOFF §2-B) 실질 가치는 낮다 — 삭제 후보.
- **api_app_v1 전환(S2-2) 계열**: `claude/s2-2-app-transition-m17-gate4-*` 와 그 위에 쌓인 `claude/s2-6*-android-signed-release-*` 3개(버전 0.1.0+9 RC). 코드 13~17 커밋이 master 에 없다. 리뉴얼(A-2~A-4)과 방향이 겹치므로 **내용 검토 후 결정**.
- **PR 병합 후 추가 커밋**: `claude/ssambership-app-fixes-sta99j`(PR #50 후 3건: 연결노트 저장 내성·iOS 마이크 권한·IQ 첨삭 진입 폐쇄), `claude/ssambership-app-supabase-interaction-gj79qr`(PR #54 후 2건: 1.0.0+22 버전 범프·서명 워크플로 재고정). 후자는 '버전 올리지 않음' 방침과 충돌하므로 이번엔 반영하지 않았다.
- **iOS/Android 빌드 설정 단건**: `claude/ios-build-app-store-*`·`claude/ios-build-session-expansion-*`·`claude/internal-test-aab-setup-*`·`claude/xcode-cloud-flutter-swiftpm-bootstrap-*`(패치 동등)·`claude/logo-image-rendering-*`(패치 동등)·`claude/ssambeship-store-screenshot-setup-*`. 대부분 다른 커밋으로 master 에 반영됨 — 삭제 후보.
- `ci-logs`: CI 가 자동 생성·force-push 하는 로그 브랜치. 다음 CI 실행 때 덮어써진다 — 지워도 무방.
