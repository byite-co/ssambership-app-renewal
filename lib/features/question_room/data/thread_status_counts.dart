import 'models/question_thread.dart';

/// 한 방(학생)의 스레드 상태 집계. 멘토 받은-학생 목록/학생방 홈이 공유한다.
///
/// ★ 라벨 매핑(웹 기준)과 일치: pending=답변 대기, answered/open=진행 중, confirmed=답변 완료.
///   '안읽음'을 추적하는 컬럼이 스키마에 없으므로, 멘토가 답해야 하는 'pending>0'을
///   주의 표시(attention)로 쓴다 — 가짜 안읽음 수를 만들지 않는다.
class ThreadStatusCounts {
  const ThreadStatusCounts({
    required this.total,
    required this.pending,
    required this.inProgress,
    required this.confirmed,
    this.completed = 0,
  });

  /// 스레드 총 개수(unknown 포함 — '전체' 탭의 개수).
  final int total;

  /// 답변 대기(pending) — 멘토가 답할 차례.
  final int pending;

  /// 진행 중(answered/open) — 답변은 갔고 학생 확인 대기.
  final int inProgress;

  /// 답변 완료(confirmed). 요약 라인·주의 표시용(기존 소비처 호환).
  final int confirmed;

  /// 완료 탭 집계(confirmed + closed + archived). 멘토 질문 목록 '완료' 탭용 —
  /// closed/archived 를 confirmed 와 분리 유지해 summaryLine 의미는 안 바꾼다.
  final int completed;

  factory ThreadStatusCounts.from(Iterable<QuestionThread> threads) {
    int p = 0, ip = 0, c = 0, done = 0, t = 0;
    for (final QuestionThread th in threads) {
      t++;
      switch (th.status) {
        case ThreadStatus.pending:
          p++;
          break;
        case ThreadStatus.answered:
        case ThreadStatus.open:
          ip++;
          break;
        case ThreadStatus.confirmed:
          c++;
          done++;
          break;
        case ThreadStatus.closed:
        case ThreadStatus.archived:
          done++; // 완료 탭에는 포함(요약 라인에서는 기존대로 제외).
          break;
        case ThreadStatus.unknown:
          break; // 알 수 없는 상태 — total(전체)에만 포함
      }
    }
    return ThreadStatusCounts(
        total: t, pending: p, inProgress: ip, confirmed: c, completed: done);
  }

  /// 멘토 주의 필요(답할 게 있음).
  bool get needsAttention => pending > 0;

  /// 목록 행의 상태 요약 한 줄.
  /// 질문 없음 / "답변 대기 N · 진행 중 N" / "모두 답변 완료".
  String get summaryLine {
    if (total == 0) return '질문 없음';
    final List<String> parts = <String>[
      if (pending > 0) '답변 대기 $pending',
      if (inProgress > 0) '진행 중 $inProgress',
    ];
    if (parts.isEmpty) return '모두 답변 완료';
    return parts.join(' · ');
  }
}
