import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mentors/data/free_question_entry.dart';
import 'package:ssambership_app/features/mentors/ui/free_question_compose_screen.dart';
import 'package:ssambership_app/features/mentors/ui/widgets/free_question_entry_section.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 무료 질문 진입점(세션1 §3) — fail-closed 자격 조회·scope 정합·CTA 분리.
/// 한도 수치(7/3/7일)는 앱이 판정하지 않는다 — 서버 오류 코드가 정본.

class _FakePort implements FreeQuestionEntryPort {
  _FakePort({
    this.snapshot,
    this.fetchError,
    this.createError,
  });

  FreeQuestionEntrySnapshot? snapshot;
  Object? fetchError;
  CreatedFreeQuestion? createResult;
  Object? createError;

  int fetchCalls = 0;
  int createCalls = 0;
  String? lastRoomId;
  String? lastTitle;
  Completer<CreatedFreeQuestion>? gate;

  @override
  Future<FreeQuestionEntrySnapshot> fetch(String mentorId) async {
    fetchCalls++;
    if (fetchError != null) throw fetchError!;
    return snapshot ??
        const FreeQuestionEntrySnapshot(
            roomId: 'room-1', totalUsed: 0, perMentorUsed: 0);
  }

  @override
  Future<CreatedFreeQuestion> createFreeThread({
    required String roomId,
    required String title,
    String? subject,
    String? firstMessageBody,
  }) async {
    createCalls++;
    lastRoomId = roomId;
    lastTitle = title;
    if (gate != null) await gate!.future.then((_) {});
    if (createError != null) throw createError!;
    return createResult ??
        const CreatedFreeQuestion(
            threadId: 't-1',
            roomId: 'room-1',
            path: 'free',
            usedFreeQuota: true);
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('decideFreeQuestionCta (순수 판정 — 한도 수치 계산 없음)', () {
    const FreeQuestionEntrySnapshot withRoom =
        FreeQuestionEntrySnapshot(roomId: 'r', totalUsed: 2, perMentorUsed: 1);
    const FreeQuestionEntrySnapshot noRoom =
        FreeQuestionEntrySnapshot(roomId: null, totalUsed: 0, perMentorUsed: 0);

    test('멘토·게스트·관리자(비학생) → hidden', () {
      expect(
          decideFreeQuestionCta(
              isStudent: false,
              alreadySubscribed: false,
              loading: false,
              fetchFailed: false,
              snapshot: withRoom),
          FreeQuestionCtaStatus.hidden);
    });

    test('구독자 → hidden (기존 질문방 진입 계약 유지)', () {
      expect(
          decideFreeQuestionCta(
              isStudent: true,
              alreadySubscribed: true,
              loading: false,
              fetchFailed: false,
              snapshot: withRoom),
          FreeQuestionCtaStatus.hidden);
    });

    test('구독 여부 미확정(null) → loading (활성 CTA 0)', () {
      expect(
          decideFreeQuestionCta(
              isStudent: true,
              alreadySubscribed: null,
              loading: false,
              fetchFailed: false,
              snapshot: withRoom),
          FreeQuestionCtaStatus.loading);
    });

    test('조회 실패 → unavailable (사용 가능 추정 금지)', () {
      expect(
          decideFreeQuestionCta(
              isStudent: true,
              alreadySubscribed: false,
              loading: false,
              fetchFailed: true,
              snapshot: null),
          FreeQuestionCtaStatus.unavailable);
    });

    test('방 부재 → roomMissing (앱은 방 생성 불가 — 서버 게이트)', () {
      expect(
          decideFreeQuestionCta(
              isStudent: true,
              alreadySubscribed: false,
              loading: false,
              fetchFailed: false,
              snapshot: noRoom),
          FreeQuestionCtaStatus.roomMissing);
    });

    test('학생+비구독+방 존재 → ready', () {
      expect(
          decideFreeQuestionCta(
              isStudent: true,
              alreadySubscribed: false,
              loading: false,
              fetchFailed: false,
              snapshot: withRoom),
          FreeQuestionCtaStatus.ready);
    });
  });

  group('FreeQuestionEntrySection (위젯)', () {
    testWidgets('학생·비구독·방 존재 → CTA 활성 노출', (WidgetTester tester) async {
      final _FakePort port = _FakePort();
      await tester.pumpWidget(_wrap(FreeQuestionEntrySection(
        mentorId: 'm-1',
        mentorName: '멘토',
        alreadySubscribed: false,
        port: port,
        isStudentOverride: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('무료 질문하기'), findsOneWidget);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNotNull);
      expect(port.fetchCalls, 1);
    });

    testWidgets('멘토(비학생) → 미노출 + 조회 0회', (WidgetTester tester) async {
      final _FakePort port = _FakePort();
      await tester.pumpWidget(_wrap(FreeQuestionEntrySection(
        mentorId: 'm-1',
        mentorName: '멘토',
        alreadySubscribed: false,
        port: port,
        isStudentOverride: false,
      )));
      await tester.pumpAndSettle();
      expect(find.text('무료 질문하기'), findsNothing);
      expect(port.fetchCalls, 0);
    });

    testWidgets('게스트(비학생) → 미노출', (WidgetTester tester) async {
      final _FakePort port = _FakePort();
      await tester.pumpWidget(_wrap(FreeQuestionEntrySection(
        mentorId: 'm-1',
        mentorName: '멘토',
        alreadySubscribed: false,
        port: port,
        isStudentOverride: false,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('조회 중(구독 미확정 null) → 비활성 CTA', (WidgetTester tester) async {
      final _FakePort port = _FakePort();
      await tester.pumpWidget(_wrap(FreeQuestionEntrySection(
        mentorId: 'm-1',
        mentorName: '멘토',
        alreadySubscribed: null,
        port: port,
        isStudentOverride: true,
      )));
      await tester.pump();
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull);
      expect(port.fetchCalls, 0); // 비구독 확정 전 조회 없음
    });

    testWidgets('조회 실패 → 활성 CTA 0 + 재시도 성공 후에만 활성·생성 RPC 0',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(fetchError: const AppError('네트워크'));
      await tester.pumpWidget(_wrap(FreeQuestionEntrySection(
        mentorId: 'm-1',
        mentorName: '멘토',
        alreadySubscribed: false,
        port: port,
        isStudentOverride: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('무료 질문 가능 여부를 확인하지 못했어요.'), findsOneWidget);
      expect(find.text('무료 질문하기'), findsNothing); // 활성 CTA 미노출
      expect(port.createCalls, 0);

      // 재시도 성공 → 그때만 활성화.
      port.fetchError = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('무료 질문하기'), findsOneWidget);
      expect(port.fetchCalls, 2);
      expect(port.createCalls, 0); // 여전히 생성 0 — 탭 전
    });

    testWidgets('방 부재 → 비활성 CTA + 안내(생성 RPC 0)', (WidgetTester tester) async {
      final _FakePort port = _FakePort(
          snapshot: const FreeQuestionEntrySnapshot(
              roomId: null, totalUsed: 0, perMentorUsed: 0));
      await tester.pumpWidget(_wrap(FreeQuestionEntrySection(
        mentorId: 'm-1',
        mentorName: '멘토',
        alreadySubscribed: false,
        port: port,
        isStudentOverride: true,
      )));
      await tester.pumpAndSettle();
      final OutlinedButton b =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(b.onPressed, isNull);
      expect(find.textContaining('연결된 질문방이 없어요'), findsOneWidget);
      expect(port.createCalls, 0);
    });

    testWidgets('구독자 → 렌더 없음(기존 진입 유지)', (WidgetTester tester) async {
      final _FakePort port = _FakePort();
      await tester.pumpWidget(_wrap(FreeQuestionEntrySection(
        mentorId: 'm-1',
        mentorName: '멘토',
        alreadySubscribed: true,
        port: port,
        isStudentOverride: true,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsNothing);
      expect(port.fetchCalls, 0);
    });
  });

  group('FreeQuestionComposeScreen (생성)', () {
    testWidgets('성공: 무료 전용 RPC 1회 + 정본 결과 pop', (WidgetTester tester) async {
      final _FakePort port = _FakePort();
      CreatedFreeQuestion? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await Navigator.of(ctx).push<CreatedFreeQuestion>(
                  MaterialPageRoute<CreatedFreeQuestion>(
                    builder: (_) => FreeQuestionComposeScreen(
                        roomId: 'room-1', mentorName: '멘토', port: port),
                  ),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), '이차함수가 궁금해요');
      await tester.tap(find.text('무료 질문 보내기'));
      await tester.pumpAndSettle();

      expect(port.createCalls, 1);
      expect(port.lastRoomId, 'room-1');
      expect(port.lastTitle, '무료 질문'); // 제목 미입력 → 중립 기본 제목
      expect(popped?.threadId, 't-1');
      expect(popped?.path, 'free');
    });

    testWidgets('연타 → 생성 최대 1회(in-flight guard)', (WidgetTester tester) async {
      final _FakePort port = _FakePort()
        ..gate = Completer<CreatedFreeQuestion>();
      await tester.pumpWidget(MaterialApp(
          home: FreeQuestionComposeScreen(
              roomId: 'room-1', mentorName: '멘토', port: port)));
      await tester.enterText(find.byType(TextField).at(1), '질문');
      await tester.tap(find.text('무료 질문 보내기'));
      await tester.pump();
      await tester.tap(find.text('등록 중…'), warnIfMissed: false);
      await tester.pump();
      port.gate!.complete(const CreatedFreeQuestion(
          threadId: 't-1',
          roomId: 'room-1',
          path: 'free',
          usedFreeQuota: true));
      await tester.pumpAndSettle();
      expect(port.createCalls, 1);
    });

    testWidgets('서버 오류(한도 소진 등) → 한글 안내 + 성공 처리 없음',
        (WidgetTester tester) async {
      final _FakePort port =
          _FakePort(createError: const AppError('무료 질문권을 모두 사용했어요.'));
      await tester.pumpWidget(MaterialApp(
          home: FreeQuestionComposeScreen(
              roomId: 'room-1', mentorName: '멘토', port: port)));
      await tester.enterText(find.byType(TextField).at(1), '질문');
      await tester.tap(find.text('무료 질문 보내기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('무료 질문권을 모두 사용했어요'), findsOneWidget);
      expect(find.text('무료 질문 보내기'), findsOneWidget); // 화면 유지(성공 이동 없음)
    });

    testWidgets('내용 없이 제출 → 생성 RPC 0회', (WidgetTester tester) async {
      final _FakePort port = _FakePort();
      await tester.pumpWidget(MaterialApp(
          home: FreeQuestionComposeScreen(
              roomId: 'room-1', mentorName: '멘토', port: port)));
      await tester.tap(find.text('무료 질문 보내기'));
      await tester.pump();
      expect(port.createCalls, 0);
      expect(find.text('질문 내용을 입력해 주세요.'), findsOneWidget);
    });
  });

  group('CTA 분리 계약', () {
    test('무료 질문 포트에는 개별질문(IQ)·결제 관련 API 가 없다(타입 수준 분리)', () {
      // FreeQuestionEntryPort 는 fetch/createFreeThread 두 멤버뿐 — IQ RPC·
      // 캐시 차감·충전·구독 이동을 표현할 수 없다. (IQ 는 IqCreateScreen +
      // create_individual_question_as_student 경로로 완전히 분리 — 소스 스캔은
      // free_question_entry.dart 에 individual_question RPC 문자열이 없음으로 보강)
      final _FakePort port = _FakePort();
      expect(port, isA<FreeQuestionEntryPort>());
    });
  });
}
