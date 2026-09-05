import 'dart:async';

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
import '../support/app_scope_test_harness.dart';

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
    await tester.pumpScopedWidget(MaterialApp(
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
    expect(find.text('캐시 변경은 완료됐지만 최신 잔액을 불러오지 못했습니다.'), findsOneWidget);
    final Finder retryInCash = find.descendant(
        of: find.byType(CashSection), matching: find.text('다시 시도'));
    expect(retryInCash, findsOneWidget);

    // 재시도 성공 → 배너 제거·최신 잔액·정상 라벨 복귀.
    await tester.tap(retryInCash);
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.text('보유 캐시'), findsOneWidget);
    expect(find.text('보유 캐시 (최신 정보 아님)'), findsNothing);
    expect(find.text('캐시 변경은 완료됐지만 최신 잔액을 불러오지 못했습니다.'), findsNothing);
  });

  group('v19 보정1 — 실제 Future.error·cash null·일반 재조회', () {
    testWidgets('bump 후 loader Future.error → 전체 화면 보존·stale·공통 안내·재시도',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _SeqLoader loader = _SeqLoader(<Object>[
        _data(balanceCents: 5000000),
        StateError('timeout'), // 실제 Future 예외
        _data(balanceCents: 6000000),
      ]);
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: loader.call))));
      await tester.pumpAndSettle();
      expect(find.text('50,000원'), findsOneWidget);

      DataRefreshBus.bumpWallet();
      await tester.pumpAndSettle();

      // 전체 오류 화면으로 교체되지 않는다 — 마지막 정상 마이페이지 보존.
      expect(find.textContaining('내 정보를 불러오지 못했어요'), findsNothing);
      expect(find.text('50,000원'), findsOneWidget);
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsOneWidget);
      // 비단정 공통 안내(원인 추정·환불 단정 없음) + 재시도.
      expect(find.text('캐시 변경은 완료됐지만 최신 잔액을 불러오지 못했습니다.'), findsOneWidget);
      // 원장 라벨('개별질문 환불')은 정당 — '환불 완료' 단정 문구만 금지.
      expect(find.textContaining('환불은 완료됐지만'), findsNothing);
      expect(find.text('최신 정보를 불러오지 못했습니다.'), findsOneWidget);

      // 재시도 성공 → stale 해제·최신 잔액.
      final Finder retry = find.descendant(
          of: find.byType(CashSection), matching: find.text('다시 시도'));
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('60,000원'), findsOneWidget);
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsNothing);
    });

    testWidgets('bump 후 data.cash == null → 기존 정상 지갑 보존 + stale',
        (WidgetTester tester) async {
      _bigSurface(tester);
      const MyPageData noCash = MyPageData(
        role: AppRole.student,
        profile: MyProfile(name: '학생', roleLabel: '학생'),
      );
      final _SeqLoader loader =
          _SeqLoader(<Object>[_data(balanceCents: 5000000), noCash]);
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: loader.call))));
      await tester.pumpAndSettle();

      DataRefreshBus.bumpWallet();
      await tester.pumpAndSettle();
      expect(find.text('50,000원'), findsOneWidget); // 보존
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsOneWidget);
    });

    testWidgets('stale 재시도 실패 → stale 유지·정상 데이터 삭제 0',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _SeqLoader loader = _SeqLoader(<Object>[
        _data(balanceCents: 5000000),
        StateError('e1'),
        StateError('e2'), // 재시도도 실패
      ]);
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: loader.call))));
      await tester.pumpAndSettle();
      DataRefreshBus.bumpWallet();
      await tester.pumpAndSettle();

      final Finder retry = find.descendant(
          of: find.byType(CashSection), matching: find.text('다시 시도'));
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('50,000원'), findsOneWidget); // 여전히 보존
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsOneWidget); // stale 유지
    });

    testWidgets('일반 재조회(resumed·비지갑) Future.error → 마지막 정상 화면 + 비단정 안내',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _SeqLoader loader = _SeqLoader(
          <Object>[_data(balanceCents: 5000000), StateError('offline')]);
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: loader.call))));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // 초기 로드 실패(전체 오류)와 구분 — 마지막 정상 화면 보존.
      expect(find.textContaining('내 정보를 불러오지 못했어요'), findsNothing);
      expect(find.text('50,000원'), findsOneWidget);
      expect(find.text('최신 정보를 불러오지 못했습니다.'), findsOneWidget);
      // 지갑 신호가 아니므로 지갑 stale 문구·환불 문구는 없다.
      expect(find.text('캐시 변경은 완료됐지만 최신 잔액을 불러오지 못했습니다.'), findsNothing);
      expect(find.textContaining('환불은 완료됐지만'), findsNothing);
      expect(find.text('보유 캐시'), findsOneWidget);
      // 재시도 제공(페이지 배너).
      expect(find.text('다시 시도'), findsWidgets);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    });

    testWidgets('초기 로드부터 Future.error·정상 스냅샷 없음 → 기존 전체 오류 UI',
        (WidgetTester tester) async {
      _bigSurface(tester);
      await tester.pumpScopedWidget(MaterialApp(
        home: Scaffold(
            body: MyPageScreen(
                loaderOverride: () =>
                    Future<MyPageData>.error(StateError('down')))),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('내 정보를 불러오지 못했어요'), findsOneWidget);
    });

    testWidgets('build 반복 호출 → 렌더링 경로 상태 변경 0(로더 재호출·상태 전이 없음)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _SeqLoader loader =
          _SeqLoader(<Object>[_data(balanceCents: 5000000)]);
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: loader.call))));
      await tester.pumpAndSettle();
      final int callsAfterFirst = loader.calls;
      // 강제 리빌드 수차례 — _cashSectionFor 등 렌더 경로는 순수여야 한다.
      for (int i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(loader.calls, callsAfterFirst);
      expect(find.text('50,000원'), findsOneWidget);
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsNothing);
    });
  });

  group('v20 정정1 — 수동 재시도 single-flight·외부 최신성 신호 supersede', () {
    testWidgets('stale 재시도 연타 → 추가 loader 정확히 1회(병렬 수동 요청 0)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _GateLoader gate = _GateLoader();
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: gate.call))));
      gate.completers[0].complete(_data(balanceCents: 5000000));
      await tester.pumpAndSettle();

      DataRefreshBus.bumpWallet();
      await tester.pump();
      gate.completers[1].completeError(StateError('e'));
      await tester.pumpAndSettle();
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsOneWidget);
      expect(gate.calls, 2);

      final Finder retry = find.descendant(
          of: find.byType(CashSection), matching: find.text('다시 시도'));
      // 연타: 두 번째 탭은 리빌드 전(콜백 no-op 가드), 세 번째는 비활성 버튼.
      await tester.tap(retry);
      await tester.tap(retry);
      await tester.pump();
      await tester.tap(retry, warnIfMissed: false);
      expect(gate.calls, 3, reason: '연타에도 추가 loader 는 정확히 1회');

      // 진행 중 요청 종료(성공) → 최신 데이터·stale 해제·재시도 가능 복구.
      gate.completers[2].complete(_data(balanceCents: 6000000));
      await tester.pumpAndSettle();
      expect(find.text('60,000원'), findsOneWidget);
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsNothing);
    });

    testWidgets('일반 오류 배너 재시도 연타 → 추가 loader 정확히 1회',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _GateLoader gate = _GateLoader();
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: gate.call))));
      gate.completers[0].complete(_data(balanceCents: 5000000));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      gate.completers[1].completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('최신 정보를 불러오지 못했습니다.'), findsOneWidget);

      // 페이지 배너 버튼만 지정(SettingsSection 자체 '다시 시도'와 구분).
      final Finder retry =
          find.byKey(const ValueKey<String>('mypage-reload-retry'));
      await tester.tap(retry);
      await tester.tap(retry);
      await tester.pump();
      expect(gate.calls, 3, reason: '연타에도 추가 loader 는 정확히 1회');

      gate.completers[2].complete(_data(balanceCents: 6000000));
      await tester.pumpAndSettle();
      expect(find.text('60,000원'), findsOneWidget);
      expect(find.text('최신 정보를 불러오지 못했습니다.'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    });

    testWidgets('로딩 중 두 재시도 버튼 비활성(shared guard) → 종료 후 복구·재시도 가능',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _GateLoader gate = _GateLoader();
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: gate.call))));
      gate.completers[0].complete(_data(balanceCents: 5000000));
      await tester.pumpAndSettle();

      // bump 실패 → stale 배너 + 일반 배너(두 버튼 동시 노출).
      DataRefreshBus.bumpWallet();
      await tester.pump();
      gate.completers[1].completeError(StateError('e'));
      await tester.pumpAndSettle();

      final Finder cashRetry = find.descendant(
          of: find.byType(CashSection), matching: find.text('다시 시도'));
      final Finder cashRetryBtn = find.descendant(
          of: find.byType(CashSection),
          matching: find.widgetWithText(TextButton, '다시 시도'));
      final Finder bannerRetryBtn =
          find.byKey(const ValueKey<String>('mypage-reload-retry'));
      await tester.tap(cashRetry); // 재시도 시작(in-flight)
      await tester.pump();

      // 로딩 중: 두 버튼 모두 onPressed=null(같은 _loading 가드 공유).
      expect(tester.widget<TextButton>(cashRetryBtn).onPressed, isNull,
          reason: '로딩 중 CashSection 재시도 비활성');
      expect(tester.widget<TextButton>(bannerRetryBtn).onPressed, isNull,
          reason: '로딩 중 페이지 배너 재시도 비활성');
      await tester.tap(cashRetry, warnIfMissed: false);
      await tester.tap(bannerRetryBtn, warnIfMissed: false);
      expect(gate.calls, 3, reason: '두 버튼이 서로 다른 loader 를 시작하지 않음');

      // 재시도 실패 종료 → stale·마지막 정상 데이터 유지 + 재시도 재활성.
      gate.completers[2].completeError(StateError('again'));
      await tester.pumpAndSettle();
      expect(find.text('50,000원'), findsOneWidget);
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsOneWidget);
      expect(tester.widget<TextButton>(cashRetryBtn).onPressed, isNotNull,
          reason: '종료 후 재시도 가능 복구');
      expect(tester.widget<TextButton>(bannerRetryBtn).onPressed, isNotNull);
      await tester.tap(cashRetry);
      expect(gate.calls, 4, reason: '복구 후 재시도는 새 loader 1회');
      gate.completers[3].complete(_data(balanceCents: 6000000));
      await tester.pumpAndSettle();
      expect(find.text('60,000원'), findsOneWidget);
    });

    testWidgets('일반 재조회 진행 중 wallet mutation → 최신 조회 유실 0·이전 응답이 덮지 않음',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _GateLoader gate = _GateLoader();
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: gate.call))));
      gate.completers[0].complete(_data(balanceCents: 5000000));
      await tester.pumpAndSettle();

      // 일반 재조회(resume) 시작 — 완료 전에 지갑 mutation 발생.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      DataRefreshBus.bumpWallet();
      await tester.pump();
      expect(gate.calls, 3, reason: 'mutation 은 loading guard 로 유실되지 않는다');

      // 이전(mutation 이전) 응답이 늦게 도착 — 최신 상태를 덮으면 안 된다.
      gate.completers[1].complete(_data(balanceCents: 5500000));
      await tester.pumpAndSettle();
      expect(find.text('55,000원'), findsNothing, reason: '늦은 이전 응답 폐기');
      expect(find.text('50,000원'), findsOneWidget);

      // mutation 이후 최신 조회 완료 → 확정 반영·stale 해제.
      gate.completers[2].complete(_data(balanceCents: 6000000));
      await tester.pumpAndSettle();
      expect(find.text('60,000원'), findsOneWidget);
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    });

    testWidgets('진행 중 요청과 resume 중첩 → supersede 정확히 1회·무한 호출 0',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _GateLoader gate = _GateLoader();
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: gate.call))));
      gate.completers[0].complete(_data(balanceCents: 5000000));
      await tester.pumpAndSettle();

      DataRefreshBus.bumpWallet(); // in-flight 지갑 재조회
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(gate.calls, 3, reason: 'resume supersede 정확히 1회');

      gate.completers[1].completeError(StateError('old')); // 폐기 대상
      gate.completers[2].complete(_data(balanceCents: 6000000));
      await tester.pumpAndSettle();
      expect(find.text('60,000원'), findsOneWidget);
      expect(find.text('보유 캐시 (최신 정보 아님)'), findsNothing,
          reason: '최신 확정값 확인 → stale 해제');
      expect(gate.calls, 3, reason: '반복·무한 호출 0');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    });

    testWidgets('dispose 후 늦은 완료·외부 신호 → 상태 반영·loader 추가 호출 0',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final _GateLoader gate = _GateLoader();
      await tester.pumpScopedWidget(MaterialApp(
          home: Scaffold(body: MyPageScreen(loaderOverride: gate.call))));
      expect(gate.calls, 1); // 초기 로드 in-flight

      await tester.pumpScopedWidget(const SizedBox.shrink()); // dispose
      DataRefreshBus.bumpWallet(); // listener 해제 확인
      await tester.pump();
      expect(gate.calls, 1, reason: 'dispose 후 외부 신호로 loader 추가 호출 0');

      gate.completers[0].complete(_data(balanceCents: 5000000)); // 늦은 완료
      await tester.pump(); // mounted 가드 — setState-after-dispose 예외 없어야 함
    });
  });

  testWidgets('변경 신호 없는 초기 실패 → 기존 - 표기 유지(배너 없음·회귀 0)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpScopedWidget(MaterialApp(
      home: Scaffold(
          body: MyPageScreen(
              loaderOverride: () async => _data(balanceCents: null))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('-'), findsOneWidget);
    expect(find.text('보유 캐시'), findsOneWidget);
    expect(find.text('캐시 변경은 완료됐지만 최신 잔액을 불러오지 못했습니다.'), findsNothing);
  });

  testWidgets('환불 RPC 실패 → 지갑 신호 0(낙관적 변경 없음) + 오류 안내',
      (WidgetTester tester) async {
    _bigSurface(tester);
    final int genBefore = DataRefreshBus.walletGeneration.value;
    await tester.pumpScopedWidget(MaterialApp(
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

/// v20 정정1 — Completer 게이트 loader: 요청을 in-flight 로 붙잡아 두고
/// 테스트가 완료 시점(성공/실패)을 직접 제어한다. calls = 시작된 요청 수.
class _GateLoader {
  final List<Completer<MyPageData>> completers = <Completer<MyPageData>>[];

  int get calls => completers.length;

  Future<MyPageData> call() {
    final Completer<MyPageData> c = Completer<MyPageData>();
    completers.add(c);
    return c.future;
  }
}

/// v19 보정1 — 실제 Future.error·cash null·일반 재조회 실패·초기 실패 매트릭스.
class _SeqLoader {
  _SeqLoader(this.steps);

  /// 각 호출이 소비하는 스텝: MyPageData 또는 Object(에러로 throw).
  final List<Object> steps;
  int calls = 0;

  Future<MyPageData> call() {
    final Object step = steps[calls < steps.length ? calls : steps.length - 1];
    calls++;
    if (step is MyPageData) return Future<MyPageData>.value(step);
    return Future<MyPageData>.error(step);
  }
}
