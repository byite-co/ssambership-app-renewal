import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ssambership_app/main.dart' as app;

/// v16 e2e — 실서버(staging=운영 공용 DB) 대상. 웹 렌더러 + chromedriver 로 구동.
///
/// ★ 실계정·실DB 원칙(절대 준수):
/// - 탈퇴 플로우 실행 금지(실계정), 질문 생성 금지(무료쿼터/IQ 실소모),
///   게시글 작성 금지(삭제 UI 없음), 신고/차단 실행 금지(타 사용자 영향).
/// - 유일한 쓰기 2건은 가역: ① 게시판 댓글 1건([E2E] 표식 — 실행 후 SQL 로 즉시
///   정리, 절차는 docs/APP_V16_E2E_REPORT.md) ② 알림 설정 토글(원상복구까지 수행).
/// - 자격증명은 --dart-define 주입만 허용(코드/로그에 평문 금지).
const String _studentEmail = String.fromEnvironment('E2E_STUDENT_EMAIL');
const String _studentPw = String.fromEnvironment('E2E_STUDENT_PW');
const String _mentorEmail = String.fromEnvironment('E2E_MENTOR_EMAIL');
const String _mentorPw = String.fromEnvironment('E2E_MENTOR_PW');
const String _adminEmail = String.fromEnvironment('E2E_ADMIN_EMAIL');
const String _adminPw = String.fromEnvironment('E2E_ADMIN_PW');

/// 실행 시각 표식 — 정리(cleanup) 시 이 문자열로 e2e 댓글을 식별한다.
const String _commentTag = String.fromEnvironment('E2E_COMMENT_TAG',
    defaultValue: '[E2E] 자동테스트 댓글');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('학생→멘토→관리자 순 실서버 왕복 시나리오', (WidgetTester tester) async {
    // release/profile 웹 드라이버가 실패 상세를 비워 보내는 문제 대응 —
    // 진행 마커·실패 원인을 브라우저 콘솔로 직접 남긴다(CDP 로 수집).
    try {
      await _scenario(tester);
      _mark('ALL-DONE');
    } catch (e, st) {
      _mark('FAILURE: $e');
      _mark('STACK: ${st.toString().split('\n').take(10).join(' § ')}');
      // 실패 시점 화면의 텍스트 덤프 — 어떤 화면에 멈췄는지 식별용.
      final String texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .where((String s) => s.isNotEmpty)
          .take(40)
          .join(' | ');
      _mark('SCREEN: $texts');
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}

// ignore: avoid_print
void _mark(String msg) => print('E2E-MARK $msg');

Future<void> _scenario(WidgetTester tester) async {
    final WidgetTester _ = tester;
    expect(_studentEmail.isNotEmpty && _mentorEmail.isNotEmpty,
        isTrue, reason: 'E2E 자격증명(--dart-define)이 주입되지 않았다');

    _mark('boot');
    app.main();
    // 부팅(스플래시 → 세션 판정 → 로그인 화면). 실네트워크라 고정 대기 대신 폴링.
    await _pumpUntil(tester, find.text('로그인'),
        reason: '부팅 후 로그인 화면 도달');

    _mark('step1-student-login');
    // ── 1. 학생 로그인 → 홈 셸(5탭) ─────────────────────────────────────────
    await _login(tester, _studentEmail, _studentPw);
    await _pumpUntil(tester, find.byType(NavigationBar),
        timeout: const Duration(seconds: 45), reason: '학생 로그인 후 홈 셸');
    for (final String tab in <String>['질문방', '커뮤니티', '멘토 찾기', '알림', '개별질문']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)),
          findsOneWidget, reason: '하단 탭 "$tab" 존재');
    }

    // 질문방(초기 탭): 목록 프레임이 에러 없이 렌더(실데이터 로드).
    await _settle(tester, seconds: 6);
    _expectNoErrorText(tester, where: '질문방 탭');

    _mark('step2-community');
    // ── 2. 커뮤니티: 게시판 read + 댓글 1건 write(가역 — 사후 SQL 정리) ────────
    await _tapTab(tester, '커뮤니티');
    await _pumpUntil(tester, find.text('게시판'), reason: '커뮤니티 탭 진입');
    // 게시판 탭 전환 — 전환의 증거('작성' FAB, 게시판 탭 전용)가 보일 때까지 재시도.
    for (int i = 0; i < 4 && !tester.any(find.text('작성')); i++) {
      await tester.tap(find.text('게시판').hitTestable().first,
          warnIfMissed: false);
      await _settle(tester, seconds: 2);
    }
    expect(find.text('작성'), findsWidgets, reason: '게시판 탭 전환(작성 FAB 노출)');
    await _settle(tester, seconds: 5);
    _expectNoErrorText(tester, where: '게시판 목록');

    // 첫 게시글 열기 — 목록(ListView) 내부의 탭 가능한 InkWell 만 대상으로 한다.
    final Finder postOpen = find
        .descendant(
            of: find.byType(ListView),
            matching: find.byWidgetPredicate(
                (Widget w) => w is InkWell && w.onTap != null))
        .first;
    // 게시글 목록이 비어 있으면(운영 데이터 기준) 댓글 시나리오는 건너뛴다.
    final bool hasPost = tester.any(postOpen);
    bool commentWritten = false;
    if (hasPost) {
      await tester.tap(postOpen);
      await _pumpUntil(tester, find.text('게시글'), reason: '게시글 상세 진입');
      await _settle(tester, seconds: 4);

      final Finder commentField = find.byWidgetPredicate((Widget w) =>
          w is TextField && w.decoration?.hintText == '댓글 입력');
      if (tester.any(commentField)) {
        final String body =
            '$_commentTag ${DateTime.now().toIso8601String()}';
        await _type(tester, commentField, body, label: 'comment');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        // 게시 전 정책 동의 다이얼로그(ContentPolicyGate) — '동의하고 계속' 탭.
        if (tester.any(find.text('동의하고 계속'))) {
          _mark('policy-gate shown');
          await tester.tap(find.text('동의하고 계속'));
          await tester.pump(const Duration(milliseconds: 500));
        }
        // 서버 왕복(comments INSERT → 목록 재조회) 후 본문이 '댓글 목록의 Text'
        // 로 나타나야 한다. 입력 필드(EditableText)를 오탐하지 않도록 Text 한정.
        final Finder posted = find.byWidgetPredicate((Widget w) =>
            w is Text && (w.data?.contains(_commentTag) ?? false));
        await _pumpUntil(tester, posted,
            timeout: const Duration(seconds: 25),
            reason: '작성한 댓글이 목록에 반영');
        commentWritten = true;
        _mark('comment-posted-confirmed');
      }
      // 상세 닫기 — 홈 셸(NavigationBar)로 복귀할 때까지.
      await _goBack(tester);
      await _pumpUntil(tester, find.byType(NavigationBar),
          reason: '게시글 상세에서 홈 셸 복귀');
      await _settle(tester, seconds: 2);
    }
    debugPrint('E2E-MARK commentWritten=$commentWritten');

    _mark('step3-tabs');
    // ── 3. 멘토 찾기 / 알림 / 개별질문 read ─────────────────────────────────
    await _tapTab(tester, '멘토 찾기');
    await _settle(tester, seconds: 6);
    _expectNoErrorText(tester, where: '멘토 찾기 탭');

    await _tapTab(tester, '알림');
    await _pumpUntil(tester, find.text('안 읽음'), reason: '알림 탭 헤더');
    _expectNoErrorText(tester, where: '알림 탭');

    await _tapTab(tester, '개별질문');
    await _settle(tester, seconds: 6);
    _expectNoErrorText(tester, where: '개별질문 탭');

    _mark('step4-mypage');
    // ── 4. 마이페이지: 알림 설정 토글 왕복(가역 write) → 로그아웃 ─────────────
    await _openMyPage(tester);
    final Finder masterLabel = find.text('알림 받기');
    await _scrollTo(tester, masterLabel);
    final Finder masterSwitch = find.byType(Switch).first;
    final bool before = tester.widget<Switch>(masterSwitch).value;
    await tester.tap(masterSwitch);
    await _settle(tester, seconds: 4); // 서버 upsert 왕복
    expect(tester.widget<Switch>(find.byType(Switch).first).value, !before,
        reason: '알림 마스터 토글이 반영');
    await tester.tap(find.byType(Switch).first);
    await _settle(tester, seconds: 4);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, before,
        reason: '알림 마스터 토글 원상복구');

    await _logoutFromMyPage(tester);

    _mark('step5-mentor');
    // ── 5. 멘토 로그인 → 동일 셸 → 로그아웃 ────────────────────────────────
    await _login(tester, _mentorEmail, _mentorPw);
    await _pumpUntil(tester, find.byType(NavigationBar),
        reason: '멘토 로그인 후 홈 셸');
    await _settle(tester, seconds: 6);
    _expectNoErrorText(tester, where: '멘토 질문방 탭');
    await _openMyPage(tester);
    await _logoutFromMyPage(tester);

    _mark('step6-admin');
    // ── 6. 관리자 로그인 → 차단 화면(학생·멘토 전용) → 로그아웃 ───────────────
    if (_adminEmail.isNotEmpty) {
      await _login(tester, _adminEmail, _adminPw);
      await _pumpUntil(tester, find.text('앱을 이용할 수 없어요'),
          reason: '관리자 차단 화면');
      expect(find.textContaining('학생·멘토 전용'), findsOneWidget,
          reason: '관리자 차단 안내 문구');
      expect(find.text('다시 시도'), findsNothing,
          reason: '관리자 차단은 재시도 불가(비재시도형)');
      await tester.tap(find.text('로그아웃'));
      await _pumpUntil(tester, find.text('로그인'), reason: '차단 화면 로그아웃 복귀');
    }
}

/// 텍스트 입력 — enterText 가 웹(profile/release)에서 컨트롤러에 반영되지 않는
/// 사례가 있어(서버로 빈 값 전송 확인), 반영 여부를 검증하고 컨트롤러 직접 세팅으로
/// 폴백한다. 값 자체는 로그에 남기지 않는다(길이만).
Future<void> _type(WidgetTester tester, Finder field, String text,
    {required String label}) async {
  await tester.enterText(field, text);
  await tester.pump(const Duration(milliseconds: 100));
  final TextField tf = tester.widget<TextField>(field);
  if ((tf.controller?.text ?? '') != text) {
    tf.controller?.text = text;
    await tester.pump(const Duration(milliseconds: 100));
  }
  _mark('typed $label len=${tf.controller?.text.length ?? -1}');
}

/// 하단 탭 전환 — NavigationBar 안의 라벨을 찾을 때까지 폴링 후 탭.
Future<void> _tapTab(WidgetTester tester, String label) async {
  final Finder tab = find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label));
  await _pumpUntil(tester, tab, reason: '하단 탭 "$label" 대기');
  await tester.tap(tab);
  await tester.pump(const Duration(milliseconds: 400));
}

/// 로그인 화면에서 이메일/비밀번호 입력 → 로그인 버튼.
Future<void> _login(WidgetTester tester, String email, String pw) async {
  await _pumpUntil(tester, find.text('로그인'), reason: '로그인 화면 표시');
  final Finder fields = find.byType(TextField);
  expect(fields, findsNWidgets(2), reason: '이메일/비밀번호 입력 필드');
  await _type(tester, fields.at(0), email, label: 'email');
  await _type(tester, fields.at(1), pw, label: 'pw');
  await tester.pump(const Duration(milliseconds: 300));
  // PrimaryButton 의 실제 위젯은 FilledButton (design/widgets/primary_button.dart).
  final Finder loginButton =
      find.widgetWithText(FilledButton, '로그인').hitTestable();
  if (tester.any(loginButton)) {
    await tester.tap(loginButton.first);
  } else {
    // 폴백: 버튼 라벨 텍스트 직접 탭(0매치 tap 은 예외라 사전 확인 필수).
    await tester.tap(find.text('로그인').hitTestable().last);
  }
  await tester.pump(const Duration(seconds: 1));
}

/// 우상단 프로필(마이페이지) 진입.
Future<void> _openMyPage(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.person_rounded).hitTestable());
  await _pumpUntil(tester, find.text('마이페이지'), reason: '마이페이지 진입');
  await _settle(tester, seconds: 5); // 구독/캐시/설정 실조회
}

/// 마이페이지 설정 섹션까지 스크롤 후 로그아웃 → 로그인 화면 복귀.
Future<void> _logoutFromMyPage(WidgetTester tester) async {
  final Finder logout = find.text('로그아웃');
  await _scrollTo(tester, logout);
  await tester.tap(logout.hitTestable());
  await _pumpUntil(tester, find.text('로그인'),
      timeout: const Duration(seconds: 30), reason: '로그아웃 후 로그인 화면 복귀');
}

Future<void> _goBack(WidgetTester tester) async {
  final Finder back = find.byTooltip('Back');
  if (tester.any(back)) {
    await tester.tap(back.first);
  } else {
    await tester.pageBack();
  }
  await tester.pump(const Duration(seconds: 1));
}

/// 스크롤 가능한 첫 Scrollable 에서 대상이 보일 때까지 드래그.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (int i = 0; i < 12 && !tester.any(target.hitTestable()); i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -240),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
  }
  expect(target.hitTestable(), findsWidgets, reason: '스크롤로 대상 노출');
}

/// 실네트워크 폴링 — pumpAndSettle 은 realtime/타이머로 영원히 안 정착할 수 있어
/// 고정 주기 pump + finder 폴링으로 대기한다.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 400));
    if (tester.any(finder)) return;
  }
  _mark('TIMEOUT: ${reason ?? finder.toString()}');
  expect(finder, findsWidgets, reason: reason ?? '대기 시간 초과');
}

/// 고정 시간 동안 주기 pump(실네트워크 로드 대기).
Future<void> _settle(WidgetTester tester, {required int seconds}) async {
  final DateTime end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// 화면에 friendlyError 계열 문구가 떠 있지 않은지 확인(느슨한 네거티브 체크).
void _expectNoErrorText(WidgetTester tester, {required String where}) {
  for (final String s in <String>['오류가 발생했', '실패했어요', '연결되어 있지 않아요']) {
    expect(find.textContaining(s), findsNothing, reason: '$where 에 에러 문구 없음');
  }
}
