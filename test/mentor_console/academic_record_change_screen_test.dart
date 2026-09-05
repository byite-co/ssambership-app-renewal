import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/academic_record_change_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';
import '../support/fake_scan_port.dart';
import '../support/mentor_document_fixtures.dart';

/// 학적 변경 요청(A-4a #5) — 학교명 필수·40자 / 사유 선택·100자 / 서류 필수 / 검토 중 잠금.
void main() {
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(FakeMentorConsole port, {FakeScanPort? scan}) => withTestAppScope(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: AcademicRecordChangeScreen(
            portOverride: port,
            scanPicker: scan ?? FakeScanPort(result: jpgDocument()),
          ),
        ),
        auth: TestAppAuth(role: AppRole.mentor, userId: 'm1'),
      );

  Finder fieldUnder(String label) => find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(Column),
        ).first,
        matching: find.byType(TextField),
      );

  Future<void> pickDocument(WidgetTester tester) async {
    await tester.tap(find.text('서류 선택하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('파일'));
    await tester.pumpAndSettle();
  }

  testWidgets('학교명 + 서류가 있어야 제출 · 사유는 비우면 null 로 보낸다', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole();
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    expect(find.text('학적 변경을 요청할 수 있어요'), findsOneWidget);
    await pickDocument(tester);
    await tester.tap(find.text('변경 요청 제출하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty); // 학교명 없음.

    await tester.enterText(fieldUnder('변경할 학교명'), '  연세대학교 ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('변경 요청 제출하기'));
    await tester.pumpAndSettle();

    expect(port.calls.single['name'], 'submitAcademicRecordChange');
    expect(port.calls.single['university'], '연세대학교');
    expect(port.calls.single['reason'], isNull);
    expect(port.calls.single['kind'], 'jpg');
    expect(find.text('학적 변경 요청을 제출했어요. 결과는 알림으로 알려드릴게요.'),
        findsOneWidget);
    // 재조회 → 검토 중 + 잠금.
    expect(find.text('요청을 검토하고 있어요'), findsOneWidget);
    expect(find.text('변경 요청 제출하기'), findsNothing);
    expect(find.text('검토 중'), findsOneWidget); // 기록 배지.
  });

  testWidgets('41자 학교명·101자 사유는 사유 문장 + 제출 잠금', (WidgetTester tester) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole();
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    await pickDocument(tester);

    await tester.enterText(fieldUnder('변경할 학교명'), '가' * 41);
    await tester.pumpAndSettle();
    expect(find.text('학교명은 40자까지 입력할 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('변경 요청 제출하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);

    await tester.enterText(fieldUnder('변경할 학교명'), '고려대학교');
    await tester.enterText(fieldUnder('변경 사유 (선택)'), '나' * 101);
    await tester.pumpAndSettle();
    expect(find.text('사유는 100자까지 입력할 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('변경 요청 제출하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);

    await tester.enterText(fieldUnder('변경 사유 (선택)'), '편입');
    await tester.pumpAndSettle();
    await tester.tap(find.text('변경 요청 제출하기'));
    await tester.pumpAndSettle();
    expect(port.calls.single['reason'], '편입');
  });

  testWidgets('검토 중이면 폼 대신 안내 · 승인·반려 상태 문구', (WidgetTester tester) async {
    tallSurface(tester);
    final FakeMentorConsole pending = FakeMentorConsole(
      academicChanges: <AcademicRecordChangeRecord>[
        AcademicRecordChangeRecord(
          id: 'a1',
          status: ReviewStatus.pending,
          requestedUniversityName: '연세대학교',
          createdAt: DateTime(2026, 8, 1),
        ),
      ],
    );
    await tester.pumpWidget(app(pending));
    await tester.pumpAndSettle();
    expect(find.text('연세대학교(으)로 변경 요청 · 보통 영업일 2일 안에 끝나요'),
        findsOneWidget);
    expect(find.text('서류 선택하기'), findsNothing);
    expect(find.text('검토가 끝나면 새 요청을 보낼 수 있어요. 결과는 알림으로 알려드릴게요.'),
        findsOneWidget);

    final FakeMentorConsole approved = FakeMentorConsole(
      academicChanges: <AcademicRecordChangeRecord>[
        AcademicRecordChangeRecord(
          id: 'a2',
          status: ReviewStatus.approved,
          requestedUniversityName: '연세대학교',
          approvedUniversityName: '연세대학교',
          reviewedAt: DateTime(2026, 8, 5, 10),
          createdAt: DateTime(2026, 8, 1),
        ),
        AcademicRecordChangeRecord(
          id: 'a0',
          status: ReviewStatus.rejected,
          requestedUniversityName: '고려대학교',
          rejectReason: '서류가 흐려요.',
          createdAt: DateTime(2026, 7, 1),
        ),
      ],
    );
    // 같은 위치의 State 재사용을 막아 새 fixture 로 다시 조회하게 한다.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(approved));
    await tester.pumpAndSettle();
    expect(find.text('연세대학교(으)로 변경됐어요'), findsOneWidget);
    expect(find.text('2026년 8월 5일에 승인됐어요'), findsOneWidget);
    expect(find.text('서류 선택하기'), findsOneWidget); // 승인 뒤엔 새 요청 가능.
    expect(find.text('승인'), findsOneWidget);
    expect(find.text('반려'), findsOneWidget);
  });

  testWidgets('제출 실패는 인라인 오류로 남고 입력은 유지된다', (WidgetTester tester) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole()
      ..failWith = const AppError('업로드 실패');
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    await pickDocument(tester);
    await tester.enterText(fieldUnder('변경할 학교명'), '연세대학교');
    await tester.pumpAndSettle();
    await tester.tap(find.text('변경 요청 제출하기'));
    await tester.pumpAndSettle();
    expect(find.text('업로드 실패'), findsOneWidget);
    expect(find.text('certificate.jpg'), findsOneWidget);
    expect(
      tester.widget<TextField>(fieldUnder('변경할 학교명')).controller!.text,
      '연세대학교',
    );
  });
}
