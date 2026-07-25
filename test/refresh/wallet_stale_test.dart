import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/refresh/data_refresh_bus.dart';
import 'package:ssambership_app/features/individual_question/data/individual_question_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/mypage_screen.dart';
import 'package:ssambership_app/features/mypage/ui/sections/cash_section.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 세션1.5 보정3 — 환불 성공·재조회 실패 시 stale generation UI.
/// 마지막 정상 캐시는 삭제하지 않되, 환불 이전 잔액을 최신 확정값처럼
/// 표시하지 않는다. 환불 실패 시 낙관적 변경 0(bump 0).

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MyPageData _data({int? balanceCents}) => MyPageData(
      role: AppRole.student,
      profile: const MyProfile(name: '학생', roleLabel: '학생'),
      cash: CashSummary(
        balanceCents: balanceCents,
        recent: balanceCents == null
            ? const <CashEntry>[]
            : <CashEntry>[
                CashEntry(
                    deltaCents: 100000,
                    createdAt: DateTime(2026, 7, 25),
                    reason: 'individual_question_refund'),
              ],
      ),
    );

void main() {
  testWidgets('환불(bump) 후 재조회 실패 → 마지막 정상값 보존 + 최신 정보 아님 + 재시도',
      (WidgetTester tester) async {
    _bigSurface(tester);
    int calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MyPageScreen(loaderOverride: () async {
        calls++;
        if (calls == 2) return _data(balanceCents: null); // 재조회 실패 상태
        return _data(balanceCents: 5000000);
      })),
    ));
    await tester.pumpAndSettle();
    expect(find.text('50,000원'), findsOneWidget);
    expect(find.text('보유 캐시'), findsOneWidget);

    DataRefreshBus.bumpWallet(); // 환불 성공 신호 → 재조회(실패 응답)
    await tester.pumpAndSettle();

    // 마지막 정상 캐시 보존(삭제 금지) — 단 최신 확정값처럼 표시하지 않는다.
    expect(find.text('50,000원'), findsOneWidget);
    expect(find.text('보유 캐시 (최신 정보 아님)'), findsOneWidget);
    expect(find.text('보유 캐시'), findsNothing); // 최신값 표기는 사라져야 한다
    expect(find.text('환불은 완료됐지만 최신 잔액을 불러오지 못했습니다.'), findsOneWidget);
    final Finder retryInCash = find.descendant(
        of: find.byType(CashSection), matching: find.text('다시 시도'));
    expect(retryInCash, findsOneWidget);

    // 재시도 성공 → 배너 제거·최신 잔액·정상 라벨 복귀.
    await tester.tap(retryInCash);
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.text('보유 캐시'), findsOneWidget);
    expect(find.text('보유 캐시 (최신 정보 아님)'), findsNothing);
    expect(find.text('환불은 완료됐지만 최신 잔액을 불러오지 못했습니다.'), findsNothing);
  });

  testWidgets('변경 신호 없는 초기 실패 → 기존 - 표기 유지(배너 없음·회귀 0)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: MyPageScreen(
              loaderOverride: () async => _data(balanceCents: null))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('-'), findsOneWidget);
    expect(find.text('보유 캐시'), findsOneWidget);
    expect(find.text('환불은 완료됐지만 최신 잔액을 불러오지 못했습니다.'), findsNothing);
  });

  testWidgets('환불 RPC 실패 → 지갑 신호 0(낙관적 변경 없음) + 오류 안내',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final int genBefore = DataRefreshBus.walletGeneration.value;
    await tester.pumpWidget(MaterialApp(
      home: IqDetailScreen(
        questionId: 'q-1',
        roleOverride: AppRole.student,
        repositoryOverride: _FailingRefundRepo(),
        loaderOverride: () async => IqDetailData(
          question: IndividualQuestion(
            id: 'q-1',
            studentId: 's1',
            type: IndividualQuestionType.open,
            status: IndividualQuestionStatus.open, // 답변 전 — 질문 취소 가능
            title: '질문',
            body: '본문',
            priceCents: 500000,
            createdAt: DateTime(2026, 7, 1),
          ),
          messages: const <IqMessage>[],
          attachments: const <IqAttachment>[],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('질문 취소 (캐시 환불)'));
    await tester.tap(find.text('질문 취소 (캐시 환불)'));
    await tester.pumpAndSettle();
    // 확인 다이얼로그의 '질문 취소' 확정 버튼.
    await tester.tap(find.text('질문 취소'));
    await tester.pumpAndSettle();

    expect(DataRefreshBus.walletGeneration.value, genBefore,
        reason: '환불 실패 시 지갑 무효화 신호 0(낙관적 성공값 없음)');
    // 낙관적 성공 문구·상태 전이 없음(성공 스낵바 미노출).
    expect(find.textContaining('질문을 취소했어요'), findsNothing);
  });
}

class _FailingRefundRepo extends IndividualQuestionRepository {
  @override
  Future<IqEscrowResult> refund(String questionId) async {
    throw const AppError('환불 처리에 실패했어요.');
  }
}
