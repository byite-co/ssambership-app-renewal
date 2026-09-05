import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/core/scan/scan_source_picker.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/education_verification_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';
import '../support/fake_scan_port.dart';
import '../support/mentor_document_fixtures.dart';

/// 학력 인증(A-4a #4) — 4상태 · 서류 검증(형식/크기) · 제출 · 검토 중 잠금 · 실패 인라인.
void main() {
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(FakeMentorConsole port, {FakeScanPort? scan}) => withTestAppScope(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: EducationVerificationScreen(
            portOverride: port,
            scanPicker: scan ?? FakeScanPort(),
          ),
        ),
        auth: TestAppAuth(role: AppRole.mentor, userId: 'm1'),
      );

  SchoolVerificationRecord record(
    ReviewStatus status, {
    String? doc = 'student-id-images/m1/school-verifications/a.jpg',
    String? reason,
    String? university,
    String? department,
    DateTime? reviewedAt,
  }) =>
      SchoolVerificationRecord(
        id: 'v-${status.name}',
        status: status,
        documentStorageRef: doc,
        rejectReason: reason,
        verifiedUniversityName: university,
        verifiedDepartmentName: department,
        reviewedAt: reviewedAt,
        createdAt: DateTime(2026, 8, 20),
      );

  Future<void> pickViaSheet(WidgetTester tester, String source) async {
    await tester.tap(find.text('서류 선택하기'));
    await tester.pumpAndSettle();
    expect(find.text('서류 올리기'), findsOneWidget);
    await tester.tap(find.text(source));
    await tester.pumpAndSettle();
  }

  testWidgets('미제출: 안내 + 서류 선택 전 버튼 비활성 → 파일(PDF) 선택 → 제출 → 검토 중', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole();
    final FakeScanPort scan = FakeScanPort(result: pdfDocument());
    await tester.pumpWidget(app(port, scan: scan));
    await tester.pumpAndSettle();

    expect(find.text('아직 인증하지 않았어요'), findsOneWidget);
    expect(find.text('서류 제출하기'), findsOneWidget);
    await tester.tap(find.text('서류 제출하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty); // 서류 없이는 비활성.

    await pickViaSheet(tester, '파일');
    expect(scan.calls, <ScanSource>[ScanSource.file]);
    expect(find.text('enrollment.pdf'), findsOneWidget);
    expect(find.text('3KB'), findsOneWidget);

    await tester.tap(find.text('서류 제출하기'));
    await tester.pumpAndSettle();

    expect(port.calls.single['name'], 'submitSchoolVerification');
    expect(port.calls.single['kind'], 'pdf');
    expect(find.text('서류를 제출했어요. 검토 결과는 알림으로 알려드릴게요.'),
        findsOneWidget);
    // 재조회 → 검토 중 상태 + 폼 잠금.
    expect(find.text('서류를 확인하고 있어요'), findsOneWidget);
    expect(find.text('서류 제출하기'), findsNothing);
    expect(find.text('검토가 끝나면 다른 서류로 다시 제출할 수 있어요.'), findsOneWidget);
  });

  testWidgets('형식 밖(WEBP)·20MB 초과는 사유를 보여주고 제출 버튼을 잠근다', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole();
    final FakeScanPort scan = FakeScanPort(result: webpDocument());
    await tester.pumpWidget(app(port, scan: scan));
    await tester.pumpAndSettle();

    await pickViaSheet(tester, '갤러리');
    expect(find.text('JPG, PNG, PDF 형식의 서류만 올릴 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('서류 제출하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);

    // 삭제 후 다시 선택(크기 초과).
    await tester.tap(find.byTooltip('서류 삭제'));
    await tester.pumpAndSettle();
    scan.result = oversizedDocument();
    await pickViaSheet(tester, '촬영');
    expect(find.text('서류는 최대 20MB까지 올릴 수 있어요.'), findsOneWidget);
    await tester.tap(find.text('서류 제출하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);
  });

  testWidgets('반려: 사유 문장 + 다시 제출 가능 / 제출 실패는 인라인 오류', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(
      schoolVerifications: <SchoolVerificationRecord>[
        record(ReviewStatus.rejected, reason: '발급일이 6개월을 넘었어요.'),
      ],
    )..failWith = const AppError('저장소 오류');
    await tester.pumpWidget(app(port, scan: FakeScanPort(result: jpgDocument())));
    await tester.pumpAndSettle();

    expect(find.text('서류가 반려됐어요'), findsOneWidget);
    expect(find.text('발급일이 6개월을 넘었어요.'), findsOneWidget);
    expect(find.text('반려'), findsOneWidget); // 제출 기록 배지.

    await pickViaSheet(tester, '파일');
    await tester.tap(find.text('다시 제출하기'));
    await tester.pumpAndSettle();
    expect(port.calls.single['name'], 'submitSchoolVerification');
    expect(find.text('저장소 오류'), findsOneWidget);
    expect(find.text('certificate.jpg'), findsOneWidget); // 선택은 유지.
  });

  testWidgets('검토 중(서류 없음 · 자동 생성 행)은 구분 문구로 보여주고 잠근다', (
    WidgetTester tester,
  ) async {
    final FakeMentorConsole port = FakeMentorConsole(
      schoolVerifications: <SchoolVerificationRecord>[
        record(ReviewStatus.pending, doc: null),
      ],
    );
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text('서류 없음 · 관리자 확정 대기'), findsOneWidget);
    expect(find.text('서류 없음 · 자동 생성'), findsOneWidget);
    expect(find.text('서류 선택하기'), findsNothing);
  });

  testWidgets('완료: 검증값·승인일 + "다른 서류로 다시 인증하기"로 폼 펼침', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(
      schoolVerifications: <SchoolVerificationRecord>[
        record(
          ReviewStatus.approved,
          university: '서울대학교',
          department: '의예과',
          reviewedAt: DateTime(2026, 3, 12, 9),
        ),
        record(ReviewStatus.superseded),
      ],
    );
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text('인증이 완료됐어요'), findsOneWidget);
    expect(find.text('서울대학교 · 의예과\n2026년 3월 12일에 승인됐어요'),
        findsOneWidget);
    expect(find.text('서류 선택하기'), findsNothing);

    await tester.tap(find.text('다른 서류로 다시 인증하기'));
    await tester.pumpAndSettle();
    expect(find.text('서류 선택하기'), findsOneWidget);
    expect(find.text('다시 제출하기'), findsOneWidget);
  });

  testWidgets('조회 실패 → 오류 + 다시 시도', (WidgetTester tester) async {
    final FakeMentorConsole port = FakeMentorConsole()
      ..loadFailure = const AppError('네트워크 오류');
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text('인증 상태를 불러오지 못했어요'), findsOneWidget);
    port.loadFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('아직 인증하지 않았어요'), findsOneWidget);
  });
}
