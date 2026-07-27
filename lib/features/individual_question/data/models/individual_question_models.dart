/// 개별질문(IQ) 도메인 모델 + 표시/규칙 헬퍼.
///
/// 웹 정본을 미러링한다(값·라벨 날조 금지):
/// - 상태/유형: ssambership_web `lib/individualQuestion/individualQuestionTypes.ts`
/// - 라벨·만료 표기: `individualQuestionFormat.ts`
/// - 액션 가드: `individualQuestionActions.ts` (취소는 answered 이후 불가,
///   확정(release)은 answered 에서만)
/// 저장 금액은 cents(=캐시×100) 정수 — 표시는 ÷100 캐시(지갑·구독과 동일 규약).
library;

/// 질문 유형. direct = 지정형(멘토 지정·가격표 조회), open = 공개형(금액 자유).
enum IndividualQuestionType { direct, open, unknown }

IndividualQuestionType iqTypeFromDb(String? v) {
  switch ((v ?? '').trim().toLowerCase()) {
    case 'direct':
      return IndividualQuestionType.direct;
    case 'open':
      return IndividualQuestionType.open;
    default:
      return IndividualQuestionType.unknown;
  }
}

/// 유형 한글 라벨(웹 정본: 공개형/지정형).
String iqTypeLabel(IndividualQuestionType t) =>
    t == IndividualQuestionType.open ? '공개형' : '지정형';

/// IQ 목록 '질문 유형' 필터(멘토·학생 공용). 유형 기준이라 상태(진행중/완료 등)와 독립.
/// - all        = 전체
/// - direct     = 지정형(question_type=='direct')
/// - openClaimed= 공개형 + 답변자 확정(claimed_mentor_id != null)
/// - openWaiting= 공개형 + 답변자 미정(claimed_mentor_id == null)
enum IqTypeFilter { all, direct, openClaimed, openWaiting }

/// 칩 노출 순서(라벨 확정: 전체 / 지정 / 공개·확정 / 공개·대기).
const List<IqTypeFilter> kIqTypeFilters = <IqTypeFilter>[
  IqTypeFilter.all,
  IqTypeFilter.direct,
  IqTypeFilter.openClaimed,
  IqTypeFilter.openWaiting,
];

/// 필터 한글 라벨.
String iqTypeFilterLabel(IqTypeFilter f) {
  switch (f) {
    case IqTypeFilter.all:
      return '전체';
    case IqTypeFilter.direct:
      return '지정';
    case IqTypeFilter.openClaimed:
      return '공개·확정';
    case IqTypeFilter.openWaiting:
      return '공개·대기';
  }
}

/// 질문 1건이 유형 필터에 부합하는지(유형 기준 — 상태와 독립).
bool iqMatchesTypeFilter(IndividualQuestion q, IqTypeFilter f) {
  switch (f) {
    case IqTypeFilter.all:
      return true;
    case IqTypeFilter.direct:
      return q.type == IndividualQuestionType.direct;
    case IqTypeFilter.openClaimed:
      return q.type == IndividualQuestionType.open && q.claimedMentorId != null;
    case IqTypeFilter.openWaiting:
      return q.type == IndividualQuestionType.open && q.claimedMentorId == null;
  }
}

/// 멘토 목록의 '수락 대기(공개형)' 섹션(OpenIndividualQuestion)은 정의상
/// 공개·대기(open·미확정)다. 이 섹션을 필터에서 보여줄지 여부.
bool iqShowOpenWaitingSection(IqTypeFilter f) =>
    f == IqTypeFilter.all || f == IqTypeFilter.openWaiting;

/// 상태(웹 070 CHECK 값 + 미지 방어).
enum IndividualQuestionStatus {
  escrowed,
  assigned,
  open,
  claimed,
  answered,
  released,
  expired,
  refunded,
  canceled,
  unknown,
}

IndividualQuestionStatus iqStatusFromDb(String? v) {
  switch ((v ?? '').trim().toLowerCase()) {
    case 'escrowed':
      return IndividualQuestionStatus.escrowed;
    case 'assigned':
      return IndividualQuestionStatus.assigned;
    case 'open':
      return IndividualQuestionStatus.open;
    case 'claimed':
      return IndividualQuestionStatus.claimed;
    case 'answered':
      return IndividualQuestionStatus.answered;
    case 'released':
      return IndividualQuestionStatus.released;
    case 'expired':
      return IndividualQuestionStatus.expired;
    case 'refunded':
      return IndividualQuestionStatus.refunded;
    case 'canceled':
      return IndividualQuestionStatus.canceled;
    default:
      return IndividualQuestionStatus.unknown;
  }
}

/// 상태 한글 라벨(코드 비노출).
/// ★ answered/released 는 앱 전용 새 용어(답변 도착/답변완료) — 웹은 추후 별도 반영.
String iqStatusLabel(IndividualQuestionStatus s) {
  switch (s) {
    case IndividualQuestionStatus.escrowed:
      return '예치중';
    case IndividualQuestionStatus.open:
      return '공개중';
    case IndividualQuestionStatus.assigned:
    case IndividualQuestionStatus.claimed:
      return '답변중';
    case IndividualQuestionStatus.answered:
      return '답변 도착';
    case IndividualQuestionStatus.released:
      return '답변완료';
    case IndividualQuestionStatus.refunded:
      return '환불';
    case IndividualQuestionStatus.expired:
      return '만료';
    case IndividualQuestionStatus.canceled:
      return '취소';
    case IndividualQuestionStatus.unknown:
      return '진행 중';
  }
}

/// 아직 답변을 기다리는 상태인지(웹 `isIndividualQuestionAwaitingAnswer` 미러).
bool iqAwaitingAnswer(IndividualQuestionStatus s) {
  switch (s) {
    case IndividualQuestionStatus.escrowed:
    case IndividualQuestionStatus.open:
    case IndividualQuestionStatus.assigned:
    case IndividualQuestionStatus.claimed:
      return true;
    default:
      return false;
  }
}

/// 학생이 답변 확정(release·정산)할 수 있는 상태인지 — answered 에서만.
bool iqCanStudentRelease(IndividualQuestionStatus s) =>
    s == IndividualQuestionStatus.answered;

/// 학생이 질문 취소(환불)할 수 있는 상태인지 — 웹 가드 미러:
/// answered/released/종결(환불·만료·취소) 이후에는 불가.
bool iqCanStudentRefund(IndividualQuestionStatus s) => iqAwaitingAnswer(s);

/// 멘토가 답변을 작성할 수 있는 상태인지 — RPC 가드와 동일(claimed/assigned).
bool iqCanMentorAnswer(IndividualQuestionStatus s) =>
    s == IndividualQuestionStatus.claimed ||
    s == IndividualQuestionStatus.assigned;

/// cents 정수 → "5,000캐시" (웹 `formatIndividualQuestionPrice` 미러: ÷100).
String formatIqCash(int amountCents) {
  final int cash = amountCents.abs() ~/ 100;
  final String s = cash.toString();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b캐시';
}

/// 답변 대기 상태의 남은 마감 표기(웹 미러). 대기 아님/마감 없음 → null.
/// "마감 지남" / "곧 마감" / "N시간 후 마감" / "N일 후 마감".
String? formatIqExpiryRemaining(
  DateTime? expiresAt,
  IndividualQuestionStatus status, {
  DateTime Function()? now,
}) {
  if (!iqAwaitingAnswer(status) || expiresAt == null) return null;
  final Duration remaining = expiresAt.difference((now ?? DateTime.now)());
  if (remaining.isNegative || remaining == Duration.zero) return '마감 지남';
  final int hours = remaining.inHours;
  if (hours < 1) return '곧 마감';
  if (hours < 24) return '$hours시간 후 마감';
  return '${remaining.inDays}일 후 마감';
}

/// RPC 실패(raise exception 문자열)를 사용자용 한글 메시지로 변환.
/// 내부 코드·영문은 화면에 노출하지 않는다. 미지 코드는 일반 안내로 폴백.
String iqFailureMessage(Object error) {
  final String raw = error.toString();
  if (raw.contains('CASH_INSUFFICIENT')) {
    return '캐시가 부족해요. 충전은 웹에서 할 수 있어요.';
  }
  if (raw.contains('MENTOR_PRICE_NOT_SET')) {
    return '이 멘토는 아직 개별질문 가격을 설정하지 않았어요.';
  }
  if (raw.contains('NOT_QUESTION_OWNER') ||
      raw.contains('NOT_QUESTION_MENTOR')) {
    return '이 질문에 대한 권한이 없어요.';
  }
  if (raw.contains('not_answered') || raw.contains('NOT_ANSWERABLE_STATUS')) {
    return '지금 상태에서는 진행할 수 없어요. 화면을 새로고침해 주세요.';
  }
  if (raw.contains('REFUND_NOT_ALLOWED')) {
    // 서버 wrapper: escrowed/open/assigned/claimed 외 상태의 취소 거부(P0-5).
    return '지금 상태에서는 질문을 취소할 수 없어요. 화면을 새로고침해 주세요.';
  }
  if (raw.contains('INDIVIDUAL_QUESTION_REFUND_FAILED')) {
    return '환불을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.';
  }
  if (raw.contains('already_released')) {
    return '이미 정산이 완료된 질문이에요.';
  }
  if (raw.contains('already_refunded')) {
    return '이미 환불된 질문이에요.';
  }
  if (raw.contains('already_claimed') || raw.contains('CLAIM_FAILED')) {
    return '다른 멘토가 먼저 수락했거나 수락할 수 없는 상태예요.';
  }
  if (raw.contains('QUESTION_NOT_FOUND')) {
    return '질문을 찾을 수 없어요.';
  }
  if (raw.contains('AUTH_REQUIRED')) {
    return '로그인이 필요해요.';
  }
  return '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

DateTime? _parseTime(Object? v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

int _parseInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return 0;
}

/// 개별질문 1건(individual_questions 행).
class IndividualQuestion {
  const IndividualQuestion({
    required this.id,
    required this.studentId,
    required this.type,
    required this.status,
    required this.title,
    required this.body,
    required this.priceCents,
    this.designatedMentorId,
    this.claimedMentorId,
    this.subject,
    this.topic,
    this.expiresAt,
    this.answeredAt,
    this.releasedAt,
    this.refundedAt,
    this.createdAt,
  });

  final String id;
  final String studentId;
  final IndividualQuestionType type;
  final IndividualQuestionStatus status;
  final String title;
  final String body;
  final int priceCents;
  final String? designatedMentorId;
  final String? claimedMentorId;
  final String? subject;
  final String? topic;
  final DateTime? expiresAt;
  final DateTime? answeredAt;
  final DateTime? releasedAt;
  final DateTime? refundedAt;
  final DateTime? createdAt;

  /// 답변·정산의 담당 멘토(웹 payout 규칙: claimed 우선 → designated).
  String? get mentorId => claimedMentorId ?? designatedMentorId;

  factory IndividualQuestion.fromMap(Map<String, dynamic> map) {
    return IndividualQuestion(
      id: map['id'] as String,
      studentId: (map['student_id'] as String?) ?? '',
      type: iqTypeFromDb(map['question_type'] as String?),
      status: iqStatusFromDb(map['status'] as String?),
      title: (map['title'] as String?)?.trim() ?? '',
      body: (map['body'] as String?) ?? '',
      priceCents: _parseInt(map['price_cents']),
      designatedMentorId: map['designated_mentor_id'] as String?,
      claimedMentorId: map['claimed_mentor_id'] as String?,
      subject: map['subject'] as String?,
      topic: map['topic'] as String?,
      expiresAt: _parseTime(map['expires_at']),
      answeredAt: _parseTime(map['answered_at']),
      releasedAt: _parseTime(map['released_at']),
      refundedAt: _parseTime(map['refunded_at']),
      createdAt: _parseTime(map['created_at']),
    );
  }
}

/// 멘토용 공개 대기 질문(위생 처리된 RPC 행 — 본문·학생 정보 없음).
class OpenIndividualQuestion {
  const OpenIndividualQuestion({
    required this.id,
    required this.title,
    required this.priceCents,
    this.subject,
    this.topic,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String title;
  final int priceCents;
  final String? subject;
  final String? topic;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory OpenIndividualQuestion.fromMap(Map<String, dynamic> map) {
    return OpenIndividualQuestion(
      id: map['id'] as String,
      title: (map['title'] as String?)?.trim() ?? '',
      priceCents: _parseInt(map['price_cents']),
      subject: map['subject'] as String?,
      topic: map['topic'] as String?,
      expiresAt: _parseTime(map['expires_at']),
      createdAt: _parseTime(map['created_at']),
    );
  }
}

/// 질문 스레드 메시지(individual_question_messages 행).
class IqMessage {
  const IqMessage({
    required this.id,
    required this.questionId,
    required this.authorId,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String questionId;
  final String authorId;
  final String body;
  final DateTime? createdAt;

  factory IqMessage.fromMap(Map<String, dynamic> map) {
    return IqMessage(
      id: map['id'] as String,
      questionId: (map['question_id'] as String?) ?? '',
      authorId: (map['author_id'] as String?) ?? '',
      body: (map['body'] as String?) ?? '',
      createdAt: _parseTime(map['created_at']),
    );
  }
}

/// 첨부(조회 전용 — 앱은 첨부 행을 만들지 않는다. 업로드는 웹에서).
class IqAttachment {
  const IqAttachment({
    required this.id,
    required this.storagePath,
    this.messageId,
    this.fileName,
    this.mimeType,
  });

  final String id;
  final String storagePath;
  final String? messageId;
  final String? fileName;
  final String? mimeType;

  factory IqAttachment.fromMap(Map<String, dynamic> map) {
    return IqAttachment(
      id: map['id'] as String,
      storagePath: (map['storage_path'] as String?) ?? '',
      messageId: map['message_id'] as String?,
      fileName: map['file_name'] as String?,
      mimeType: map['mime_type'] as String?,
    );
  }
}

/// 멘토 지정형 가격(mentor_individual_question_pricing 행).
class IqPricing {
  const IqPricing({required this.mentorId, required this.amountCents});

  final String mentorId;
  final int amountCents;

  factory IqPricing.fromMap(Map<String, dynamic> map) {
    return IqPricing(
      mentorId: (map['mentor_id'] as String?) ?? '',
      amountCents: _parseInt(map['amount_cents']),
    );
  }
}

/// 에스크로 RPC 공통 결과(070 `individual_question_escrow_result`).
class IqEscrowResult {
  const IqEscrowResult({
    required this.ok,
    required this.code,
    this.message,
    this.questionId,
    this.status,
    this.walletBalanceCents,
  });

  final bool ok;
  final String code;
  final String? message;
  final String? questionId;
  final IndividualQuestionStatus? status;
  final int? walletBalanceCents;

  factory IqEscrowResult.fromMap(Map<String, dynamic> map) {
    return IqEscrowResult(
      ok: (map['ok'] as bool?) ?? false,
      code: (map['code'] as String?) ?? '',
      message: map['message'] as String?,
      questionId: map['question_id'] as String?,
      status: map['status'] == null
          ? null
          : iqStatusFromDb(map['status'] as String?),
      walletBalanceCents: map['wallet_balance_cents'] == null
          ? null
          : _parseInt(map['wallet_balance_cents']),
    );
  }
}
