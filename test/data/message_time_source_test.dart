import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/model_parse.dart';
import 'package:ssambership_app/features/question_room/data/models/question_message.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/features/question_room/data/thread_messages_controller.dart';
import 'package:ssambership_app/features/question_room/ui/widgets/message_bubble.dart';
import 'package:ssambership_app/shared/format/formatters.dart';

/// S3-E §3·§4 — 질문방 말풍선 시각의 정본 경로 회귀 가드.
///
/// 계약: [QuestionMessage.createdAt] 은 `parseTime`(= toLocal) 이 만드는
/// **로컬 시각** 축이다. append RPC 는 created_at 을 돌려주지 않으므로
/// 낙관적 행도 같은 축(로컬)이어야 하고, 서버 행이 도착하면 교체돼야 한다.
QuestionMessage _msg(String id, DateTime createdAt, {String author = 'me'}) =>
    QuestionMessage(
      id: id,
      threadId: 't1',
      authorId: author,
      body: 'hello',
      createdAt: createdAt,
    );

void main() {
  group('parseTime 계약', () {
    test('서버 timestamptz → 기기 로컬 시각(비-UTC)', () {
      final DateTime t = parseTime('2026-08-01T01:00:00+00:00');
      expect(t.isUtc, isFalse);
      expect(t, DateTime.parse('2026-08-01T01:00:00Z').toLocal());
    });
  });

  group('말풍선 표시 시각', () {
    testWidgets('로컬 시각 그대로 hh:mm — 중복 변환 없음', (WidgetTester tester) async {
      final DateTime local = DateTime(2026, 8, 1, 21, 34);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MessageBubble(message: _msg('m1', local), mine: true)),
      ));
      expect(find.text('21:34'), findsOneWidget);
    });

    testWidgets('UTC 로 들어온 값은 표시 직전 기기 시간대로 맞춘다',
        (WidgetTester tester) async {
      final DateTime utc = DateTime.utc(2026, 8, 1, 12, 34);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MessageBubble(message: _msg('m1', utc), mine: true)),
      ));
      // 기기 시간대와 무관하게 '로컬 변환 1회' 결과와 일치해야 한다.
      expect(find.text(Formatters.hourMinute(utc.toLocal())), findsOneWidget);
    });

    testWidgets('UTC 기기(로컬==UTC)에서도 이중 변환이 없다', (WidgetTester tester) async {
      // parseTime 결과를 다시 toLocal 해도 값이 변하지 않아야 한다(멱등).
      final DateTime parsed = parseTime('2026-08-01T03:05:00+00:00');
      expect(parsed.toLocal(), parsed);
      expect(Formatters.hourMinute(parsed.toLocal()),
          Formatters.hourMinute(parsed));
      await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: MessageBubble(message: _msg('m1', parsed), mine: false)),
      ));
      expect(find.text(Formatters.hourMinute(parsed)), findsOneWidget);
    });
  });

  group('append 낙관적 행(학생·멘토 공용 경로)', () {
    test('created_at 은 로컬 축 — UTC 로 만들지 않는다(전송 직후 KST 정상)', () {
      final QuestionMessage m = QuestionRoomWriteRepository.optimisticMessage(
        messageId: 'm1',
        threadId: 't1',
        authorId: 'u1',
        body: '  안녕하세요  ',
      );
      expect(m.createdAt.isUtc, isFalse);
      expect(m.body, '안녕하세요');
      // parseTime(서버행)과 같은 축이라 hh:mm 이 기기 로컬 시각과 일치한다.
      final DateTime now = DateTime.now();
      expect(m.createdAt.difference(now).abs(),
          lessThan(const Duration(seconds: 5)));
      expect(Formatters.hourMinute(m.createdAt),
          Formatters.hourMinute(m.createdAt.toLocal()));
    });

    test('같은 순간의 서버 행과 hh:mm 이 일치한다(새로고침 전후 동일)', () {
      final DateTime instant = DateTime(2026, 8, 1, 21, 34, 10);
      final QuestionMessage optimistic =
          QuestionRoomWriteRepository.optimisticMessage(
        messageId: 'm1',
        threadId: 't1',
        authorId: 'u1',
        body: 'x',
        now: instant,
      );
      // 서버가 같은 순간을 timestamptz 로 돌려준 뒤 재조회한 행.
      final DateTime server = parseTime(instant.toUtc().toIso8601String());
      expect(Formatters.hourMinute(optimistic.createdAt),
          Formatters.hourMinute(server));
    });
  });

  group('낙관적 행 ↔ 서버 행', () {
    test('서버 행 도착 시 같은 id 의 낙관적 행을 교체한다(서버 시각 유지)', () {
      final DateTime optimistic = DateTime(2026, 8, 1, 21, 34, 10);
      final DateTime server = parseTime('2026-08-01T12:34:56+00:00');
      final ThreadMessagesController c =
          ThreadMessagesController(<QuestionMessage>[]);

      expect(c.add(_msg('m1', optimistic)), isTrue); // 낙관적 반영
      expect(c.items.single.createdAt, optimistic);

      expect(c.upsertFromServer(_msg('m1', server)), isTrue);
      expect(c.length, 1); // 중복 행이 생기지 않는다
      expect(c.items.single.createdAt, server); // 서버 시각이 정본
    });

    test('서버 행이 먼저 온 뒤의 낙관적 add 는 서버 시각을 덮지 않는다', () {
      final DateTime server = parseTime('2026-08-01T12:34:56+00:00');
      final ThreadMessagesController c =
          ThreadMessagesController(<QuestionMessage>[]);

      expect(c.upsertFromServer(_msg('m1', server)), isTrue);
      expect(c.add(_msg('m1', DateTime(2026, 8, 1, 3, 0))), isFalse);
      expect(c.items.single.createdAt, server);
    });

    test('새 id 의 서버 행은 그냥 추가되고 시간순 정렬을 유지한다', () {
      final ThreadMessagesController c = ThreadMessagesController(
          <QuestionMessage>[_msg('a', DateTime(2026, 8, 1, 10, 0))]);
      c.upsertFromServer(_msg('b', DateTime(2026, 8, 1, 9, 0)));
      expect(c.items.map((QuestionMessage m) => m.id).toList(),
          <String>['b', 'a']);
    });

    test('낙관적 행은 서버 행과 같은 시간축이라 목록 끝에 붙는다(9시간 점프 없음)', () {
      final DateTime prevServer = parseTime(
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String());
      final ThreadMessagesController c =
          ThreadMessagesController(<QuestionMessage>[_msg('old', prevServer)]);
      // 화면이 append RPC 결과로 만드는 낙관적 행과 동일한 방식(로컬 now).
      c.add(_msg('new', DateTime.now()));
      expect(c.items.last.id, 'new');
    });
  });
}
