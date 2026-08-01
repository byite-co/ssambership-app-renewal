import 'model_parse.dart';

/// 스레드 진행 상태. DB question_threads.status CHECK 값을 그대로 따른다:
/// pending / answered / confirmed / open / closed / archived (기본 open).
/// ★ 알 수 없는 값이 와도 깨지지 않게 [ThreadStatus.unknown] 으로 폴백.
enum ThreadStatus {
  pending,
  answered,
  confirmed,
  open,
  closed,
  archived,

  /// DB에 없던 값(스키마 변경 등)에 대한 안전 폴백. DB로 다시 쓰지 않는다.
  unknown;

  /// DB 코드 → enum. 모르는 값은 unknown.
  static ThreadStatus fromCode(String? code) {
    switch (code?.trim()) {
      case 'pending':
        return ThreadStatus.pending;
      case 'answered':
        return ThreadStatus.answered;
      case 'confirmed':
        return ThreadStatus.confirmed;
      case 'open':
        return ThreadStatus.open;
      case 'closed':
        return ThreadStatus.closed;
      case 'archived':
        return ThreadStatus.archived;
      default:
        return ThreadStatus.unknown;
    }
  }

  /// enum → DB 코드. unknown 은 쓰기에 부적합하므로 null(쓰기 시 호출부가 제외).
  String? get code => this == ThreadStatus.unknown ? null : name;
}

/// 학습 숙련 상태. DB mastery_status CHECK: unknown/wrong/review/mastered (기본 unknown).
enum MasteryStatus {
  unknown,
  wrong,
  review,
  mastered;

  static MasteryStatus fromCode(String? code) {
    switch (code?.trim()) {
      case 'wrong':
        return MasteryStatus.wrong;
      case 'review':
        return MasteryStatus.review;
      case 'mastered':
        return MasteryStatus.mastered;
      case 'unknown':
      default:
        return MasteryStatus.unknown;
    }
  }

  String get code => name;
}

/// 질문 스레드(question_threads) = 질문 한 건.
class QuestionThread {
  const QuestionThread({
    required this.id,
    required this.roomId,
    this.title,
    required this.status,
    this.topic,
    this.subject,
    required this.masteryStatus,
    this.firstAnsweredAt,
    this.confirmedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// mentor_student_room_id (FK → mentor_student_rooms.id).
  final String roomId;
  final String? title;
  final ThreadStatus status;
  final String? topic;

  /// subjects.code (영문 코드). 화면 표시 시 한글 라벨로 변환할 것.
  final String? subject;
  final MasteryStatus masteryStatus;
  final DateTime? firstAnsweredAt;
  final DateTime? confirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory QuestionThread.fromMap(Map<String, dynamic> map) {
    return QuestionThread(
      id: map['id'] as String,
      roomId: map['mentor_student_room_id'] as String,
      title: map['title'] as String?,
      status: ThreadStatus.fromCode(map['status'] as String?),
      topic: map['topic'] as String?,
      subject: map['subject'] as String?,
      masteryStatus: MasteryStatus.fromCode(map['mastery_status'] as String?),
      firstAnsweredAt: parseTimeOrNull(map['first_answered_at']),
      confirmedAt: parseTimeOrNull(map['confirmed_at']),
      createdAt: parseTime(map['created_at']),
      updatedAt: parseTime(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'mentor_student_room_id': roomId,
        'title': title,
        'status': status.code,
        'topic': topic,
        'subject': subject,
        'mastery_status': masteryStatus.code,
        'first_answered_at': firstAnsweredAt?.toIso8601String(),
        'confirmed_at': confirmedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 제목 미입력 시 자동 제목 — 그 방(mentor_student_room)의 질문 순번(1-based) 기반.
///
/// [existingCount] = 그 방의 기존 질문(스레드) 수. 새 질문의 순번 N = existingCount + 1.
/// 예) 방에 질문이 2건이면 새 질문 제목은 '3번 질문'. 저장·표시 모두 이 값을 쓴다.
String autoQuestionTitle(int existingCount) => '${existingCount + 1}번 질문';
