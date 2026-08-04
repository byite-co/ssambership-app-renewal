// 멘토 찾기(공개·열람 전용) 도메인 모델.
//
// 데이터 출처(모두 공개 조회 가능한 소스 — 계약 수렴 후):
// - 목록/프로필: 뷰 `api_web_v1.mentor_directory_v1` (anon+authenticated SELECT).
//   행 존재 자체가 '활성·승인 멘토'라는 서버 보장이다. ★ full_name 컬럼은
//   뷰에 없다 — 표시명은 nickname, 비면 중립 '멘토'.
// - 요금제: 테이블 `mentor_plans` (is_active=true 만) — 가격은 '표시'만 한다.
//
// ★ 내부 id·딥링크·코드값은 화면에 노출하지 않는다(표시명/한글 라벨만 사용).
import '../format/mentor_price_format.dart';
import 'mentor_subject.dart';

DateTime? _parseTime(Object? v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

/// 멘토 공개 요금제 1건(가격 표시 전용 — 결제 트리거 없음).
class MentorPlan {
  const MentorPlan({
    required this.planTier,
    required this.amountCents,
    this.label,
    this.isActive = true,
  });

  final String planTier; // limited / standard / premium (화면 미노출)
  final int amountCents; // 예) 2990000 → 29,900원
  final String? label; // 멘토가 붙인 표기(예: '라이트'/'스탠다드'/'프리미엄'). 없으면 등급명 사용.
  final bool isActive;

  /// 원 단위 가격(amount_cents / 100).
  int get won => amountCents ~/ 100;

  /// 화면 표기명. 멘토가 붙인 라벨이 코드값과 다르면 그것을, 아니면 한글 등급명.
  String get displayLabel {
    final String l = label?.trim() ?? '';
    if (l.isNotEmpty && l != planTier) return l;
    return planTierLabel(planTier);
  }

  factory MentorPlan.fromMap(Map<String, dynamic> map) {
    return MentorPlan(
      planTier: (map['plan_tier'] as String?)?.trim() ?? '',
      amountCents: (map['amount_cents'] as num?)?.toInt() ?? 0,
      label: map['label'] as String?,
      // ★ 행 값 그대로 — 누락을 true 로 날조하지 않는다(true 는 명시값만).
      isActive: map['is_active'] == true,
    );
  }
}

/// 멘토 공개 프로필(학교/전공/과목/소개/인증 — 공개 필드만).
class MentorProfileInfo {
  const MentorProfileInfo({
    required this.userId,
    this.universityName,
    this.departmentName,
    this.teachingSubjects = const <String>[],
    this.introLine,
    this.verificationStatus,
    this.schoolVerified = false,
  });

  final String userId;
  final String? universityName;
  final String? departmentName;

  /// 지도 과목 **원본 값**(DB `teaching_subjects`). 정본 코드(`math`)·한글 라벨(`수학`)·
  /// 레거시 값이 혼재할 수 있다 → 화면 표시·필터·검색은 [MentorListItem.subjectViews]
  /// (canonical)로 처리하고, 이 raw 리스트를 화면에 직접 노출하지 않는다.
  final List<String> teachingSubjects;
  final String? introLine;
  final String? verificationStatus; // 'approved' 등
  final bool schoolVerified;

  /// 인증 배지 노출 여부(학교 인증 승인). 민감정보(학생증 등)는 다루지 않는다.
  bool get isVerified =>
      schoolVerified || (verificationStatus?.trim() == 'approved');

  /// '서울대학교 · 수학교육과' 형태. 둘 다 없으면 null.
  String? get schoolLine {
    final String u = universityName?.trim() ?? '';
    final String d = departmentName?.trim() ?? '';
    if (u.isEmpty && d.isEmpty) return null;
    if (u.isEmpty) return d;
    if (d.isEmpty) return u;
    return '$u · $d';
  }

  factory MentorProfileInfo.fromMap(Map<String, dynamic> map) {
    final Object? subjects = map['teaching_subjects'];
    return MentorProfileInfo(
      userId: map['user_id'] as String,
      universityName: map['university_name'] as String?,
      departmentName: map['department_name'] as String?,
      teachingSubjects: subjects is List
          ? subjects
              .map((Object? e) => e?.toString().trim() ?? '')
              .where((String s) => s.isNotEmpty)
              .toList()
          : const <String>[],
      introLine: map['intro_line'] as String?,
      verificationStatus: map['verification_status'] as String?,
      schoolVerified: (map['school_verified'] as bool?) ?? false,
    );
  }
}

/// 멘토 목록 1행(디렉터리 뷰 항목 + 활성 요금제).
class MentorListItem {
  const MentorListItem({
    required this.id,
    this.nickname,
    this.createdAt,
    this.profile,
    this.plans = const <MentorPlan>[],
    this.avgRating,
    this.reviewCount = 0,
  });

  final String id; // 내부용(화면 미노출). 상세 조회·구독 확인에만 사용.
  final String? nickname;
  final DateTime? createdAt;
  final MentorProfileInfo? profile;
  final List<MentorPlan> plans; // is_active=true 만

  /// 공개(visible) 리뷰 평균 평점(정렬 '별점높은순'용, 뷰 avg_rating). null = 리뷰 없음.
  final double? avgRating;

  /// 공개(visible) 리뷰 수(정렬 '리뷰많은순'용, 뷰 review_count). 0 = 없음.
  final int reviewCount;

  /// 표시명 — nickname(트림, 비어 있지 않음) 없으면 중립 '멘토'.
  /// ★ full_name 폴백은 계약 수렴으로 폐기됐다(뷰에 full_name 자체가 없다).
  String get displayName {
    final String n = nickname?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return '멘토';
  }

  /// 화면·필터·검색용 canonical 과목(순서 보존·중복 제거·빈 값 제외). 카드/상세는
  /// 여기서 [MentorSubject.label](한글)만 표시한다 — raw 코드는 화면에 새지 않는다.
  List<MentorSubject> get subjectViews =>
      canonicalizeSubjects(profile?.teachingSubjects ?? const <String>[]);

  bool get isVerified => profile?.isVerified ?? false;

  /// 검색 매칭용 텍스트(이름·학교·전공·과목).
  ///
  /// 과목은 raw(레거시·코드 검색 호환)와 canonical 한글 라벨을 모두 포함해 `수학`(라벨)·
  /// `math`(raw) 어느 쪽으로 검색해도 매칭된다. 대소문자 무시는 호출부에서 처리한다.
  String get searchHaystack {
    final StringBuffer b = StringBuffer(displayName);
    final MentorProfileInfo? p = profile;
    if (p != null) {
      if (p.universityName != null) b.write(' ${p.universityName}');
      if (p.departmentName != null) b.write(' ${p.departmentName}');
      for (final String raw in p.teachingSubjects) {
        b.write(' $raw'); // raw(코드/레거시) 검색 호환
      }
      for (final MentorSubject s in subjectViews) {
        b.write(' ${s.label}'); // 한글 라벨 검색
      }
    }
    return b.toString();
  }

  MentorListItem copyWith({
    MentorProfileInfo? profile,
    List<MentorPlan>? plans,
    double? avgRating,
    int? reviewCount,
  }) {
    return MentorListItem(
      id: id,
      nickname: nickname,
      createdAt: createdAt,
      profile: profile ?? this.profile,
      plans: plans ?? this.plans,
      avgRating: avgRating ?? this.avgRating,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }

  /// `api_web_v1.mentor_directory_v1` 행 → 목록 항목.
  ///
  /// 프로필 필드(학교·과목·소개·인증)도 같은 행에 실려 온다. 행 존재 자체가
  /// 서버가 보장하는 '활성·승인 멘토'이므로 verificationStatus 는 계약상
  /// 'approved' 로 둔다(날조가 아니라 뷰 정의의 사실 기술).
  /// ★ full_name 키는 읽지 않는다 — 뷰에 존재하지 않는 계약이다.
  factory MentorListItem.fromDirectoryViewMap(Map<String, dynamic> map) {
    final Object? subjects = map['teaching_subjects'];
    final String id = map['mentor_id'] as String;
    return MentorListItem(
      id: id,
      nickname: map['nickname'] as String?,
      createdAt: _parseTime(map['created_at']),
      profile: MentorProfileInfo(
        userId: id,
        universityName: map['university_name'] as String?,
        departmentName: map['department_name'] as String?,
        teachingSubjects: subjects is List
            ? subjects
                .map((Object? e) => e?.toString().trim() ?? '')
                .where((String s) => s.isNotEmpty)
                .toList()
            : const <String>[],
        introLine: map['intro_line'] as String?,
        // 행 존재 = 활성·승인(뷰 계약) — 기존 배지 의미를 유지한다.
        verificationStatus: 'approved',
        schoolVerified: (map['school_verified'] as bool?) ?? false,
      ),
      avgRating: (map['avg_rating'] as num?)?.toDouble(),
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 상세 화면 추가 정보(목록에서 못 가져오는 것: 활동 통계·내 구독 여부).
class MentorDetailExtras {
  const MentorDetailExtras({
    this.avgResponseHours,
    this.avgRating,
    this.reviewCount = 0,
    this.alreadySubscribed = false,
  });

  /// 평균 답변시간(시간). null = 통계 없음.
  final num? avgResponseHours;

  /// 공개(visible) 리뷰 평균 평점(1~5). null = 리뷰 없음(평점 미표시).
  final double? avgRating;

  /// 공개(visible) 리뷰 수. 0 = 없음.
  final int reviewCount;

  /// 현재 로그인 사용자가 이 멘토를 활성 구독 중인지(게스트는 항상 false).
  final bool alreadySubscribed;

  /// 평점 표시 라벨('4.5 · 리뷰 2개'). 공개 리뷰가 있을 때만, 없으면 null(날조 금지).
  String? get ratingLabel {
    final double? r = avgRating;
    if (reviewCount <= 0 || r == null) return null;
    return '${r.toStringAsFixed(1)}  ·  리뷰 $reviewCount개';
  }

  /// 평균 응답시간 라벨. 값이 없으면 null.
  String? get responseLabel {
    final num? h = avgResponseHours;
    if (h == null) return null;
    return h < 1 ? '평균 답변 1시간 이내' : '평균 답변 약 ${h.round()}시간';
  }

  /// 표시할 활동 정보(평점·응답시간)가 하나도 없는지 → 빈 상태 안내로 대체.
  bool get hasNoActivity => ratingLabel == null && responseLabel == null;
}
