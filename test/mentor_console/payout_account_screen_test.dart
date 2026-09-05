import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/payout_account_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';

/// 정산 계좌 등록(A-4a #1) — 은행 시트 선택 · 숫자 8~24 검증 · F13 호출 · 실패 인라인.
void main() {
  /// 기본 테스트 표면(800×600)은 하단 버튼이 화면 밖이라 세로로 넉넉히 잡는다.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(FakeMentorConsole port) => withTestAppScope(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: PayoutAccountScreen(portOverride: port),
        ),
        auth: TestAppAuth(role: AppRole.mentor, userId: 'm1'),
      );

  testWidgets('미등록: 경고 안내 · 은행 선택 + 유효 계좌 입력 전엔 버튼 비활성', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(fullName: '김서연');
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    expect(find.text('아직 계좌가 없어요'), findsOneWidget);
    expect(find.text('김서연'), findsOneWidget); // 예금주 고정.
    expect(find.text('등록하기'), findsOneWidget);

    // 계좌만 입력(은행 미선택) → 비활성.
    await tester.enterText(find.byType(TextField), '3333012345678');
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);

    // 은행 선택.
    await tester.tap(find.text('은행을 선택해 주세요'));
    await tester.pumpAndSettle();
    expect(find.text('은행 선택'), findsWidgets);
    await tester.tap(find.text('카카오뱅크'));
    await tester.pumpAndSettle();
    expect(find.text('카카오뱅크'), findsOneWidget);

    await tester.tap(find.text('등록하기'));
    await tester.pumpAndSettle();

    expect(port.calls.single['name'], 'updatePayoutAccount');
    expect(port.calls.single['bankName'], '카카오뱅크');
    expect(port.calls.single['accountNumber'], '3333012345678');
    expect(find.text('정산 계좌를 등록했어요.'), findsOneWidget);
  });

  testWidgets('7자리·하이픈 섞인 입력은 사유를 보여주고 저장하지 않는다', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole();
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    await tester.tap(find.text('은행을 선택해 주세요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신한은행'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234567');
    await tester.pumpAndSettle();
    expect(find.text('계좌번호는 숫자 8~24자리로 입력해 주세요.'), findsOneWidget);
    await tester.tap(find.text('등록하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);

    // 하이픈은 제거돼 8자리 이상이면 통과.
    await tester.enterText(find.byType(TextField), '110-123-456789');
    await tester.pumpAndSettle();
    expect(find.text('계좌번호는 숫자 8~24자리로 입력해 주세요.'), findsNothing);
    await tester.tap(find.text('등록하기'));
    await tester.pumpAndSettle();
    expect(port.calls.single['accountNumber'], '110123456789');
  });

  testWidgets('서버 거부(승인 전 멘토)는 인라인 실패 문구 · 폼 유지', (
    WidgetTester tester,
  ) async {
    final FakeMentorConsole port = FakeMentorConsole(
      failWith: const AppError('멘토 승인이 완료된 뒤에 할 수 있어요.'),
    );
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.text('은행을 선택해 주세요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('토스뱅크'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '100012345678');
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록하기'));
    await tester.pumpAndSettle();

    expect(find.text('멘토 승인이 완료된 뒤에 할 수 있어요.'), findsOneWidget);
    expect(find.text('등록하기'), findsOneWidget); // 폼 그대로.
    expect(find.byType(PayoutAccountScreen), findsOneWidget);
  });

  testWidgets('이미 등록: 마스킹 계좌 표시 + "계좌 변경하기"', (WidgetTester tester) async {
    final FakeMentorConsole port = FakeMentorConsole(
      payoutAccount: const PayoutAccountInfo(
        bankName: '우리은행',
        accountMasked: '********9012',
      ),
    );
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text('우리은행 ********9012'), findsOneWidget);
    expect(find.text('계좌 변경하기'), findsOneWidget);
    expect(find.textContaining('9012'), findsOneWidget); // 원문 노출 0.
  });

  testWidgets('조회 실패 → 다시 시도 노출', (WidgetTester tester) async {
    final FakeMentorConsole port =
        FakeMentorConsole(loadFailure: const AppError('연결 오류'));
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text('계좌 정보를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    port.loadFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('등록하기'), findsOneWidget);
  });
}
