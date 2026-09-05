import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/api_web_v1_envelope.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_repository.dart';
import 'package:ssambership_app/features/mypage/ui/sections/mentor_self_service_section.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';
import '../support/fake_scan_port.dart';
import '../support/mentor_document_fixtures.dart';

MentorOwnProfile _profile({
  String status = 'active',
  DateTime? pauseUntil,
  DateTime? terminationAt,
  String? studentId,
}) =>
    MentorOwnProfile(
      userId: 'm1',
      universityName: '서울대학교',
      departmentName: '수학교육과',
      verificationStatus: 'approved',
      activityStatus: status,
      pauseUntil: pauseUntil,
      terminationEffectiveAt: terminationAt,
      studentIdImageUrl: studentId,
    );

final DateTime _now = DateTime(2026, 9, 5, 10);

/// A-4b ④ 활동 상태 · ⑦ 학생증 사후 제출 — 멘토 마이페이지 셀프서비스.
void main() {
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pump(WidgetTester tester, FakeMentorConsole port, {FakeScanPort? scan}) async {
    tallSurface(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(withTestAppScope(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MentorSelfServiceSections(
              port: port,
              scanPicker: scan ?? FakeScanPort(),
              nowOverride: () => _now,
            ),
          ),
        ),
      ),
      auth: TestAppAuth(role: AppRole.mentor, userId: 'm1'),
    ));
    await tester.pumpAndSettle();
  }

  group('활동 상태(④)', () {
    testWidgets('활동 중: 잠시 쉬기 → 기간·사유 시트 → paused(pause_until=now+N일·reason)', (tester) async {
      final FakeMentorConsole port = FakeMentorConsole(profile: _profile())
        ..activityResult = MentorActivityResult(
          activityStatus: 'paused',
          pauseUntil: _now.add(const Duration(days: 3)),
          subscriptionsExtended: 2,
        );
      await pump(tester, port);
      expect(find.text('활동 중'), findsOneWidget);
      expect(find.text('새 구독을 받고 학생 질문에 답하고 있어요.'), findsOneWidget);
      expect(find.textContaining('웹'), findsNothing);

      await tester.tap(find.text('잠시 쉬기'));
      await tester.pumpAndSettle();
      expect(find.text('새 구독만 막히고 지금 학생 질문은 계속 받아요. 쉬는 만큼 구독 학생의 기간이 자동으로 늘어나요.'), findsOneWidget);
      expect(find.text('9월 8일에 자동으로 복귀해요'), findsOneWidget); // 기본 3일.
      await tester.tap(find.text('5일'));
      await tester.pumpAndSettle();
      expect(find.text('9월 10일에 자동으로 복귀해요'), findsOneWidget);
      await tester.tap(find.text('질병 등'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5일 쉬기'));
      await tester.pumpAndSettle();

      final Map<String, Object?> call = port.calls.single;
      expect(call['name'], 'setActivityStatus');
      expect(call['status'], 'paused');
      expect(call['reason'], 'illness');
      expect(call['pauseUntil'], _now.add(const Duration(days: 5)));
      expect(find.text('9월 8일까지 쉬어요. 구독 2건의 기간이 그만큼 늘어나요.'), findsOneWidget);
      // 재조회 → 일시중지 표시.
      expect(find.text('일시중지'), findsOneWidget);
      expect(find.text('지금 복귀하기'), findsOneWidget);
    });

    testWidgets('일시중지: 복귀 시트에 요금제 재활성 안내(결정 5-a) → active', (tester) async {
      final FakeMentorConsole port = FakeMentorConsole(
        profile: _profile(status: 'paused', pauseUntil: _now.add(const Duration(days: 2))),
      )..activityResult = const MentorActivityResult(activityStatus: 'active', plansReactivated: 3);
      await pump(tester, port);
      expect(find.text('9월 7일까지 쉬어요. 새 구독만 막히고 지금 학생 질문은 계속 받아요.'), findsOneWidget);
      await tester.tap(find.text('지금 복귀하기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('요금제 설정에서 꺼둔 요금제도 모두 다시 켜져요'), findsOneWidget);
      await tester.tap(find.text('복귀하기'));
      await tester.pumpAndSettle();
      expect(port.calls.single['status'], 'active');
      expect(find.text('활동을 다시 시작했어요. 요금제 3개를 켰어요.'), findsOneWidget);
    });

    testWidgets('활동 종료 예약: 날짜 선택(최소 14일) → 확인 → terminating · 종료 예정 표시 후 버튼 없음', (tester) async {
      final FakeMentorConsole port = FakeMentorConsole(profile: _profile())
        ..activityResult = MentorActivityResult(
          activityStatus: 'terminating',
          terminationEffectiveAt: _now.add(const Duration(days: 14)),
          notifiedSubscribers: 4,
        );
      await pump(tester, port);
      await tester.tap(find.text('활동 종료 예약'));
      await tester.pumpAndSettle();
      // 날짜 다이얼로그(기본 = +14일) → 선택.
      expect(find.text('선택'), findsOneWidget);
      await tester.tap(find.text('선택'));
      await tester.pumpAndSettle();
      expect(find.text('9월 19일에 활동을 종료할까요?'), findsOneWidget);
      await tester.tap(find.text('종료 예약'));
      await tester.pumpAndSettle();
      expect(port.calls.single['status'], 'terminating');
      expect(port.calls.single['terminationEffectiveAt'], DateTime(2026, 9, 19));
      expect(find.text('9월 19일에 활동이 종료돼요. 구독 학생 4명에게 안내했어요.'), findsOneWidget);
      expect(find.text('종료 예정'), findsOneWidget);
      expect(find.text('잠시 쉬기'), findsNothing);
      expect(find.text('활동 종료 예약'), findsNothing);
    });

    testWidgets('REST_FREQUENCY_LIMIT → 6개월 1회 문구(다음 가능일)', (tester) async {
      final FakeMentorConsole port = FakeMentorConsole(profile: _profile())
        ..failWith = ApiEnvelopeFailure(
          'REST_FREQUENCY_LIMIT',
          activityMessageForCode('REST_FREQUENCY_LIMIT', <String, dynamic>{
            'next_available_at': '2026-12-01T00:00:00Z',
          }),
          const <String, dynamic>{},
        );
      await pump(tester, port);
      await tester.tap(find.text('잠시 쉬기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3일 쉬기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('일반 휴식은 6개월에 한 번이에요.'), findsOneWidget);
      expect(find.text('활동 중'), findsOneWidget); // 상태 그대로.
    });

    test('pause_until 경과 = 활동 중(웹 mentorActivityState 동일)', () {
      expect(mentorActivityState(_profile(status: 'paused', pauseUntil: _now.subtract(const Duration(hours: 1))), now: _now), 'active');
      expect(mentorActivityState(_profile(status: 'paused', pauseUntil: _now.add(const Duration(hours: 1))), now: _now), 'paused');
      expect(mentorActivityState(_profile(status: 'terminated'), now: _now), 'terminated');
      final Map<String, dynamic> params = MentorActivityRequest.pause(
        pauseUntil: DateTime.utc(2026, 9, 8, 1), reason: 'rest',
      ).toParams();
      expect(params, <String, dynamic>{'p_status': 'paused', 'p_pause_until': '2026-09-08T01:00:00.000Z', 'p_reason': 'rest'});
      expect(const MentorActivityRequest.resume().toParams(), <String, dynamic>{'p_status': 'active'});
    });
  });

  group('학생증 사후 제출(⑦)', () {
    testWidgets('미제출 → 서류 선택 → 제출 → RPC 반영 · 제출됨', (tester) async {
      final FakeMentorConsole port = FakeMentorConsole(profile: _profile());
      final FakeScanPort scan = FakeScanPort(result: jpgDocument());
      await pump(tester, port, scan: scan);
      expect(find.text('미제출'), findsOneWidget);
      expect(find.text('아직 학생증을 제출하지 않았어요. 재학 확인에 쓰여요.'), findsOneWidget);
      final FilledButton before = tester.widget(find.widgetWithText(FilledButton, '학생증 제출'));
      expect(before.onPressed, isNull);

      await tester.tap(find.text('서류 선택하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리'));
      await tester.pumpAndSettle();
      expect(find.text('certificate.jpg'), findsOneWidget);
      await tester.ensureVisible(find.text('학생증 제출'));
      await tester.tap(find.text('학생증 제출'));
      await tester.pumpAndSettle();
      expect(port.calls.single['name'], 'submitStudentIdDocument');
      expect(port.calls.single['kind'], 'jpg');
      expect(find.text('학생증을 제출했어요.'), findsOneWidget);
      expect(find.text('제출됨'), findsOneWidget);
    });

    testWidgets('학력 인증 잠정 pending(서류 없음)은 안내만 — 제출을 잠그지 않는다(§7 H)', (tester) async {
      final FakeMentorConsole port = FakeMentorConsole(
        profile: _profile(studentId: 'student-id-images/m1/student-id/a.jpg'),
        schoolVerifications: <SchoolVerificationRecord>[
          SchoolVerificationRecord(id: 'v1', status: ReviewStatus.pending, createdAt: DateTime(2026, 9, 1)),
        ],
      );
      await pump(tester, port, scan: FakeScanPort(result: pdfDocument()));
      expect(find.text('제출됨'), findsOneWidget);
      expect(find.textContaining('서류 없음 · 관리자 확정 대기'), findsOneWidget);
      await tester.tap(find.text('서류 선택하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('파일'));
      await tester.pumpAndSettle();
      final FilledButton btn = tester.widget(find.widgetWithText(FilledButton, '학생증 제출'));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('형식 밖 파일 → 즉시 안내 · 제출 불가', (tester) async {
      final FakeMentorConsole port = FakeMentorConsole(profile: _profile());
      await pump(tester, port, scan: FakeScanPort(result: webpDocument()));
      await tester.tap(find.text('서류 선택하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리'));
      await tester.pumpAndSettle();
      expect(find.text('JPG, PNG, PDF 형식의 서류만 올릴 수 있어요.'), findsOneWidget);
      final FilledButton btn = tester.widget(find.widgetWithText(FilledButton, '학생증 제출'));
      expect(btn.onPressed, isNull);
      expect(port.calls, isEmpty);
    });
  });
}
