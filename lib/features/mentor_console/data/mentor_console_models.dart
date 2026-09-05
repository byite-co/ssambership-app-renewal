/// 멘토 콘솔(A-4a) 도메인 모델 — 정산 계좌·요금제·정산 조회·학력 인증·학적 변경·
/// 본인 프로필. 서버 행/봉투를 그대로 옮긴 읽기 전용 값 객체다(금액 계산 0).
library;

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

DateTime? _time(Object? v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

String? _str(Object? v) {
  if (v is! String) return null;
  final String t = v.trim();
  return t.isEmpty ? null : t;
}

/// 정산 계좌 조회 결과(본인 행 SELECT). 계좌번호는 **마스킹 값만** 보관한다 —
/// 원문은 화면·로그·저장소 어디에도 남기지 않는다(F13 §11.4).
class PayoutAccountInfo {
  const PayoutAccountInfo({this.bankName, this.accountMasked});

  final String? bankName;

  /// 끝 4자리 외 `*`. 미등록이면 null.
  final String? accountMasked;

  bool get registered =>
      (bankName?.isNotEmpty ?? false) && (accountMasked?.isNotEmpty ?? false);

  /// 본인 행 → 마스킹 결과. 원문 계좌번호는 이 생성자 안에서만 존재한다.
  factory PayoutAccountInfo.fromRow(Map<String, dynamic>? row) {
    final String? bank = _str(row?['payout_bank_name']);
    final String? raw = _str(row?['payout_account_number']);
    return PayoutAccountInfo(
      bankName: bank,
      accountMasked: raw == null ? null : maskPayoutAccount(raw),
    );
  }
}

/// 끝 4자리만 남기고 `*` 처리(F13 서버 마스킹식과 동일).
String maskPayoutAccount(String raw) {
  final String digits = raw.trim();
  if (digits.isEmpty) return '';
  final int hidden = digits.length - 4;
  if (hidden <= 0) return digits;
  return '${'*' * hidden}${digits.substring(hidden)}';
}

/// 요금제 등급 3종 — 순서는 F8 인자 순서(라이트·스탠다드·프리미엄)와 같다.
enum MentorPlanTier { limited, standard, premium }

/// 요금제 밴드(캐시=원). ★ 웹 정본 `lib/subscribe/mentorPlanPricing.ts` · DB F8
/// 상수와 동일 — 세 곳을 같은 PR 에서 함께 바꾼다. 앱은 사전 안내·버튼 비활성에만
/// 쓰고, 최종 판정은 서버(PLAN_PRICE_OUT_OF_BAND)가 한다.
class PlanPriceBand {
  const PlanPriceBand._(this.tier, this.minWon, this.maxWon);

  final MentorPlanTier tier;
  final int minWon;
  final int maxWon;

  static const PlanPriceBand limited =
      PlanPriceBand._(MentorPlanTier.limited, 29900, 69900);
  static const PlanPriceBand standard =
      PlanPriceBand._(MentorPlanTier.standard, 84900, 149900);
  static const PlanPriceBand premium =
      PlanPriceBand._(MentorPlanTier.premium, 174900, 329900);

  static PlanPriceBand of(MentorPlanTier tier) {
    switch (tier) {
      case MentorPlanTier.limited:
        return limited;
      case MentorPlanTier.standard:
        return standard;
      case MentorPlanTier.premium:
        return premium;
    }
  }

  bool contains(int won) => won >= minWon && won <= maxWon;
}

/// 등급 한글 라벨(코드값 비노출).
String mentorPlanTierLabel(MentorPlanTier tier) {
  switch (tier) {
    case MentorPlanTier.limited:
      return '라이트';
    case MentorPlanTier.standard:
      return '스탠다드';
    case MentorPlanTier.premium:
      return '프리미엄';
  }
}

/// 등급별 주간 문항 안내(웹 카탈로그 032/065 정본: 4·9·무제한).
String mentorPlanTierQuotaLabel(MentorPlanTier tier) {
  switch (tier) {
    case MentorPlanTier.limited:
      return '주 4문항';
    case MentorPlanTier.standard:
      return '주 9문항';
    case MentorPlanTier.premium:
      return '질문 무제한';
  }
}

/// 본인 요금제 현재값(캐시=원). 행이 없는 등급은 null(미설정).
class MentorPlanPrices {
  const MentorPlanPrices({this.limitedWon, this.standardWon, this.premiumWon});

  final int? limitedWon;
  final int? standardWon;
  final int? premiumWon;

  int? won(MentorPlanTier tier) {
    switch (tier) {
      case MentorPlanTier.limited:
        return limitedWon;
      case MentorPlanTier.standard:
        return standardWon;
      case MentorPlanTier.premium:
        return premiumWon;
    }
  }

  /// `mentor_plans` 본인 행 목록 → 등급별 원 단위(amount_cents ÷ 100).
  factory MentorPlanPrices.fromRows(List<Map<String, dynamic>> rows) {
    int? limited;
    int? standard;
    int? premium;
    for (final Map<String, dynamic> r in rows) {
      final int won = _int(r['amount_cents']) ~/ 100;
      switch (_str(r['plan_tier'])) {
        case 'limited':
          limited = won;
        case 'standard':
          standard = won;
        case 'premium':
          premium = won;
      }
    }
    return MentorPlanPrices(
      limitedWon: limited,
      standardWon: standard,
      premiumWon: premium,
    );
  }
}

/// 정산 월 요약(`mentor_settlement_summary` jsonb). 금액은 전부 cents 원문 보존.
class SettlementSummary {
  const SettlementSummary({
    required this.month,
    required this.runDate,
    required this.payoutAccountRegistered,
    required this.confirmedNetCents,
    required this.confirmedCount,
    required this.accruingNetCents,
    required this.accruingCount,
    required this.heldMentorAmountCents,
    required this.heldCount,
    required this.paidTotalNetCents,
    required this.paidTotalCount,
    required this.bySource,
  });

  /// 'YYYY-MM'.
  final String month;

  /// 'YYYY-MM-DD' — 이 달 확정분의 지급(예정)일.
  final String runDate;

  /// false 면 지급 run 이 건너뛰고 다음 달로 이월된다.
  final bool payoutAccountRegistered;

  final int confirmedNetCents;
  final int confirmedCount;
  final int accruingNetCents;
  final int accruingCount;
  final int heldMentorAmountCents;
  final int heldCount;
  final int paidTotalNetCents;
  final int paidTotalCount;

  /// 이번 달 발생 기준 소스별 멘토 몫(source_type → {mentor_amount_cents, count}).
  final Map<String, SettlementSourceAmount> bySource;

  /// 이번 달 받을 금액(확정분 실수령).
  int get thisMonthNetCents => confirmedNetCents;

  SettlementSourceAmount source(String type) =>
      bySource[type] ?? const SettlementSourceAmount(mentorAmountCents: 0, count: 0);

  factory SettlementSummary.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final Object? v = json[key];
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    }

    final Map<String, dynamic> confirmed = section('confirmed');
    final Map<String, dynamic> accruing = section('accruing');
    final Map<String, dynamic> held = section('held');
    final Map<String, dynamic> paid = section('paid_total');
    final Map<String, SettlementSourceAmount> bySource =
        <String, SettlementSourceAmount>{};
    final Object? rawBySource = json['by_source_this_month'];
    if (rawBySource is Map) {
      for (final MapEntry<dynamic, dynamic> e in rawBySource.entries) {
        final Object? v = e.value;
        if (e.key is String && v is Map) {
          bySource[e.key as String] = SettlementSourceAmount(
            mentorAmountCents: _int(v['mentor_amount_cents']),
            count: _int(v['count']),
          );
        }
      }
    }
    return SettlementSummary(
      month: _str(json['month']) ?? '',
      runDate: _str(json['run_date']) ?? '',
      payoutAccountRegistered: json['payout_account_registered'] == true,
      confirmedNetCents: _int(confirmed['net_cents']),
      confirmedCount: _int(confirmed['count']),
      accruingNetCents: _int(accruing['net_cents']),
      accruingCount: _int(accruing['count']),
      heldMentorAmountCents: _int(held['mentor_amount_cents']),
      heldCount: _int(held['count']),
      paidTotalNetCents: _int(paid['net_cents']),
      paidTotalCount: _int(paid['count']),
      bySource: bySource,
    );
  }
}

class SettlementSourceAmount {
  const SettlementSourceAmount({
    required this.mentorAmountCents,
    required this.count,
  });

  final int mentorAmountCents;
  final int count;
}

/// 정산 라인 상태(RPC 정규화 5종). 그 외 값은 [unknown] — 무음 매핑 금지.
enum SettlementLineStatus { accruing, pending, hold, paid, canceled, unknown }

SettlementLineStatus settlementLineStatusFromCode(String? code) {
  switch (code?.trim()) {
    case 'accruing':
      return SettlementLineStatus.accruing;
    case 'pending':
      return SettlementLineStatus.pending;
    case 'hold':
      return SettlementLineStatus.hold;
    case 'paid':
      return SettlementLineStatus.paid;
    case 'canceled':
      return SettlementLineStatus.canceled;
    default:
      return SettlementLineStatus.unknown;
  }
}

/// 라인 상태 한글(웹 STATUS_LABELS 와 동일).
String settlementLineStatusLabel(SettlementLineStatus s) {
  switch (s) {
    case SettlementLineStatus.accruing:
      return '적립중';
    case SettlementLineStatus.pending:
      return '지급 예정';
    case SettlementLineStatus.hold:
      return '보류';
    case SettlementLineStatus.paid:
      return '지급 완료';
    case SettlementLineStatus.canceled:
      return '취소';
    case SettlementLineStatus.unknown:
      return '상태 확인 필요';
  }
}

/// 소스 유형 한글.
String settlementSourceLabel(String? sourceType) {
  switch (sourceType?.trim()) {
    case 'subscription':
      return '구독';
    case 'custom_request':
      return '맞춤의뢰';
    case 'individual_question':
      return '개별질문';
    default:
      return '정산 항목';
  }
}

/// 정산 라인 1건(`mentor_settlement_lines` 행).
class SettlementLine {
  const SettlementLine({
    required this.sourceType,
    required this.sourceId,
    required this.occurredAt,
    this.periodStart,
    this.periodEnd,
    required this.grossCents,
    required this.platformFeeCents,
    required this.mentorAmountCents,
    required this.withholdingCents,
    required this.netCents,
    required this.status,
    this.holdReason,
    this.expectedRunDate,
    this.paidRunDate,
    this.paidAt,
  });

  final String sourceType;
  final String sourceId;
  final DateTime? occurredAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int grossCents;
  final int platformFeeCents;
  final int mentorAmountCents;
  final int withholdingCents;
  final int netCents;
  final SettlementLineStatus status;
  final String? holdReason;
  final String? expectedRunDate;
  final String? paidRunDate;
  final DateTime? paidAt;

  /// 지급(예정)일 = paid_run_date ?? expected_run_date.
  String? get payDate => paidRunDate ?? expectedRunDate;

  factory SettlementLine.fromMap(Map<String, dynamic> map) {
    return SettlementLine(
      sourceType: _str(map['source_type']) ?? '',
      sourceId: _str(map['source_id']) ?? '',
      occurredAt: _time(map['occurred_at']),
      periodStart: _time(map['period_start']),
      periodEnd: _time(map['period_end']),
      grossCents: _int(map['gross_cents']),
      platformFeeCents: _int(map['platform_fee_cents']),
      mentorAmountCents: _int(map['mentor_amount_cents']),
      withholdingCents: _int(map['withholding_cents']),
      netCents: _int(map['net_cents']),
      status: settlementLineStatusFromCode(_str(map['status'])),
      holdReason: _str(map['hold_reason']),
      expectedRunDate: _str(map['expected_run_date']),
      paidRunDate: _str(map['paid_run_date']),
      paidAt: _time(map['paid_at']),
    );
  }
}

/// 검토형 제출(학력 인증·학적 변경) 공통 상태.
enum ReviewStatus { pending, approved, rejected, resubmitRequired, superseded, unknown }

ReviewStatus reviewStatusFromCode(String? code) {
  switch (code?.trim()) {
    case 'pending':
      return ReviewStatus.pending;
    case 'approved':
      return ReviewStatus.approved;
    case 'rejected':
      return ReviewStatus.rejected;
    case 'resubmit_required':
      return ReviewStatus.resubmitRequired;
    case 'superseded':
      return ReviewStatus.superseded;
    default:
      return ReviewStatus.unknown;
  }
}

/// 학교·전공 인증 행(`mentor_school_verifications` 본인 행).
class SchoolVerificationRecord {
  const SchoolVerificationRecord({
    required this.id,
    required this.status,
    this.verifiedUniversityName,
    this.verifiedDepartmentName,
    this.schoolTier,
    this.documentStorageRef,
    this.reviewedAt,
    this.rejectReason,
    required this.createdAt,
  });

  final String id;
  final ReviewStatus status;
  final String? verifiedUniversityName;
  final String? verifiedDepartmentName;
  final String? schoolTier;
  final String? documentStorageRef;
  final DateTime? reviewedAt;
  final String? rejectReason;
  final DateTime createdAt;

  /// 서류 없이 서버가 자동 생성한 잠정 행(192 트리거)인지.
  bool get hasDocument => documentStorageRef?.isNotEmpty ?? false;

  factory SchoolVerificationRecord.fromMap(Map<String, dynamic> map) {
    return SchoolVerificationRecord(
      id: map['id'] as String,
      status: reviewStatusFromCode(_str(map['status'])),
      verifiedUniversityName: _str(map['verified_university_name']),
      verifiedDepartmentName: _str(map['verified_department_name']),
      schoolTier: _str(map['school_tier']),
      documentStorageRef: _str(map['document_storage_ref']),
      reviewedAt: _time(map['reviewed_at']),
      rejectReason: _str(map['reject_reason']),
      createdAt: _time(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 학적 변경 요청 행(`mentor_academic_record_change_requests` 본인 행).
class AcademicRecordChangeRecord {
  const AcademicRecordChangeRecord({
    required this.id,
    required this.status,
    this.requestedUniversityName,
    this.changeReason,
    this.approvedUniversityName,
    this.rejectReason,
    this.reviewedAt,
    required this.createdAt,
  });

  final String id;
  final ReviewStatus status;
  final String? requestedUniversityName;
  final String? changeReason;
  final String? approvedUniversityName;
  final String? rejectReason;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  factory AcademicRecordChangeRecord.fromMap(Map<String, dynamic> map) {
    return AcademicRecordChangeRecord(
      id: map['id'] as String,
      status: reviewStatusFromCode(_str(map['status'])),
      requestedUniversityName: _str(map['requested_university_name']),
      changeReason: _str(map['change_reason']),
      approvedUniversityName: _str(map['approved_university_name']),
      rejectReason: _str(map['reject_reason']),
      reviewedAt: _time(map['reviewed_at']),
      createdAt: _time(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 본인 멘토 프로필(F7 allowlist 9필드 + 표시용 상태). `mentor_profiles` 본인 행.
class MentorOwnProfile {
  const MentorOwnProfile({
    required this.userId,
    this.universityName,
    this.departmentName,
    this.highSchoolName,
    this.teachingSubjects = const <String>[],
    this.introLine,
    this.bio,
    this.answerStyle,
    this.profileImageUrl,
    this.isOpenForSubscriptions = true,
    this.verificationStatus,
    this.activityStatus,
    this.pauseUntil,
  });

  final String userId;
  final String? universityName;
  final String? departmentName;
  final String? highSchoolName;

  /// DB 원본 값(정본 코드·라벨 혼재 가능). 편집은 정본 코드로 정규화해 보낸다.
  final List<String> teachingSubjects;
  final String? introLine;
  final String? bio;
  final String? answerStyle;
  final String? profileImageUrl;
  final bool isOpenForSubscriptions;
  final String? verificationStatus;
  final String? activityStatus;
  final DateTime? pauseUntil;

  bool get isApproved {
    switch (verificationStatus?.trim().toLowerCase()) {
      case 'approved':
      case 'verified':
      case 'active':
        return true;
      default:
        return false;
    }
  }

  factory MentorOwnProfile.fromMap(Map<String, dynamic> map) {
    final Object? subjects = map['teaching_subjects'];
    return MentorOwnProfile(
      userId: map['user_id'] as String,
      universityName: _str(map['university_name']),
      departmentName: _str(map['department_name']),
      highSchoolName: _str(map['high_school_name']),
      teachingSubjects: subjects is List
          ? subjects
              .map((Object? e) => e?.toString().trim() ?? '')
              .where((String s) => s.isNotEmpty)
              .toList()
          : const <String>[],
      introLine: _str(map['intro_line']),
      bio: _str(map['bio']),
      answerStyle: _str(map['answer_style']),
      profileImageUrl: _str(map['profile_image_url']),
      // ★ 행 값 그대로 — null 이면 서버 기본(true)과 같은 의미로 본다.
      isOpenForSubscriptions: map['is_open_for_subscriptions'] != false,
      verificationStatus: _str(map['verification_status']),
      activityStatus: _str(map['activity_status']),
      pauseUntil: _time(map['pause_until']),
    );
  }

  MentorOwnProfile copyWith({
    String? universityName,
    String? departmentName,
    String? highSchoolName,
    List<String>? teachingSubjects,
    String? introLine,
    String? bio,
    String? answerStyle,
    String? profileImageUrl,
    bool? isOpenForSubscriptions,
  }) {
    return MentorOwnProfile(
      userId: userId,
      universityName: universityName ?? this.universityName,
      departmentName: departmentName ?? this.departmentName,
      highSchoolName: highSchoolName ?? this.highSchoolName,
      teachingSubjects: teachingSubjects ?? this.teachingSubjects,
      introLine: introLine ?? this.introLine,
      bio: bio ?? this.bio,
      answerStyle: answerStyle ?? this.answerStyle,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isOpenForSubscriptions:
          isOpenForSubscriptions ?? this.isOpenForSubscriptions,
      verificationStatus: verificationStatus,
      activityStatus: activityStatus,
      pauseUntil: pauseUntil,
    );
  }
}

/// F7 전면 교체 입력(9필드 그대로). 서버가 allowlist 밖 컬럼을 건드리지 않는다.
class MentorProfileUpdate {
  const MentorProfileUpdate({
    required this.universityName,
    required this.departmentName,
    this.highSchoolName,
    required this.teachingSubjects,
    this.introLine,
    this.bio,
    this.answerStyle,
    this.profileImageUrl,
    required this.isOpenForSubscriptions,
  });

  final String universityName;
  final String departmentName;
  final String? highSchoolName;
  final List<String> teachingSubjects;
  final String? introLine;
  final String? bio;
  final String? answerStyle;
  final String? profileImageUrl;
  final bool isOpenForSubscriptions;

  Map<String, dynamic> toParams() => <String, dynamic>{
        'p_university_name': universityName,
        'p_department_name': departmentName,
        'p_high_school_name': highSchoolName,
        'p_teaching_subjects': teachingSubjects,
        'p_intro_line': introLine,
        'p_bio': bio,
        'p_answer_style': answerStyle,
        'p_profile_image_url': profileImageUrl,
        'p_is_open_for_subscriptions': isOpenForSubscriptions,
      };
}
