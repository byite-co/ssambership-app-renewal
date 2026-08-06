import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/question_message.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/data/thread_messages_controller.dart';

/// N21 페이지 계약 — 복합 커서(created_at, id)의 무손실·무중복.
///
/// 서버 술어를 그대로 미러링한 인메모리 시뮬레이터로 커서 워크 전체를
/// 검증한다: 술어 = `created_at < c.ts OR (created_at = c.ts AND id < c.id)`,
/// 정렬 = (created_at DESC, id DESC), limit 후 asc 반전.
QuestionMessage _msg(String id, DateTime at) => QuestionMessage(
      id: id,
      threadId: 't1',
      authorId: 'u1',
      body: 'b-$id',
      createdAt: at,
    );

/// 서버 쿼리 시뮬레이터 — repository 의 recentMessages/messagesBefore 와
/// 동일 술어·정렬·limit 계약.
List<QuestionMessage> _fetchPage(
  List<QuestionMessage> dataset, {
  MessageCursor? cursor,
  required int limit,
}) {
  Iterable<QuestionMessage> it = dataset;
  if (cursor != null) {
    it = it.where((QuestionMessage m) =>
        m.createdAt.isBefore(cursor.createdAt) ||
        (m.createdAt.isAtSameMomentAs(cursor.createdAt) &&
            m.id.compareTo(cursor.id) < 0));
  }
  final List<QuestionMessage> desc = it.toList()
    ..sort((QuestionMessage a, QuestionMessage b) {
      final int c = b.createdAt.compareTo(a.createdAt);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
  return desc.take(limit).toList().reversed.toList();
}

/// 커서 워크 전체 수행 — 화면과 동일한 규칙(hasMore = 페이지가 꽉 찼는가,
/// 빈 후속 페이지 → 종료)으로 처음부터 끝까지 걷는다.
({List<QuestionMessage> collected, int pages}) _walkAll(
  List<QuestionMessage> dataset, {
  required int limit,
}) {
  final ThreadMessagesController ctrl =
      ThreadMessagesController(_fetchPage(dataset, limit: limit));
  int pages = 1;
  bool hasMore = ctrl.length >= limit;
  while (hasMore) {
    final List<QuestionMessage> older = _fetchPage(dataset,
        cursor: MessageCursor.oldestOf(ctrl.items), limit: limit);
    pages++;
    if (older.isEmpty) {
      hasMore = false; // 빈 후속 페이지 → 종료
      break;
    }
    ctrl.upsertAllFromServer(older);
    hasMore = older.length >= limit;
  }
  return (collected: ctrl.items, pages: pages);
}

void _assertLossless(List<QuestionMessage> dataset, {int limit = 200}) {
  final ({List<QuestionMessage> collected, int pages}) r =
      _walkAll(dataset, limit: limit);
  expect(r.collected.length, dataset.length, reason: '누락 0');
  expect(r.collected.map((QuestionMessage m) => m.id).toSet().length,
      dataset.length,
      reason: '중복 0');
  // 정렬: (created_at asc, id asc) — 컨트롤러 타이브레이크와 동일.
  for (int i = 1; i < r.collected.length; i++) {
    final QuestionMessage a = r.collected[i - 1], b = r.collected[i];
    final int c = a.createdAt.compareTo(b.createdAt);
    expect(c < 0 || (c == 0 && a.id.compareTo(b.id) < 0), isTrue,
        reason: '정렬 안정성 @$i');
  }
}

List<QuestionMessage> _distinctTimes(int n) => <QuestionMessage>[
      for (int i = 0; i < n; i++)
        _msg('id-${i.toString().padLeft(4, '0')}',
            DateTime.utc(2026, 1, 1).add(Duration(minutes: i))),
    ];

void main() {
  group('N21 커서 워크 무손실(경계 크기 전수)', () {
    for (final int n in <int>[0, 1, 199, 200, 201, 400, 401]) {
      test('$n건 — 누락 0·중복 0·정렬 안정', () {
        _assertLossless(_distinctTimes(n));
      });
    }

    test('201건 전부 동일 created_at — id 타이브레이크만으로 무손실', () {
      final DateTime t = DateTime.utc(2026, 3, 1, 12);
      _assertLossless(<QuestionMessage>[
        for (int i = 0; i < 201; i++)
          _msg('same-${i.toString().padLeft(4, '0')}', t),
      ]);
    });

    test('페이지 경계(200·201번째)가 동일 timestamp — 경계 무손실', () {
      // 최신쪽 199건은 시각 상이, 200·201번째(과거쪽)는 같은 시각.
      final DateTime boundary = DateTime.utc(2026, 2, 1);
      final List<QuestionMessage> ds = <QuestionMessage>[
        _msg('bnd-a', boundary),
        _msg('bnd-b', boundary),
        for (int i = 0; i < 199; i++)
          _msg('new-${i.toString().padLeft(4, '0')}',
              boundary.add(Duration(minutes: i + 1))),
      ];
      _assertLossless(ds);
    });

    test('동일 timestamp 혼합 대형(43개 시각 × 10건 = 430)', () {
      final List<QuestionMessage> ds = <QuestionMessage>[
        for (int t = 0; t < 43; t++)
          for (int k = 0; k < 10; k++)
            _msg('m-$t-$k', DateTime.utc(2026, 4, 1).add(Duration(seconds: t))),
      ];
      _assertLossless(ds);
    });

    test('마지막 페이지가 정확히 limit 크기 → 빈 후속 페이지로 종료(hasMore=false)', () {
      final ({List<QuestionMessage> collected, int pages}) r =
          _walkAll(_distinctTimes(400), limit: 200);
      expect(r.collected.length, 400);
      expect(r.pages, 3, reason: '200+200+빈페이지 — 빈 페이지가 종료 신호');
    });
  });

  group('N21 병합·커서 규칙', () {
    test('cursor 는 항상 현재 로드된 가장 오래된 행', () {
      final List<QuestionMessage> ds = _distinctTimes(250);
      final ThreadMessagesController ctrl =
          ThreadMessagesController(_fetchPage(ds, limit: 200));
      final MessageCursor c1 = MessageCursor.oldestOf(ctrl.items);
      expect(c1.id, 'id-0050'); // 250건 중 최신 200 → 가장 오래된 로드행=50
      ctrl.upsertAllFromServer(_fetchPage(ds, cursor: c1, limit: 200));
      expect(MessageCursor.oldestOf(ctrl.items).id, 'id-0000');
    });

    test('refresh(최신 페이지 merge)가 이전 페이지를 보존한다', () {
      final List<QuestionMessage> ds = _distinctTimes(300);
      final ThreadMessagesController ctrl =
          ThreadMessagesController(_fetchPage(ds, limit: 200));
      ctrl.upsertAllFromServer(_fetchPage(ds,
          cursor: MessageCursor.oldestOf(ctrl.items), limit: 200));
      expect(ctrl.length, 300);
      // refresh = 최신 페이지 재조회 merge — resetTo 가 아니므로 300 유지.
      ctrl.upsertAllFromServer(_fetchPage(ds, limit: 200));
      expect(ctrl.length, 300, reason: '이전 페이지 보존');
    });

    test('중복 realtime 이벤트 — id dedup, 개수 불변', () {
      final List<QuestionMessage> ds = _distinctTimes(10);
      final ThreadMessagesController ctrl =
          ThreadMessagesController(_fetchPage(ds, limit: 200));
      ctrl.upsertFromServer(ds[3]);
      ctrl.upsertFromServer(ds[3]);
      expect(ctrl.length, 10);
    });

    test('upsertAllFromServer — notify 정확 1회(페이지 병합)', () {
      final ThreadMessagesController ctrl =
          ThreadMessagesController(_distinctTimes(5));
      int notifies = 0;
      ctrl.addListener(() => notifies++);
      final List<QuestionMessage> more = <QuestionMessage>[
        for (int i = 100; i < 150; i++)
          _msg('extra-$i', DateTime.utc(2025, 1, 1).add(Duration(minutes: i))),
      ];
      ctrl.upsertAllFromServer(more);
      expect(notifies, 1, reason: '행별 notify 는 앵커 보정을 깨뜨린다');
      ctrl.upsertAllFromServer(const <QuestionMessage>[]);
      expect(notifies, 1, reason: '변경 0건이면 notify 없음');
    });
  });

  group('N21 커서 필터 문자열(PostgREST or= 형식 고정)', () {
    test('형식: created_at.lt."TS",and(created_at.eq."TS",id.lt."ID")', () {
      expect(
        messageCursorBeforeFilter(
            ts: '2026-08-06T09:00:00.123456Z', id: 'abc-123'),
        'created_at.lt."2026-08-06T09:00:00.123456Z",'
        'and(created_at.eq."2026-08-06T09:00:00.123456Z",id.lt."abc-123")',
      );
    });

    test('커서 직렬화 — UTC ISO 마이크로초 보존(µs 왕복 무손실)', () {
      final DateTime at = DateTime.parse('2026-08-06T18:00:00.123456+09:00');
      expect(at.toUtc().toIso8601String(), '2026-08-06T09:00:00.123456Z');
    });
  });
}
