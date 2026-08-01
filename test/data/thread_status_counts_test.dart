import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/thread_status_counts.dart';

/// 멘토 받은-학생 목록/학생방 홈의 상태 요약 집계(순수). 실제 DB 없이 고정 스레드로 검증.
QuestionThread _thread(ThreadStatus status) {
  final DateTime now = DateTime(2026, 7, 1);
  return QuestionThread(
    id: 'id-${status.name}',
    roomId: 'room-1',
    status: status,
    masteryStatus: MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('ThreadStatusCounts.from', () {
    test('상태별 카운트 집계 (open 은 진행 중에 합산)', () {
      final ThreadStatusCounts c = ThreadStatusCounts.from(<QuestionThread>[
        _thread(ThreadStatus.pending),
        _thread(ThreadStatus.pending),
        _thread(ThreadStatus.answered),
        _thread(ThreadStatus.open),
        _thread(ThreadStatus.confirmed),
      ]);
      expect(c.total, 5);
      expect(c.pending, 2);
      expect(c.inProgress, 2); // answered + open
      expect(c.confirmed, 1);
    });

    test('pending>0 이면 needsAttention(멘토가 답할 차례)', () {
      expect(
        ThreadStatusCounts.from(<QuestionThread>[_thread(ThreadStatus.pending)])
            .needsAttention,
        isTrue,
      );
      expect(
        ThreadStatusCounts.from(
                <QuestionThread>[_thread(ThreadStatus.confirmed)])
            .needsAttention,
        isFalse,
      );
    });
  });

  group('summaryLine (목록 행 요약)', () {
    test('질문 없음', () {
      expect(ThreadStatusCounts.from(const <QuestionThread>[]).summaryLine,
          '질문 없음');
    });

    test('대기/진행 혼합 → "답변 대기 N · 진행 중 N"', () {
      final ThreadStatusCounts c = ThreadStatusCounts.from(<QuestionThread>[
        _thread(ThreadStatus.pending),
        _thread(ThreadStatus.answered),
      ]);
      expect(c.summaryLine, '답변 대기 1 · 진행 중 1');
    });

    test('전부 확인 완료 → "모두 답변 완료"', () {
      final ThreadStatusCounts c = ThreadStatusCounts.from(<QuestionThread>[
        _thread(ThreadStatus.confirmed),
        _thread(ThreadStatus.confirmed),
      ]);
      expect(c.summaryLine, '모두 답변 완료');
    });

    test('요약 라인에 영문 status 코드가 노출되지 않는다', () {
      final ThreadStatusCounts c = ThreadStatusCounts.from(<QuestionThread>[
        _thread(ThreadStatus.pending),
        _thread(ThreadStatus.answered),
        _thread(ThreadStatus.confirmed),
      ]);
      expect(RegExp(r'[a-zA-Z]').hasMatch(c.summaryLine), isFalse);
    });
  });
}
