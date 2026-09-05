import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'iq_error_mapper.dart';
import 'models/individual_question_models.dart';

/// `iq_append_message` 성공 반환({ok, message_id, answered_transition}).
class IqAppendResult {
  const IqAppendResult({
    required this.messageId,
    required this.answeredTransition,
  });

  /// 생성된 메시지 행 id(화면 미노출 — dedup·재조회 대조용).
  final String messageId;

  /// true = 멘토 첫 메시지로 claimed/assigned → answered 전이가 함께 일어남.
  final bool answeredTransition;
}

/// 개별질문(IQ) 레포지토리 — 모든 변경은 SECURITY DEFINER 래퍼 RPC 로만.
///
/// 웹 마이그레이션 계약(091·092, authenticated 부여):
/// - 생성: `create_individual_question_as_student` (에스크로 홀드 포함)
/// - 수락: `claim_individual_question_as_mentor`
/// - 답변: `answer_individual_question` (메시지 insert + answered 전이 원자화)
/// - 대화: `iq_append_message` (양 당사자 — 학생 후속·멘토 추가 답글)
/// - 확정: `release_individual_question` (학생 → 멘토 정산)
/// - 취소: `refund_individual_question` (예치 캐시 반환)
/// 조회는 당사자 SELECT RLS(070) + 공개 대기 질문 위생 RPC 로 직접 읽는다.
/// ★ 첨부 행 insert 정책은 없으므로 앱은 첨부를 만들지 않는다(조회 전용).
class IndividualQuestionRepository {
  const IndividualQuestionRepository();

  static const String attachmentBucket = 'individual-question-attachments';

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  String get _uid {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const AppError('로그인이 필요해요.');
    }
    return uid;
  }

  // ---------------------------------------------------------------------
  // 조회
  // ---------------------------------------------------------------------

  /// 학생: 내가 만든 질문 목록(최신순).
  Future<List<IndividualQuestion>> listForStudent({int limit = 50}) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('individual_questions')
        .select()
        .eq('student_id', _uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(IndividualQuestion.fromMap).toList(growable: false);
  }

  /// 멘토: 나에게 지정됐거나 내가 수락한 질문 목록(최신순).
  Future<List<IndividualQuestion>> listForMentor({int limit = 50}) async {
    final String uid = _uid;
    final List<Map<String, dynamic>> rows = await _client
        .from('individual_questions')
        .select()
        .or('designated_mentor_id.eq.$uid,claimed_mentor_id.eq.$uid')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(IndividualQuestion.fromMap).toList(growable: false);
  }

  /// 멘토: 수락 대기 중인 공개형 질문(위생 RPC — 본문·학생 정보 없음).
  /// 승인 멘토가 아니면 빈 목록이 온다(RPC 내부 게이트).
  Future<List<OpenIndividualQuestion>> listOpenForMentor(
      {int limit = 50}) async {
    final dynamic res = await _client.rpc(
      'list_open_individual_questions_for_mentor',
      params: <String, dynamic>{'p_limit': limit},
    );
    final List<OpenIndividualQuestion> out = <OpenIndividualQuestion>[];
    if (res is List) {
      for (final Object? row in res) {
        if (row is Map<String, dynamic>) {
          out.add(OpenIndividualQuestion.fromMap(row));
        }
      }
    }
    return out;
  }

  /// 상세 1건(당사자 RLS). 없거나 권한 밖이면 null.
  Future<IndividualQuestion?> fetch(String questionId) async {
    final Map<String, dynamic>? row = await _client
        .from('individual_questions')
        .select()
        .eq('id', questionId)
        .maybeSingle();
    return row == null ? null : IndividualQuestion.fromMap(row);
  }

  /// 스레드 메시지(작성순).
  Future<List<IqMessage>> listMessages(String questionId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('individual_question_messages')
        .select()
        .eq('question_id', questionId)
        .order('created_at', ascending: true);
    return rows.map(IqMessage.fromMap).toList(growable: false);
  }

  /// 첨부 목록(조회 전용 — 표시용 서명 URL 은 IqAttachmentUrlResolver 가
  /// 캐시와 함께 담당한다).
  Future<List<IqAttachment>> listAttachments(String questionId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('individual_question_attachments')
        .select()
        .eq('question_id', questionId)
        .order('created_at', ascending: false);
    return rows.map(IqAttachment.fromMap).toList(growable: false);
  }

  /// 멘토 지정형 가격. 미설정이면 null.
  Future<IqPricing?> fetchMentorPricing(String mentorId) async {
    final Map<String, dynamic>? row = await _client
        .from('mentor_individual_question_pricing')
        .select()
        .eq('mentor_id', mentorId)
        .maybeSingle();
    return row == null ? null : IqPricing.fromMap(row);
  }

  /// 내 캐시 잔액(cents). 지갑 미생성이면 0. 표시·사전 안내용 —
  /// 실제 검증은 서버(RPC)가 한다(앱은 결제·차감 계산을 하지 않는다).
  Future<int> fetchWalletBalanceCents() async {
    // N5: 원테이블 직접 SELECT → 본인 한정 invoker 뷰(api_web_v1.my_wallet_v1).
    final Map<String, dynamic>? row = await _client
        .schema('api_web_v1')
        .from('my_wallet_v1')
        .select('balance_cents')
        .eq('user_id', _uid)
        .maybeSingle();
    final Object? v = row?['balance_cents'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  // ---------------------------------------------------------------------
  // 변경(래퍼 RPC — 본인 한정·상태 가드·에스크로는 전부 서버가 수행)
  // ---------------------------------------------------------------------

  /// 학생: 질문 생성 + 캐시 예치. direct 는 멘토 가격표에서 서버가 가격을 정하고,
  /// open 은 [amountCents] 를 보낸다. 성공 시 생성된 질문 행을 돌려준다.
  Future<IndividualQuestion> createAsStudent({
    required IndividualQuestionType type,
    required String title,
    required String body,
    int? amountCents,
    String? designatedMentorId,
    String? idempotencyKey,
  }) async {
    final dynamic res = await _client.rpc(
      'create_individual_question_as_student',
      params: <String, dynamic>{
        'p_question_type':
            type == IndividualQuestionType.open ? 'open' : 'direct',
        'p_title': title,
        'p_body': body,
        'p_amount_cents': amountCents,
        'p_designated_mentor_id': designatedMentorId,
        'p_idempotency_key': idempotencyKey,
      },
    );
    if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
      return IndividualQuestion.fromMap(res.first as Map<String, dynamic>);
    }
    throw const AppError('질문 생성 결과를 확인하지 못했어요.');
  }

  /// 멘토: 공개형 질문 수락(선착).
  Future<IqEscrowResult> claimAsMentor(String questionId) async {
    final dynamic res = await _client.rpc(
      'claim_individual_question_as_mentor',
      params: <String, dynamic>{'p_question_id': questionId},
    );
    return _escrowResult(res);
  }

  /// 양 당사자 공용 메시지 전송(`iq_append_message`) — 학생 후속 질문과 멘토
  /// 답변(첫 답변 포함 — answered 전이는 서버 봉투 answered_transition)이
  /// 모두 이 경로다. C20: 구 answer_individual_question 배선은 호출 0건이라
  /// 제거(서버 함수는 서버 레인 N6 정리 대상).
  ///
  /// 서버 계약(6): {ok, message_id, answered_transition}. 오류는
  /// raise exception 'CODE' — [mapIqError] 가 한글 문구로 변환한다.
  /// 성공 봉투는 strict 검증(fail-closed) — 계약 밖 응답을 성공으로 처리하지
  /// 않는다. 로컬 선반영 없음(화면은 성공 후 서버 재조회가 정본).
  Future<IqAppendResult> appendMessage(String questionId, String body) async {
    final dynamic res;
    try {
      res = await _client.rpc(
        'iq_append_message',
        params: <String, dynamic>{
          'p_question_id': questionId,
          'p_body': body,
        },
      );
    } catch (e) {
      throw mapIqError(e);
    }
    if (res is Map && res['ok'] == true && res['message_id'] is String) {
      final String id = (res['message_id'] as String).trim();
      if (id.isNotEmpty) {
        return IqAppendResult(
          messageId: id,
          answeredTransition: res['answered_transition'] == true,
        );
      }
    }
    throw const AppError('메시지 전송 결과를 확인하지 못했어요. 다시 시도해 주세요.');
  }

  /// 학생: 답변 확정 → 멘토 정산(release).
  Future<IqEscrowResult> release(String questionId) async {
    final dynamic res = await _client.rpc(
      'release_individual_question',
      params: <String, dynamic>{'p_question_id': questionId},
    );
    return _escrowResult(res);
  }

  /// 학생: 질문 취소 → 예치 캐시 환불.
  Future<IqEscrowResult> refund(String questionId) async {
    final dynamic res = await _client.rpc(
      'refund_individual_question',
      params: <String, dynamic>{'p_question_id': questionId},
    );
    return _escrowResult(res);
  }

  IqEscrowResult _escrowResult(dynamic res) {
    if (res is Map<String, dynamic>) return IqEscrowResult.fromMap(res);
    if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
      return IqEscrowResult.fromMap(res.first as Map<String, dynamic>);
    }
    throw const AppError('처리 결과를 확인하지 못했어요.');
  }
}
