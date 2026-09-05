import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/core/entitlement/subscription_summary.dart';
import 'package:ssambership_app/core/entitlement/weekly_question_usage.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart';
import 'package:ssambership_app/features/question_room/data/mentor_lookup_repository.dart';
import 'package:ssambership_app/features/question_room/data/models/connection_note.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/question_room/data/models/question_message.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/data/room_safety_repository.dart';
import 'package:ssambership_app/features/question_room/data/student_lookup_repository.dart';
import 'package:ssambership_app/features/question_room/data/thread_realtime.dart';

/// 골든 픽스처 — 네트워크·인증·전역 싱글턴에 닿지 않는 손코딩 데이터와 포트 fake.
///
/// ★ 날짜는 전부 **7일 이상 과거의 로컬 시각**으로 둔다.
///   - Formatters.relativeKorean 은 7일 이전이면 절대 날짜('2026년 7월 1일')로
///     떨어져 실행일에 따라 골든이 바뀌지 않는다.
///   - 말풍선 시각(hourMinute)은 `toLocal()` 을 거치는데, 로컬 DateTime 은
///     그대로 돌아오므로 실행 기기의 시간대와 무관하게 같은 문자열이 나온다.
const String kStudentId = 's1';
const String kMentorId = 'm1';
const String kRoomId = 'r1';
const String kMentorName = '김멘토';
const String kStudentName = '이학생';

DateTime _at(int day, [int hour = 9, int minute = 0]) =>
    DateTime(2026, 7, day, hour, minute);

Room goldenRoom() => Room(
      id: kRoomId,
      studentId: kStudentId,
      mentorId: kMentorId,
      createdAt: _at(1),
      updatedAt: _at(3),
    );

SubscriptionSummary goldenSubscription() => SubscriptionSummary(
      mentorId: kMentorId,
      isActive: true,
      status: 'active',
      nextRenewal: _at(27),
    );

const WeeklyQuestionUsage goldenUsage = WeeklyQuestionUsage(
  used: 2,
  limit: 5,
  remaining: 3,
  canAsk: true,
);

QuestionThread goldenThread({
  required String id,
  required ThreadStatus status,
  required String title,
  String? subject,
  MasteryStatus mastery = MasteryStatus.unknown,
  int day = 2,
}) =>
    QuestionThread(
      id: id,
      roomId: kRoomId,
      title: title,
      status: status,
      subject: subject,
      masteryStatus: mastery,
      firstAnsweredAt: status == ThreadStatus.pending ? null : _at(day, 14),
      confirmedAt: status == ThreadStatus.confirmed ? _at(day, 18) : null,
      createdAt: _at(day),
      updatedAt: _at(day, 18),
    );

/// 학생 질문 영역 목록용 — 상태 3종(대기·답변완료·확인완료)이 한 화면에 보이게.
List<QuestionThread> goldenThreads() => <QuestionThread>[
      goldenThread(
        id: 't3',
        status: ThreadStatus.pending,
        title: '삼각함수 합성 문제에서 위상 구하는 법',
        subject: 'math_1',
        day: 3,
      ),
      goldenThread(
        id: 't2',
        status: ThreadStatus.answered,
        title: '영어 독해 지문에서 주제문 찾기',
        subject: 'english',
        day: 2,
      ),
      goldenThread(
        id: 't1',
        status: ThreadStatus.confirmed,
        title: '비문학 독서 — 논지 전개 방식 정리',
        subject: 'korean_reading',
        mastery: MasteryStatus.mastered,
        day: 1,
      ),
    ];

/// 채팅·답변 화면 공용 대화 — 학생 질문 → 멘토 답변 → 학생 추가 질문.
List<QuestionMessage> goldenMessages(String threadId) => <QuestionMessage>[
      QuestionMessage(
        id: 'q1',
        threadId: threadId,
        authorId: kStudentId,
        body: '선생님, 이 문제에서 sin 과 cos 을 합성할 때 위상은 어떻게 구하나요? '
            '교재 풀이는 arctan 을 쓰는데 부호가 헷갈려요.',
        createdAt: _at(3, 9, 12),
      ),
      QuestionMessage(
        id: 'a1',
        threadId: threadId,
        authorId: kMentorId,
        body: '좋은 질문이에요. a·sinθ + b·cosθ = √(a²+b²)·sin(θ+α) 로 놓고, '
            'α 는 cosα = a/√(a²+b²), sinα = b/√(a²+b²) 를 **둘 다** 만족하는 각으로 잡아요. '
            'arctan(b/a) 만 쓰면 a<0 일 때 사분면이 뒤집혀서 부호가 틀리는 거예요.',
        createdAt: _at(3, 14, 5),
      ),
      QuestionMessage(
        id: 'q2',
        threadId: threadId,
        authorId: kStudentId,
        body: '아, 그래서 a 가 음수면 π 를 더해야 하는군요. 예제 3번으로 한 번 더 확인해볼게요!',
        createdAt: _at(3, 14, 31),
      ),
    ];

List<ConnectionNote> goldenNotes() => <ConnectionNote>[
      ConnectionNote(
        id: 'n1',
        roomId: kRoomId,
        body: '삼각함수 합성·미분 단원은 개념은 잡혔고 계산 실수가 잦음. '
            '주 2회 오답노트 점검 예정. 다음 주부터 확률과통계 시작.',
        authorId: kMentorId,
        authorRole: NoteAuthorRole.mentor,
        createdAt: _at(1),
        updatedAt: _at(3, 19),
      ),
      ConnectionNote(
        id: 'n2',
        roomId: kRoomId,
        body: '목표: 9월 모의고사 수학 2등급. 평일 1시간, 주말 3시간 학습 중.',
        authorId: kStudentId,
        authorRole: NoteAuthorRole.student,
        createdAt: _at(1),
        updatedAt: _at(2, 21),
      ),
    ];

// ── 질문방 1뎁스(학생 목록·멘토 인박스) 픽스처 ──────────────────────────────

const String kMentor2Id = 'm2';
const String kMentor3Id = 'm3';
const String kStudent2Id = 's2';
const String kStudent3Id = 's3';

Room _roomOf(String id, String studentId, String mentorId, int day) => Room(
      id: id,
      studentId: studentId,
      mentorId: mentorId,
      createdAt: _at(1),
      updatedAt: _at(day),
    );

/// 학생 s1 의 멘토방 3개 — 활성 구독·만료 구독·구독 정보 없음.
List<Room> goldenStudentRooms() => <Room>[
      _roomOf(kRoomId, kStudentId, kMentorId, 3),
      _roomOf('r2', kStudentId, kMentor2Id, 2),
      _roomOf('r3', kStudentId, kMentor3Id, 1),
    ];

Map<String, MentorPublic> goldenMentors() => const <String, MentorPublic>{
      kMentorId: MentorPublic(id: kMentorId, nickname: kMentorName),
      kMentor2Id: MentorPublic(id: kMentor2Id, nickname: '박멘토'),
      kMentor3Id: MentorPublic(id: kMentor3Id, nickname: '최멘토'),
    };

Map<String, SubscriptionSummary> goldenSubscriptionsByMentor() =>
    <String, SubscriptionSummary>{
      kMentorId: goldenSubscription(),
      kMentor2Id: const SubscriptionSummary(
        mentorId: kMentor2Id,
        isActive: false,
        status: 'expired',
      ),
    };

Map<String, WeeklyQuestionUsage?> goldenUsageByMentor() =>
    const <String, WeeklyQuestionUsage?>{
      kMentorId: goldenUsage,
      kMentor2Id: null,
      kMentor3Id: null,
    };

ThreadStatusRow _statusRow(String roomId, ThreadStatus status, int day,
        [int hour = 18]) =>
    ThreadStatusRow(roomId: roomId, status: status, updatedAt: _at(day, hour));

/// 학생 목록용 스레드 상태 행 — r1 대기+답변완료, r2 확인완료, r3 없음.
List<ThreadStatusRow> goldenStudentStatusRows() => <ThreadStatusRow>[
      _statusRow(kRoomId, ThreadStatus.pending, 3),
      _statusRow(kRoomId, ThreadStatus.answered, 2, 14),
      _statusRow('r2', ThreadStatus.confirmed, 2, 10),
    ];

/// 멘토 m1 의 학생방 3개.
List<Room> goldenMentorRooms() => <Room>[
      _roomOf(kRoomId, kStudentId, kMentorId, 3),
      _roomOf('r4', kStudent2Id, kMentorId, 1),
      _roomOf('r5', kStudent3Id, kMentorId, 1),
    ];

Map<String, StudentPublic> goldenStudents() => const <String, StudentPublic>{
      kStudentId: StudentPublic(id: kStudentId, nickname: kStudentName),
      kStudent2Id: StudentPublic(id: kStudent2Id, nickname: '박학생'),
      kStudent3Id: StudentPublic(id: kStudent3Id, fullName: '최민준'),
    };

/// 인박스용 상태 행 — r1 답할 것 1(pending), r4 답변완료, r5 확인완료 2.
List<ThreadStatusRow> goldenMentorStatusRows() => <ThreadStatusRow>[
      _statusRow(kRoomId, ThreadStatus.pending, 3),
      _statusRow(kRoomId, ThreadStatus.answered, 2, 14),
      _statusRow('r4', ThreadStatus.answered, 1, 15),
      _statusRow('r5', ThreadStatus.confirmed, 1, 9),
      _statusRow('r5', ThreadStatus.confirmed, 1, 11),
    ];

MyPageData goldenStudentMyPage() => MyPageData(
      role: AppRole.student,
      profile: const MyProfile(
        name: kStudentName,
        roleLabel: '학생',
        email: 'student@example.com',
        grade: '고2',
      ),
      subscriptions: <SubscriptionCardInfo>[
        SubscriptionCardInfo(
          mentorName: kMentorName,
          isActive: true,
          status: 'active',
          nextRenewal: _at(27),
          usage: goldenUsage,
        ),
        const SubscriptionCardInfo(
          mentorName: '박멘토',
          isActive: false,
          status: 'expired',
        ),
      ],
      cash: CashSummary(
        balanceCents: 5000000,
        recent: <CashEntry>[
          CashEntry(
            deltaCents: 5000000,
            createdAt: _at(1),
            reason: 'cash_topup',
          ),
          CashEntry(
            deltaCents: -1500000,
            createdAt: _at(2),
            reason: 'individual_question_escrow_hold',
          ),
        ],
      ),
    );

MyPageData goldenMentorMyPage() => const MyPageData(
      role: AppRole.mentor,
      profile: MyProfile(
        name: kMentorName,
        roleLabel: '멘토',
        email: 'mentor@example.com',
      ),
      mentor: MentorDashboard(
        studentCount: 12,
        pendingAnswers: 3,
        latestSettlementCents: 84000000,
      ),
    );

// ── 포트 fake ────────────────────────────────────────────────────────────

/// 읽기 레포 fake — 화면이 initState 에서 호출하는 조회만 고정 데이터로 응답한다.
/// 기반 클래스의 나머지 메서드는 백엔드에 닿는 즉시 AppError 를 던지므로,
/// 골든이 새 조회를 필요로 하면 여기서 오버라이드가 필요하다(= 계측 지점).
class GoldenReadRepository extends QuestionRoomReadRepository {
  const GoldenReadRepository({
    this.threadRows = const <QuestionThread>[],
    this.messageRows = const <QuestionMessage>[],
    this.noteRows = const <ConnectionNote>[],
    this.usage,
    this.roomRows = const <Room>[],
    this.statusRows = const <ThreadStatusRow>[],
    this.usageByMentor = const <String, WeeklyQuestionUsage?>{},
  });

  final List<QuestionThread> threadRows;
  final List<QuestionMessage> messageRows;
  final List<ConnectionNote> noteRows;
  final WeeklyQuestionUsage? usage;
  final List<Room> roomRows;
  final List<ThreadStatusRow> statusRows;
  final Map<String, WeeklyQuestionUsage?> usageByMentor;

  @override
  Future<List<Room>> myRooms() async => roomRows;

  @override
  Future<List<ThreadStatusRow>> threadStatusRowsForRooms(
          List<String> roomIds) async =>
      statusRows
          .where((ThreadStatusRow r) => roomIds.contains(r.roomId))
          .toList();

  @override
  Future<Map<String, WeeklyQuestionUsage?>> weeklyUsageBatch(
          Iterable<String> mentorIds) async =>
      <String, WeeklyQuestionUsage?>{
        for (final String id in mentorIds) id: usageByMentor[id],
      };

  @override
  Future<List<QuestionThread>> threads(String roomId) async => threadRows;

  @override
  Future<WeeklyQuestionUsage?> weeklyUsage({required String mentorId}) async =>
      usage;

  /// 새 질문 과목 칩 후보(멘토 담당 과목) — 픽스처 고정(Supabase 미접속).
  @override
  Future<List<String>> mentorTeachingSubjects(String mentorId) async =>
      const <String>['math', 'english'];

  @override
  Future<List<QuestionMessage>> recentMessages(
    String threadId, {
    required int limit,
  }) async =>
      messageRows;

  @override
  Future<List<QuestionMessage>> messagesBefore(
    String threadId, {
    required MessageCursor cursor,
    required int limit,
  }) async =>
      const <QuestionMessage>[];

  @override
  Future<List<QuestionAttachment>> attachments(String threadId) async =>
      const <QuestionAttachment>[];

  @override
  Future<List<ConnectionNote>> notes(String roomId) async => noteRows;

  @override
  Future<QuestionThread?> threadById(String threadId) async => null;
}

/// 실시간 포트 no-op — 구독하지 않는다(골든은 정지 화면).
class GoldenNoopRealtime implements ThreadRealtimePort {
  @override
  void start({
    required void Function(QuestionMessage message) onMessageInsert,
    void Function()? onThreadUpdate,
    void Function()? onAttachmentInsert,
  }) {}

  @override
  Future<void> dispose() async {}
}

/// 신고·차단 포트 fake — 차단 안 됨(composer 활성 상태로 렌더).
class GoldenSafety implements RoomSafetyPort {
  const GoldenSafety();

  @override
  Future<bool> isBlockedByMe(String targetUserId) async => false;

  @override
  Future<SafetyOutcome> blockUser(String targetUserId) async =>
      SafetyOutcome.failed;

  @override
  Future<SafetyOutcome> reportUser({
    required String targetUserId,
    required String reason,
    String? description,
  }) async =>
      SafetyOutcome.failed;
}

/// 첨부 업로더 fake — 준비 안 됨(골든에서는 전송 경로를 타지 않는다).
class GoldenUploader implements AttachmentUploaderPort {
  const GoldenUploader();

  @override
  bool get isReady => false;

  @override
  Future<AttachmentUploadResult> upload({
    required String roomId,
    required String threadId,
    String? messageId,
    required PickedImage image,
  }) =>
      throw UnsupportedError('golden fixture: upload is disabled');
}
