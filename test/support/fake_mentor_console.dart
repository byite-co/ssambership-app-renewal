import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/features/mentor_console/data/document_validation.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// A-4a 멘토 콘솔 포트 fake — 네트워크 0. 필요한 값만 채우고, 채우지 않은 조회는
/// 기본값(미등록·빈 목록)을 돌려준다. 쓰기 호출은 기록되며 [failWith] 로 실패를
/// 흉내 낼 수 있다.
class FakeMentorConsole implements MentorConsolePort {
  FakeMentorConsole({
    this.payoutAccount = const PayoutAccountInfo(),
    this.fullName,
    this.planPrices = const MentorPlanPrices(),
    this.iqPriceWon,
    this.summary,
    this.lines = const <SettlementLine>[],
    this.schoolVerifications = const <SchoolVerificationRecord>[],
    this.academicChanges = const <AcademicRecordChangeRecord>[],
    this.profile,
    this.avatarUrl = 'https://example.test/profile-avatars/m1/a.jpg',
    this.failWith,
    this.loadFailure,
  });

  PayoutAccountInfo payoutAccount;
  String? fullName;
  MentorPlanPrices planPrices;
  int? iqPriceWon;
  SettlementSummary? summary;
  List<SettlementLine> lines;
  List<SchoolVerificationRecord> schoolVerifications;
  List<AcademicRecordChangeRecord> academicChanges;
  MentorOwnProfile? profile;
  String avatarUrl;

  /// A-4b ④⑦: 활동 상태 결과·학생증 결과(쓰기 호출은 [calls] 에 기록).
  MentorActivityResult? activityResult;
  StudentIdDocumentResult studentIdResult = const StudentIdDocumentResult(
      storedRef: 'student-id-images/m1/student-id/x.jpg');

  /// 쓰기 호출을 이 오류로 실패시킨다(null 이면 성공).
  Object? failWith;

  /// 조회 호출을 이 오류로 실패시킨다(null 이면 성공).
  Object? loadFailure;

  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  void _guardLoad() {
    final Object? e = loadFailure;
    if (e != null) throw e;
  }

  void _guardWrite(String name, Map<String, Object?> args) {
    calls.add(<String, Object?>{'name': name, ...args});
    final Object? e = failWith;
    if (e != null) throw e;
  }

  @override
  Future<PayoutAccountInfo> loadPayoutAccount() async {
    _guardLoad();
    return payoutAccount;
  }

  @override
  Future<PayoutAccountInfo> updatePayoutAccount({
    required String bankName,
    required String accountNumber,
  }) async {
    _guardWrite('updatePayoutAccount',
        <String, Object?>{'bankName': bankName, 'accountNumber': accountNumber});
    payoutAccount = PayoutAccountInfo(
      bankName: bankName,
      accountMasked: maskPayoutAccount(accountNumber),
    );
    return payoutAccount;
  }

  @override
  Future<String?> loadFullName() async => fullName;

  @override
  Future<MentorPlanPrices> loadPlanPrices() async {
    _guardLoad();
    return planPrices;
  }

  @override
  Future<void> setPlanPrices({
    required int limitedWon,
    required int standardWon,
    required int premiumWon,
  }) async {
    _guardWrite('setPlanPrices', <String, Object?>{
      'limited': limitedWon,
      'standard': standardWon,
      'premium': premiumWon,
    });
    planPrices = MentorPlanPrices(
      limitedWon: limitedWon,
      standardWon: standardWon,
      premiumWon: premiumWon,
    );
  }

  @override
  Future<int?> loadIndividualQuestionPriceWon() async {
    _guardLoad();
    return iqPriceWon;
  }

  @override
  Future<void> setIndividualQuestionPriceWon(int won) async {
    _guardWrite('setIndividualQuestionPriceWon', <String, Object?>{'won': won});
    iqPriceWon = won;
  }

  @override
  Future<SettlementSummary> loadSettlementSummary({DateTime? month}) async {
    _guardLoad();
    final SettlementSummary? s = summary;
    if (s == null) throw const AppError('정산 요약 fixture 없음');
    return s;
  }

  @override
  Future<List<SettlementLine>> loadSettlementLines({
    DateTime? from,
    DateTime? to,
  }) async {
    _guardLoad();
    return lines;
  }

  @override
  Future<List<SchoolVerificationRecord>> loadSchoolVerifications() async {
    _guardLoad();
    return schoolVerifications;
  }

  @override
  Future<void> submitSchoolVerification(VerifiedMentorDocument document) async {
    _guardWrite('submitSchoolVerification', <String, Object?>{
      'kind': document.kind.name,
      'bytes': document.bytes.length,
    });
    schoolVerifications = <SchoolVerificationRecord>[
      SchoolVerificationRecord(
        id: 'new',
        status: ReviewStatus.pending,
        documentStorageRef: 'student-id-images/m1/school-verifications/x.jpg',
        createdAt: DateTime(2026, 7, 1),
      ),
      ...schoolVerifications,
    ];
  }

  @override
  Future<List<AcademicRecordChangeRecord>> loadAcademicRecordChanges() async {
    _guardLoad();
    return academicChanges;
  }

  @override
  Future<void> submitAcademicRecordChange({
    required String requestedUniversityName,
    String? changeReason,
    required VerifiedMentorDocument document,
  }) async {
    _guardWrite('submitAcademicRecordChange', <String, Object?>{
      'university': requestedUniversityName,
      'reason': changeReason,
      'kind': document.kind.name,
    });
    academicChanges = <AcademicRecordChangeRecord>[
      AcademicRecordChangeRecord(
        id: 'new',
        status: ReviewStatus.pending,
        requestedUniversityName: requestedUniversityName,
        changeReason: changeReason,
        createdAt: DateTime(2026, 7, 1),
      ),
      ...academicChanges,
    ];
  }

  @override
  Future<MentorOwnProfile> loadOwnProfile() async {
    _guardLoad();
    final MentorOwnProfile? p = profile;
    if (p == null) throw const AppError('프로필 fixture 없음');
    return p;
  }

  @override
  Future<void> updateOwnProfile(MentorProfileUpdate update) async {
    _guardWrite('updateOwnProfile', update.toParams());
    profile = (profile ??
            const MentorOwnProfile(userId: 'm1'))
        .copyWith(
      universityName: update.universityName,
      departmentName: update.departmentName,
      highSchoolName: update.highSchoolName,
      teachingSubjects: update.teachingSubjects,
      introLine: update.introLine,
      bio: update.bio,
      answerStyle: update.answerStyle,
      profileImageUrl: update.profileImageUrl,
      isOpenForSubscriptions: update.isOpenForSubscriptions,
    );
  }

  @override
  Future<MentorActivityResult> setActivityStatus(
      MentorActivityRequest request) async {
    _guardWrite('setActivityStatus', <String, Object?>{
      'status': request.status,
      'pauseUntil': request.pauseUntil,
      'terminationEffectiveAt': request.terminationEffectiveAt,
      'reason': request.reason,
    });
    final MentorActivityResult r = activityResult ??
        MentorActivityResult(
          activityStatus: request.status,
          pauseUntil: request.pauseUntil,
          terminationEffectiveAt: request.terminationEffectiveAt,
        );
    final MentorOwnProfile? p = profile;
    if (p != null) {
      profile = MentorOwnProfile(
        userId: p.userId,
        universityName: p.universityName,
        departmentName: p.departmentName,
        teachingSubjects: p.teachingSubjects,
        verificationStatus: p.verificationStatus,
        activityStatus: r.activityStatus,
        pauseUntil: r.pauseUntil,
        terminationEffectiveAt: r.terminationEffectiveAt,
        studentIdImageUrl: p.studentIdImageUrl,
      );
    }
    return r;
  }

  @override
  Future<StudentIdDocumentResult> submitStudentIdDocument(
      VerifiedMentorDocument document) async {
    _guardWrite('submitStudentIdDocument', <String, Object?>{
      'kind': document.kind.name,
      'bytes': document.bytes.length,
    });
    final MentorOwnProfile? p = profile;
    if (p != null) {
      profile = MentorOwnProfile(
        userId: p.userId,
        universityName: p.universityName,
        departmentName: p.departmentName,
        teachingSubjects: p.teachingSubjects,
        verificationStatus: p.verificationStatus,
        activityStatus: p.activityStatus,
        pauseUntil: p.pauseUntil,
        terminationEffectiveAt: p.terminationEffectiveAt,
        studentIdImageUrl: studentIdResult.storedRef,
      );
    }
    return studentIdResult;
  }

  @override
  Future<String> uploadAvatar(PickedImage image) async {
    _guardWrite('uploadAvatar', <String, Object?>{
      'fileName': image.fileName,
      'mimeType': image.mimeType,
    });
    return avatarUrl;
  }
}
