import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/scan/picked_image.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'api_web_v1_envelope.dart';
import 'document_validation.dart';
import 'mentor_console_models.dart';

/// 학력 인증·학적 변경 서류 버킷(비공개, 첫 세그먼트 = 본인 uid 정책).
/// ★ 매니페스트(outbound_api_manifest_test) 상수 — 리터럴 from 금지.
const String kStudentIdImagesBucket = 'student-id-images';

/// 멘토 아바타 버킷(public 읽기, 본인 폴더 쓰기 — 097).
const String kProfileAvatarsBucket = 'profile-avatars';

/// 멘토 콘솔(A-4a) 포트 — 화면은 이 추상에만 의존한다(테스트·골든은 fake 주입).
///
/// 쓰기 경로 정본(판정표 `docs/renewal/a4a-triage-2026-09-05.md`):
/// - 정산 계좌: `api_web_v1.mentor_payout_account_update_self` (F13)
/// - 요금제: `api_web_v1.mentor_plan_prices_set_self` (F8, 밴드 DB 강제)
/// - 개별질문 단가: `public.set_individual_question_price`
/// - 정산 조회: `public.mentor_settlement_summary` · `mentor_settlement_lines`
/// - 학력 인증·학적 변경: 버킷 업로드 + 본인 pending 행 직접 INSERT(RLS)
/// - 프로필 9필드·구독 열림: `api_web_v1.mentor_profile_update_self` (F7)
/// - 아바타: 버킷 `profile-avatars` 본인 폴더 업로드 → F7 `p_profile_image_url`
abstract class MentorConsolePort {
  Future<PayoutAccountInfo> loadPayoutAccount();
  Future<PayoutAccountInfo> updatePayoutAccount({
    required String bankName,
    required String accountNumber,
  });

  /// 예금주 표시용 본인 실명(`users.full_name`). 없으면 null.
  Future<String?> loadFullName();

  Future<MentorPlanPrices> loadPlanPrices();
  Future<void> setPlanPrices({
    required int limitedWon,
    required int standardWon,
    required int premiumWon,
  });

  Future<int?> loadIndividualQuestionPriceWon();
  Future<void> setIndividualQuestionPriceWon(int won);

  Future<SettlementSummary> loadSettlementSummary({DateTime? month});
  Future<List<SettlementLine>> loadSettlementLines({
    DateTime? from,
    DateTime? to,
  });

  Future<List<SchoolVerificationRecord>> loadSchoolVerifications();
  Future<void> submitSchoolVerification(VerifiedMentorDocument document);

  Future<List<AcademicRecordChangeRecord>> loadAcademicRecordChanges();
  Future<void> submitAcademicRecordChange({
    required String requestedUniversityName,
    String? changeReason,
    required VerifiedMentorDocument document,
  });

  Future<MentorOwnProfile> loadOwnProfile();
  Future<void> updateOwnProfile(MentorProfileUpdate update);

  /// A-4b ④ 활동 상태(`api_app_v1.mentor_activity_set`) — 일시중지/복귀/종료 예정.
  Future<MentorActivityResult> setActivityStatus(MentorActivityRequest request);

  /// A-4b ⑦ 학생증 사후 제출 — 버킷 업로드(user JWT·RLS) 후
  /// `api_app_v1.mentor_student_id_document_set_self` 로 반영.
  Future<StudentIdDocumentResult> submitStudentIdDocument(
      VerifiedMentorDocument document);

  /// 아바타 업로드 → F7 에 넘길 public URL.
  Future<String> uploadAvatar(PickedImage image);
}

/// Supabase 구현. 세션 클라이언트(authenticated)만 쓴다 — service_role 0.
class SupabaseMentorConsoleRepository implements MentorConsolePort {
  const SupabaseMentorConsoleRepository();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw const AppError('로그인이 필요해요.');
    return id;
  }

  // ── 정산 계좌 (F13) ─────────────────────────────────────────────

  @override
  Future<PayoutAccountInfo> loadPayoutAccount() async {
    final Map<String, dynamic>? row = await _client
        .from('mentor_profiles')
        .select('payout_bank_name, payout_account_number')
        .eq('user_id', _uid)
        .maybeSingle();
    return PayoutAccountInfo.fromRow(row);
  }

  @override
  Future<PayoutAccountInfo> updatePayoutAccount({
    required String bankName,
    required String accountNumber,
  }) async {
    final Object? data = await _client.schema('api_web_v1').rpc(
      'mentor_payout_account_update_self',
      params: <String, dynamic>{
        'p_bank_name': bankName,
        'p_account_number': accountNumber,
      },
    );
    final ApiEnvelope env =
        ApiEnvelope.parse(data).requireOk(payoutAccountMessageForCode);
    return PayoutAccountInfo(
      bankName: bankName,
      accountMasked: env.stringField('account_masked') ??
          maskPayoutAccount(accountNumber),
    );
  }

  @override
  Future<String?> loadFullName() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('users')
          .select('full_name')
          .eq('id', _uid)
          .maybeSingle();
      final Object? v = row?['full_name'];
      final String? name = v is String ? v.trim() : null;
      return (name == null || name.isEmpty) ? null : name;
    } catch (_) {
      return null; // 표시 보강 실패는 등록 흐름을 막지 않는다.
    }
  }

  // ── 요금제 (F8) · 개별질문 단가 ─────────────────────────────────

  @override
  Future<MentorPlanPrices> loadPlanPrices() async {
    final List<Map<String, dynamic>> rows = await _client
        .from('mentor_plans')
        .select('plan_tier, amount_cents')
        .eq('mentor_id', _uid);
    return MentorPlanPrices.fromRows(rows);
  }

  @override
  Future<void> setPlanPrices({
    required int limitedWon,
    required int standardWon,
    required int premiumWon,
  }) async {
    final Object? data = await _client.schema('api_web_v1').rpc(
      'mentor_plan_prices_set_self',
      params: <String, dynamic>{
        'p_limited_cash_krw': limitedWon,
        'p_standard_cash_krw': standardWon,
        'p_premium_cash_krw': premiumWon,
      },
    );
    ApiEnvelope.parse(data).requireOk(planPricesMessageForCode);
  }

  @override
  Future<int?> loadIndividualQuestionPriceWon() async {
    final Map<String, dynamic>? row = await _client
        .from('mentor_individual_question_pricing')
        .select('amount_cents')
        .eq('mentor_id', _uid)
        .maybeSingle();
    final Object? v = row?['amount_cents'];
    if (v is int) return v ~/ 100;
    if (v is num) return v.toInt() ~/ 100;
    return null;
  }

  @override
  Future<void> setIndividualQuestionPriceWon(int won) async {
    try {
      // 094: SETOF 반환(봉투 아님) — 예외가 없으면 성공.
      await _client.rpc(
        'set_individual_question_price',
        params: <String, dynamic>{'p_amount_cents': won * 100},
      );
    } on PostgrestException catch (e) {
      throw AppError(individualQuestionPriceMessage(e), cause: e);
    }
  }

  // ── 정산 조회 ───────────────────────────────────────────────────

  @override
  Future<SettlementSummary> loadSettlementSummary({DateTime? month}) async {
    final Object? data = await _client.rpc(
      'mentor_settlement_summary',
      params: <String, dynamic>{
        'p_month': month == null ? null : _monthParam(month),
      },
    );
    if (data is! Map) {
      throw const AppError('정산 요약을 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return SettlementSummary.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<List<SettlementLine>> loadSettlementLines({
    DateTime? from,
    DateTime? to,
  }) async {
    final Object? data = await _client.rpc(
      'mentor_settlement_lines',
      params: <String, dynamic>{
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      },
    );
    if (data is! List) {
      throw const AppError('정산 내역을 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return <SettlementLine>[
      for (final Object? row in data)
        if (row is Map) SettlementLine.fromMap(Map<String, dynamic>.from(row)),
    ];
  }

  static String _monthParam(DateTime month) {
    final String mm = month.month.toString().padLeft(2, '0');
    return '${month.year}-$mm-01';
  }

  // ── 학력 인증 · 학적 변경 (버킷 + 직접 INSERT) ───────────────────

  @override
  Future<List<SchoolVerificationRecord>> loadSchoolVerifications() async {
    final List<Map<String, dynamic>> rows = await _client
        .from('mentor_school_verifications')
        .select()
        .eq('mentor_id', _uid)
        .order('created_at', ascending: false);
    return rows.map(SchoolVerificationRecord.fromMap).toList();
  }

  @override
  Future<void> submitSchoolVerification(VerifiedMentorDocument document) async {
    final String uid = _uid;
    final String path =
        '$uid/school-verifications/${_documentFileName(document)}';
    await _uploadDocument(path, document);
    try {
      await _client.from('mentor_school_verifications').insert(<String, dynamic>{
        'mentor_id': uid,
        'status': 'pending',
        'document_storage_ref': '$kStudentIdImagesBucket/$path',
      });
    } catch (e) {
      await _compensateDocument(path);
      throw AppError('서류를 제출하지 못했어요. 잠시 후 다시 시도해 주세요.', cause: e);
    }
  }

  @override
  Future<List<AcademicRecordChangeRecord>> loadAcademicRecordChanges() async {
    final List<Map<String, dynamic>> rows = await _client
        .from('mentor_academic_record_change_requests')
        .select()
        .eq('mentor_id', _uid)
        .order('created_at', ascending: false);
    return rows.map(AcademicRecordChangeRecord.fromMap).toList();
  }

  @override
  Future<void> submitAcademicRecordChange({
    required String requestedUniversityName,
    String? changeReason,
    required VerifiedMentorDocument document,
  }) async {
    final String uid = _uid;
    final String path =
        '$uid/academic-record-changes/${_documentFileName(document)}';
    await _uploadDocument(path, document);
    try {
      await _client
          .from('mentor_academic_record_change_requests')
          .insert(<String, dynamic>{
        'mentor_id': uid,
        'status': 'pending',
        'requested_university_name': requestedUniversityName,
        'change_reason': changeReason,
        'document_storage_ref': '$kStudentIdImagesBucket/$path',
      });
    } catch (e) {
      await _compensateDocument(path);
      throw AppError('학적 변경 요청을 제출하지 못했어요. 잠시 후 다시 시도해 주세요.',
          cause: e);
    }
  }

  Future<void> _uploadDocument(
    String path,
    VerifiedMentorDocument document,
  ) async {
    try {
      await _client.storage.from(kStudentIdImagesBucket).uploadBinary(
            path,
            document.bytes,
            fileOptions: FileOptions(
              contentType: document.mimeType,
              cacheControl: '3600',
              upsert: false,
            ),
          );
    } catch (e) {
      throw AppError('서류 업로드에 실패했어요. 잠시 후 다시 시도해 주세요.', cause: e);
    }
  }

  /// 행 등록 실패 시 방금 올린 객체를 지운다(웹 액션과 동일한 보상 삭제). 실패해도
  /// 원래 오류를 덮지 않는다 — 본인 폴더 객체라 다음 제출에 영향이 없다.
  Future<void> _compensateDocument(String path) async {
    try {
      await _client.storage.from(kStudentIdImagesBucket).remove(<String>[path]);
    } catch (_) {
      // best-effort.
    }
  }

  static String _documentFileName(VerifiedMentorDocument document) {
    final int ts = DateTime.now().toUtc().millisecondsSinceEpoch;
    final Random rand = Random.secure();
    final String token = List<String>.generate(
      12,
      (_) => rand.nextInt(16).toRadixString(16),
    ).join();
    return '$ts-$token.${document.extension}';
  }

  // ── 본인 프로필 (F7) · 아바타 ────────────────────────────────────

  @override
  Future<MentorOwnProfile> loadOwnProfile() async {
    final Map<String, dynamic>? row = await _client
        .from('mentor_profiles')
        .select(
          'user_id, university_name, department_name, high_school_name, '
          'teaching_subjects, intro_line, bio, answer_style, profile_image_url, '
          'is_open_for_subscriptions, verification_status, activity_status, '
          'pause_until, pause_reason, last_pause_at, termination_effective_at, '
          'student_id_image_url',
        )
        .eq('user_id', _uid)
        .maybeSingle();
    if (row == null) throw const AppError('멘토 프로필을 찾을 수 없어요.');
    return MentorOwnProfile.fromMap(row);
  }

  @override
  Future<void> updateOwnProfile(MentorProfileUpdate update) async {
    final Object? data = await _client
        .schema('api_web_v1')
        .rpc('mentor_profile_update_self', params: update.toParams());
    ApiEnvelope.parse(data).requireOk(mentorProfileMessageForCode);
  }

  @override
  Future<MentorActivityResult> setActivityStatus(
      MentorActivityRequest request) async {
    final Object? data = await _client
        .schema('api_app_v1')
        .rpc('mentor_activity_set', params: request.toParams());
    final ApiEnvelope env =
        ApiEnvelope.parse(data).requireOk(activityMessageForCode);
    return MentorActivityResult.fromBody(env.body);
  }

  @override
  Future<StudentIdDocumentResult> submitStudentIdDocument(
      VerifiedMentorDocument document) async {
    final String uid = _uid;
    // 첫 세그먼트 = uid(버킷 RLS `student_id_images_insert_own` · RPC 소유 검증).
    final String path = '$uid/student-id/${_documentFileName(document)}';
    await _uploadDocument(path, document);
    try {
      final Object? data = await _client.schema('api_app_v1').rpc(
        'mentor_student_id_document_set_self',
        params: <String, dynamic>{'p_object_path': path},
      );
      final ApiEnvelope env =
          ApiEnvelope.parse(data).requireOk(studentIdMessageForCode);
      return StudentIdDocumentResult.fromBody(env.body);
    } on AppError {
      await _compensateDocument(path);
      rethrow;
    } catch (e) {
      await _compensateDocument(path);
      throw AppError('학생증을 제출하지 못했어요. 잠시 후 다시 시도해 주세요.', cause: e);
    }
  }

  @override
  Future<String> uploadAvatar(PickedImage image) async {
    final String uid = _uid;
    final String mime = image.mimeType.toLowerCase();
    final String ext = mime == 'image/png'
        ? 'png'
        : mime == 'image/webp'
            ? 'webp'
            : 'jpg';
    final int ts = DateTime.now().toUtc().millisecondsSinceEpoch;
    final String path = '$uid/$ts-${Random.secure().nextInt(1 << 30)}.$ext';
    try {
      await _client.storage.from(kProfileAvatarsBucket).uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(
              contentType: mime,
              cacheControl: '3600',
              upsert: false,
            ),
          );
    } catch (e) {
      throw AppError('프로필 사진 업로드에 실패했어요. 잠시 후 다시 시도해 주세요.',
          cause: e);
    }
    return _client.storage.from(kProfileAvatarsBucket).getPublicUrl(path);
  }
}

// ── 오류 코드 → 사용자 문구 (RPC별 · 공통은 apiWebV1CommonMessage) ───

String payoutAccountMessageForCode(String code, Map<String, dynamic> body) {
  switch (code) {
    case 'PAYOUT_BANK_NAME_INVALID':
      return '지원하지 않는 은행이에요. 목록에서 은행을 선택해 주세요.';
    case 'PAYOUT_ACCOUNT_NUMBER_INVALID':
      return '계좌번호는 숫자 8~24자리로 입력해 주세요.';
  }
  return apiWebV1CommonMessage(code) ?? '계좌 정보를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

/// 활동 상태(A-4b ④) 코드 → 문구(웹 `mentorActivityService` 문장과 같은 뜻).
String activityMessageForCode(String code, Map<String, dynamic> body) {
  switch (code) {
    case 'ACTIVITY_STATE_INVALID':
      return '지금 상태에서는 바꿀 수 없어요. 화면을 새로고침해 주세요.';
    case 'ACTIVITY_STATUS_INVALID':
      return '요청 값이 올바르지 않아요. 다시 시도해 주세요.';
    case 'PAUSE_UNTIL_REQUIRED':
    case 'PAUSE_UNTIL_INVALID':
      return '복귀 날짜를 다시 확인해 주세요.';
    case 'PAUSE_TOO_LONG':
      final Object? max = body['max_days'];
      return '일시중지는 최대 ${max is num ? max.toInt() : 7}일까지예요.';
    case 'PAUSE_REASON_INVALID':
      return '휴식 사유를 선택해 주세요.';
    case 'REST_FREQUENCY_LIMIT':
      final Object? next = body['next_available_at'];
      final DateTime? at =
          next is String ? DateTime.tryParse(next)?.toLocal() : null;
      return at == null
          ? '일반 휴식은 6개월에 한 번이에요. 질병 등 사유로는 관리자 확인 후 쉴 수 있어요.'
          : '일반 휴식은 6개월에 한 번이에요. ${at.month}월 ${at.day}일 이후에 다시 신청할 수 있어요.';
    case 'TERMINATION_DATE_TOO_FAR':
      return '종료 예정일은 최대 90일 뒤까지 정할 수 있어요.';
  }
  return apiWebV1CommonMessage(code) ?? '활동 상태를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.';
}

/// 학생증 사후 제출(A-4b ⑦) 코드 → 문구.
String studentIdMessageForCode(String code, Map<String, dynamic> body) {
  switch (code) {
    case 'STORAGE_FILE_TYPE_INVALID':
      return 'JPG, PNG, PDF 형식의 학생증만 올릴 수 있어요.';
    case 'STORAGE_PATH_REQUIRED':
    case 'STORAGE_PATH_INVALID':
    case 'STORAGE_OBJECT_NOT_OWNED':
      return '업로드한 파일을 확인하지 못했어요. 다시 올려 주세요.';
  }
  return apiWebV1CommonMessage(code) ?? '학생증을 제출하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

String planPricesMessageForCode(String code, Map<String, dynamic> body) {
  switch (code) {
    case 'PLAN_PRICE_OUT_OF_BAND':
      final Object? tier = body['tier'];
      final Object? min = body['min_cash_krw'];
      final Object? max = body['max_cash_krw'];
      final String label = tier == 'limited'
          ? '라이트'
          : tier == 'standard'
              ? '스탠다드'
              : tier == 'premium'
                  ? '프리미엄'
                  : '구독';
      if (min is num && max is num) {
        return '$label 요금은 ${_won(min.toInt())}~${_won(max.toInt())} 사이로 적어 주세요.';
      }
      return '$label 요금이 허용 범위를 벗어났어요. 안내된 범위에서 설정해 주세요.';
    case 'PLAN_PRICE_INVALID':
      return '요금은 1원 이상 숫자로 입력해 주세요.';
  }
  return apiWebV1CommonMessage(code) ?? '요금제를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

String mentorProfileMessageForCode(String code, Map<String, dynamic> body) {
  switch (code) {
    case 'UNIVERSITY_NAME_REQUIRED':
      return '대학명을 입력해 주세요.';
    case 'DEPARTMENT_NAME_REQUIRED':
      return '학과명을 입력해 주세요.';
    case 'PROFILE_IMAGE_REF_INVALID':
      return '프로필 사진 참조가 올바르지 않아요. 사진을 다시 올려 주세요.';
  }
  return apiWebV1CommonMessage(code) ?? '프로필을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

/// `set_individual_question_price` 는 `raise exception 'CODE…'` 스타일.
String individualQuestionPriceMessage(PostgrestException e) {
  final String m = e.message.trim();
  if (m.startsWith('AUTH_REQUIRED')) return '로그인이 필요해요.';
  if (m.startsWith('INVALID_INPUT')) return '단가는 1원 이상 숫자로 입력해 주세요.';
  return '개별질문 단가를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

String _won(int v) {
  final String s = v.toString();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b원';
}
