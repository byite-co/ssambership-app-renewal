import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_route_paths.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/iq_flags.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/student_iq_list_screen.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mentors/ui/mentor_detail_screen.dart';
import '../support/app_scope_test_harness.dart';

/// 제품 경계 계약(A-4a, 2026-09-05 — 오너 결정 ②로 2026-08-05 "웹 전용" 경계를 대체):
/// 신규 개별질문 등록은 **앱 네이티브**(`/iq/new`)에서 한다.
///
/// - 등록 화면은 잔액을 먼저 보여주고, 부족하면 "잔액이 부족해요" 사실 안내 +
///   등록 버튼 비활성까지만 한다.
/// - **충전 유도 0**: '충전' 문구·버튼·링크·인앱 브라우저가 등록 경로 어디에도 없다.
/// - 두 CTA(학생 목록·멘토 상세)는 웹 브릿지가 아니라 네이티브 등록 화면을 연다.
/// - 조회·상세·답변·첨부·첨삭은 이 경계와 무관하게 유지된다(별도 스위트가 보증).
///
/// 정적 검색 + 화면 탭 양쪽으로 고정한다 — 한쪽만으로는 재배선(정적)이나
/// 죽은 배선(동적)을 놓칠 수 있다.
void main() {
  List<File> productionDartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList(growable: false);

  // ───────────────────────── 정적: 네이티브 등록 개방 ─────────────────────────
  group('정적 경계: 네이티브 등록 개방 · 충전 유도 0', () {
    test('등록 CTA 플래그는 기본 on 이다(릴리즈 워크플로는 dart-define 을 쓰지 않는다)', () {
      expect(kIndividualQuestionCreateEnabled, isTrue);
    });

    test('route table 에 /iq/new 가 있고 :questionId 보다 먼저 온다', () {
      final String routes =
          File('lib/app/routes/individual_question_routes.dart')
              .readAsStringSync();
      final int newAt = routes.indexOf('AppRoutePaths.newIndividualQuestion');
      final int detailAt = routes.indexOf(':questionId');
      expect(newAt, greaterThanOrEqualTo(0));
      expect(newAt, lessThan(detailAt),
          reason: "'new' 가 질문 id 로 매칭되지 않도록 먼저 등록한다");
      expect(AppRoutePaths.newIndividualQuestion, '/iq/new');
      expect(AppRoutePaths.newIndividualQuestionFor('m1'), '/iq/new?mentor=m1');
    });

    test('등록 경로(화면·CTA·라우트)에 충전 문구·웹 브릿지 호출이 없다', () {
      const List<String> paths = <String>[
        'lib/features/individual_question/ui/iq_create_screen.dart',
        'lib/features/individual_question/ui/student_iq_list_screen.dart',
        'lib/features/mentors/ui/mentor_detail_screen.dart',
        'lib/app/routes/individual_question_routes.dart',
      ];
      for (final String p in paths) {
        final String src = File(p).readAsStringSync();
        // 주석은 정책 설명에 '충전' 을 쓸 수 있다 — 코드(문자열·식별자)만 검사.
        final String code = src
            .split('\n')
            .where((String l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('충전'), isFalse, reason: '충전 유도 문구 금지: $p');
        expect(src.contains('openIqCreateWeb'), isFalse,
            reason: '등록 CTA 는 웹 브릿지를 쓰지 않는다: $p');
        expect(src.contains('web_bridge'), isFalse,
            reason: '등록 경로에서 web_bridge import 0: $p');
      }
    });

    test('production 에서 IqCreateScreen 을 여는 곳은 라우트·두 CTA 뿐이다', () {
      final RegExp ctor = RegExp(r'\bIqCreateScreen\s*\(');
      final Set<String> callers = <String>{};
      for (final File f in productionDartFiles()) {
        if (f.path.endsWith('iq_create_screen.dart')) continue;
        if (ctor.hasMatch(f.readAsStringSync())) callers.add(f.path);
      }
      expect(callers, <String>{
        'lib/app/routes/individual_question_routes.dart',
        'lib/features/individual_question/ui/student_iq_list_screen.dart',
        'lib/features/mentors/ui/mentor_detail_screen.dart',
      });
    });

    test('목록→상세(조회) 배선은 유지된다', () {
      final String list = File(
              'lib/features/individual_question/ui/student_iq_list_screen.dart')
          .readAsStringSync();
      expect(list.contains('IqDetailScreen('), isTrue,
          reason: '개방 작업은 등록만 연다 — 기존 질문 상세 진입은 보존');
    });
  });

  // ───────────────────────── 화면: 잔액 검사 · 충전 유도 0 ─────────────────────────
  IndividualQuestion question({String id = 'q1'}) => IndividualQuestion(
        id: id,
        studentId: 's1',
        type: IndividualQuestionType.open,
        status: IndividualQuestionStatus.open,
        title: '수열 질문이에요',
        body: '문제 본문',
        priceCents: 500000,
        createdAt: DateTime(2026, 7, 1),
      );

  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('등록 화면: 잔액 검사', () {
    testWidgets('지정형 · 잔액 부족 → "잔액이 부족해요" + 등록 비활성 + 충전 문구 0',
        (WidgetTester tester) async {
      bigSurface(tester);
      int submits = 0;
      await tester.pumpScopedWidget(MaterialApp(
        home: IqCreateScreen(
          mentorId: 'm1',
          mentorName: '멘토A',
          prefillOverride: () async => const IqCreatePrefill(
            balanceCents: 100000, // 1,000캐시
            pricing: IqPricing(mentorId: 'm1', amountCents: 250000), // 2,500캐시
          ),
          submitOverride: ({
            required IndividualQuestionType type,
            required String title,
            required String body,
            int? amountCents,
            String? designatedMentorId,
            String? idempotencyKey,
          }) async {
            submits++;
            return question();
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1,000캐시'), findsOneWidget); // 잔액 먼저.
      expect(find.text('2,500캐시'), findsOneWidget); // 결제될 금액.
      expect(find.text('잔액이 부족해요'), findsOneWidget);
      expect(find.textContaining('충전'), findsNothing);
      expect(find.textContaining('웹'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, '제목'), '제목');
      await tester.enterText(find.widgetWithText(TextField, '질문 내용'), '내용');
      await tester.tap(find.text('질문 등록'));
      await tester.pumpAndSettle();
      expect(find.text('질문을 등록할까요?'), findsNothing);
      expect(submits, 0);
    });

    testWidgets('공개형 · 금액 입력이 잔액을 넘으면 즉시 부족 안내, 줄이면 다시 활성',
        (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpScopedWidget(MaterialApp(
        home: IqCreateScreen(
          prefillOverride: () async =>
              const IqCreatePrefill(balanceCents: 300000), // 3,000캐시
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('충전'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, '질문 금액 (캐시)'), '5000');
      await tester.pumpAndSettle();
      expect(find.text('잔액이 부족해요'), findsOneWidget);
      expect(find.textContaining('충전'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, '질문 금액 (캐시)'), '2000');
      await tester.pumpAndSettle();
      expect(find.text('잔액이 부족해요'), findsNothing);
      expect(find.text('1,000캐시'), findsOneWidget); // 등록 후 남는 캐시.
    });
  });

  // ───────────────────────── CTA → 네이티브 등록 화면 ─────────────────────────
  group('학생 목록 CTA', () {
    testWidgets('"새 개별질문 (공개형)" 탭 → 네이티브 등록 화면(공개형)',
        (WidgetTester tester) async {
      await tester.pumpScopedWidget(MaterialApp(
        home: StudentIqListScreen(
          loaderOverride: () async => <IndividualQuestion>[question()],
          createCtaOverride: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('새 개별질문 (공개형)'));
      await tester.pumpAndSettle();

      final IqCreateScreen screen =
          tester.widget(find.byType(IqCreateScreen));
      expect(screen.mentorId, isNull);
      expect(find.text('새 개별질문 (공개형)'), findsOneWidget); // 등록 화면 제목.
    });

    testWidgets('빈 상태 "새 개별질문" 탭 → 네이티브 등록 화면', (WidgetTester tester) async {
      await tester.pumpScopedWidget(MaterialApp(
        home: StudentIqListScreen(
          loaderOverride: () async => <IndividualQuestion>[],
          createCtaOverride: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('새 개별질문'));
      await tester.pumpAndSettle();
      expect(find.byType(IqCreateScreen), findsOneWidget);
    });

    testWidgets('등록 성공 → 목록이 새로고침되고 새 질문 상세로 이어진다',
        (WidgetTester tester) async {
      bigSurface(tester);
      int loads = 0;
      await tester.pumpScopedWidget(MaterialApp(
        home: StudentIqListScreen(
          loaderOverride: () async {
            loads++;
            return <IndividualQuestion>[];
          },
          createCtaOverride: true,
          createScreenOverride: (BuildContext _, String? mentorId) =>
              IqCreateScreen(
            prefillOverride: () async =>
                const IqCreatePrefill(balanceCents: 1000000),
            submitOverride: ({
              required IndividualQuestionType type,
              required String title,
              required String body,
              int? amountCents,
              String? designatedMentorId,
              String? idempotencyKey,
            }) async =>
                question(id: 'q-new'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(loads, 1);

      await tester.tap(find.text('새 개별질문'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '질문 금액 (캐시)'), '5000');
      await tester.enterText(find.widgetWithText(TextField, '제목'), '제목');
      await tester.enterText(find.widgetWithText(TextField, '질문 내용'), '내용');
      await tester.tap(find.text('질문 등록'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();

      expect(find.byType(IqCreateScreen), findsNothing);
      expect(loads, 2, reason: '등록 결과가 돌아오면 목록을 다시 읽는다');
      final IqDetailScreen detail = tester.widget(find.byType(IqDetailScreen));
      expect(detail.questionId, 'q-new');
    });
  });

  group('멘토 상세 CTA', () {
    testWidgets('"개별질문 하기" 탭 → 멘토 지정형 네이티브 등록 화면',
        (WidgetTester tester) async {
      bigSurface(tester);
      await tester.pumpScopedWidget(MaterialApp(
        home: MentorDetailScreen(
          item: const MentorListItem(id: 'm1', nickname: '멘토A'),
          extrasLoaderOverride: () async =>
              const MentorDetailExtras(alreadySubscribed: false),
          createCtaOverride: true,
          createScreenOverride: (BuildContext _, String mentorId) =>
              IqCreateScreen(
            mentorId: mentorId,
            mentorName: '멘토A',
            prefillOverride: () async => const IqCreatePrefill(
              balanceCents: 1000000,
              pricing: IqPricing(mentorId: 'm1', amountCents: 250000),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('개별질문 하기'));
      await tester.tap(find.text('개별질문 하기'));
      await tester.pumpAndSettle();

      final IqCreateScreen screen =
          tester.widget(find.byType(IqCreateScreen));
      expect(screen.mentorId, 'm1', reason: '멘토 식별자는 지정형 등록으로 전달된다');
      expect(find.text('개별질문 하기 (지정형)'), findsOneWidget);
      expect(find.textContaining('충전'), findsNothing);
    });
  });
}
