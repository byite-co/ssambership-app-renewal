import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/web_bridge/web_bridge.dart';
import 'package:ssambership_app/core/web_bridge/web_bridge_actions.dart';
import 'package:ssambership_app/core/web_bridge/web_bridge_config.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_create_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/student_iq_list_screen.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mentors/ui/mentor_detail_screen.dart';
import '../support/app_scope_test_harness.dart';

/// 제품 경계 계약(2026-08-05): 신규 개별질문 등록은 **웹 전용**이다.
///
/// - production 코드에는 네이티브 등록 화면(IqCreateScreen) 진입이 0개여야 한다.
/// - 두 CTA(멘토 상세·학생 목록)는 웹 등록 브릿지만 호출한다.
/// - 조회·상세·답변·첨부·첨삭은 이 경계와 무관하게 유지된다(별도 스위트가 보증).
///
/// 정적 검색 + 화면 탭(브릿지 mock) 양쪽으로 고정한다 — 한쪽만으로는
/// 재배선(정적)이나 죽은 배선(동적)을 놓칠 수 있다.
void main() {
  // ───────────────────────── 정적: production 진입점 0 ─────────────────────────
  group('정적 경계: 네이티브 등록 진입 0', () {
    List<File> productionDartFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList(growable: false);

    test('lib/ 에서 iq_create_screen import 는 자기 자신뿐이다', () {
      final List<String> importers = <String>[];
      for (final File f in productionDartFiles()) {
        if (f.path.endsWith('iq_create_screen.dart')) continue;
        if (f.readAsStringSync().contains('iq_create_screen.dart')) {
          // 주석 언급은 허용 — import/uri 표기만 잡는다.
          for (final String line in f.readAsLinesSync()) {
            final String t = line.trim();
            if (t.startsWith('import') && t.contains('iq_create_screen.dart')) {
              importers.add(f.path);
            }
          }
        }
      }
      expect(importers, isEmpty,
          reason: '신규 등록은 웹 전용 — production 에서 네이티브 등록 화면을 '
              'import 하면 경계 위반이다: $importers');
    });

    test('lib/ 에서 IqCreateScreen 생성자 호출은 0이다(자기 파일 제외)', () {
      final List<String> callers = <String>[];
      final RegExp ctor = RegExp(r'\bIqCreateScreen\s*\(');
      for (final File f in productionDartFiles()) {
        if (f.path.endsWith('iq_create_screen.dart')) continue;
        if (ctor.hasMatch(f.readAsStringSync())) callers.add(f.path);
      }
      expect(callers, isEmpty,
          reason: 'production 그래프에서 네이티브 등록 화면 생성 0 이어야 한다: $callers');
    });

    test('route table·deep link 에 네이티브 등록 경로가 없다', () {
      final String router = File('lib/app/router.dart').readAsStringSync();
      expect(router.contains('IqCreate'), isFalse,
          reason: 'named route 로 네이티브 등록 화면을 열 수 없어야 한다');
      final Directory deeplink = Directory('lib/core/deeplink');
      for (final File f in deeplink
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))) {
        expect(f.readAsStringSync().contains('IqCreate'), isFalse,
            reason: 'deep link/알림 라우팅으로 네이티브 등록 화면에 도달할 수 '
                '없어야 한다: ${f.path}');
      }
    });

    test('목록→상세(조회) 배선은 유지된다', () {
      final String list = File(
              'lib/features/individual_question/ui/student_iq_list_screen.dart')
          .readAsStringSync();
      expect(list.contains('IqDetailScreen('), isTrue,
          reason: '경계 작업은 등록만 제거한다 — 기존 질문 상세 진입은 보존');
    });
  });

  // ───────────────────────── 브릿지: URL 정본 ─────────────────────────
  group('웹 등록 브릿지 URL 정본', () {
    test('일반 등록 → /individual-questions/new (https·허용 호스트)', () async {
      final List<Uri> opened = <Uri>[];
      final WebBridge bridge = WebBridge(launcher: (Uri u) async {
        opened.add(u);
        return true;
      });
      final WebOpenResult r = await bridge.openIqCreate();
      expect(r, WebOpenResult.opened);
      expect(opened, hasLength(1));
      expect(opened.single.path, WebBridgeConfig.iqCreatePath);
      expect(opened.single.scheme, 'https');
      expect(bridge.isAllowedUri(opened.single), isTrue);
    });

    test('멘토 지정 등록 → /mentors/{id}/individual-question/new', () async {
      final List<Uri> opened = <Uri>[];
      final WebBridge bridge = WebBridge(launcher: (Uri u) async {
        opened.add(u);
        return true;
      });
      await bridge.openIqCreate(mentorId: 'm1');
      expect(opened.single.path, '/mentors/m1/individual-question/new');
    });

    test('mentorId 는 경로 성분으로 인코딩된다(경로 위조 차단)', () async {
      final List<Uri> opened = <Uri>[];
      final WebBridge bridge = WebBridge(launcher: (Uri u) async {
        opened.add(u);
        return true;
      });
      await bridge.openIqCreate(mentorId: 'a/b?c');
      // 인코딩되어 path segment 하나로 남는다 — 상위 경로 이탈 불가.
      expect(opened.single.pathSegments[1], 'a/b?c');
      expect(opened.single.pathSegments.length, 4);
    });

    test('baseUrl 미확정이면 열지 않고 안내 폴백(notConfigured)', () async {
      final WebBridge bridge = WebBridge(
        baseUrl: '',
        launcher: (Uri u) async => fail('미확정이면 launcher 호출 금지'),
      );
      expect(await bridge.openIqCreate(), WebOpenResult.notConfigured);
    });
  });

  // ───────────────────────── 화면: CTA → 브릿지(mock) ─────────────────────────
  IndividualQuestion question() => IndividualQuestion(
        id: 'q1',
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

  group('학생 목록 CTA', () {
    testWidgets('"새 개별질문 (공개형)" 탭 → 웹 브릿지 호출, 네이티브 화면 미진입',
        (WidgetTester tester) async {
      final List<Uri> opened = <Uri>[];
      final WebBridge fake = WebBridge(launcher: (Uri u) async {
        opened.add(u);
        return true;
      });
      await tester.pumpScopedWidget(MaterialApp(
        home: StudentIqListScreen(
          loaderOverride: () async => <IndividualQuestion>[question()],
          webBridgeOverride: fake,
          createCtaOverride: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('새 개별질문 (공개형)'));
      await tester.pumpAndSettle();

      expect(opened.single.path, WebBridgeConfig.iqCreatePath);
      expect(find.byType(IqCreateScreen), findsNothing,
          reason: '신규 등록은 웹 전용 — 네이티브 등록 화면을 열면 안 된다');
    });

    testWidgets('빈 상태 "새 개별질문" 탭 → 웹 브릿지 호출', (WidgetTester tester) async {
      final List<Uri> opened = <Uri>[];
      final WebBridge fake = WebBridge(launcher: (Uri u) async {
        opened.add(u);
        return true;
      });
      await tester.pumpScopedWidget(MaterialApp(
        home: StudentIqListScreen(
          loaderOverride: () async => <IndividualQuestion>[],
          webBridgeOverride: fake,
          createCtaOverride: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('새 개별질문'));
      await tester.pumpAndSettle();

      expect(opened.single.path, WebBridgeConfig.iqCreatePath);
      expect(find.byType(IqCreateScreen), findsNothing);
    });
  });

  group('멘토 상세 CTA', () {
    testWidgets('"개별질문 하기" 탭 → 멘토 지정 웹 등록 브릿지, 네이티브 화면 미진입',
        (WidgetTester tester) async {
      bigSurface(tester);
      final List<Uri> opened = <Uri>[];
      final WebBridge fake = WebBridge(launcher: (Uri u) async {
        opened.add(u);
        return true;
      });
      await tester.pumpScopedWidget(MaterialApp(
        home: MentorDetailScreen(
          item: const MentorListItem(id: 'm1', nickname: '멘토A'),
          extrasLoaderOverride: () async =>
              const MentorDetailExtras(alreadySubscribed: false),
          webBridgeOverride: fake,
          createCtaOverride: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('개별질문 하기'));
      await tester.tap(find.text('개별질문 하기'));
      await tester.pumpAndSettle();

      expect(opened.single.path, '/mentors/m1/individual-question/new',
          reason: '멘토 식별자는 웹 실측 라우트의 path param 계약으로 전달한다');
      expect(find.byType(IqCreateScreen), findsNothing);
    });
  });

  group('실패 UX', () {
    testWidgets('웹 열기 실패 → 재시도 안내 스낵바', (WidgetTester tester) async {
      final WebBridge failing = WebBridge(launcher: (Uri u) async => false);
      await tester.pumpScopedWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => openIqCreateWeb(context, bridge: failing),
              child: const Text('열기'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('웹 페이지를 열 수 없어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('baseUrl 미확정 → 준비 중 안내 스낵바', (WidgetTester tester) async {
      final WebBridge notConfigured = WebBridge(
        baseUrl: '',
        launcher: (Uri u) async => fail('미확정이면 launcher 호출 금지'),
      );
      await tester.pumpScopedWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => openIqCreateWeb(context, bridge: notConfigured),
              child: const Text('열기'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('개별질문 등록은 웹에서 진행할 수 있어요. (준비 중)'), findsOneWidget);
    });
  });
}
