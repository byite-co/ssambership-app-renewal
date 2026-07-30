import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import '../../question_room/data/qna_error_mapper.dart';

/// 무료 질문 진입(세션1 §3) — 자격 '조회'·방 확보(F2)·생성(F3)만 담당한다.
///
/// S2-2 M17 전환(앱 계약 v1.1 §3.3·§4):
/// - 방 확보: `api_app_v1.ensure_free_question_room(p_mentor_id)` (F2) —
///   학생 ID 는 보내지 않는다(서버가 auth.uid 도출). 방 직접 INSERT·23505
///   재조회 수렴은 앱에 존재하지 않는다(공용 구현부 F10 이 원자 확보).
/// - 생성: `api_app_v1.qna_create_question_thread(...)` (F3) — envelope
///   `{ok, contract_version, ...}` 를 반환하며 도메인 거부는 `{ok:false, code}`.
///   무료질문권 소비는 F3 소관 — F2 성공 시점에 로컬 차감하지 않는다.
/// - 기존 public RPC(qna_create_free_question_thread) fallback 은 두지 않는다.
/// - 자격 scope(가입 7일 창·전역 총량·멘토쌍 한도) '판정'은 전부 서버 —
///   앱은 수량·기간을 하드코딩하지 않고 사실값(본인 free_question_usage 행)만 읽는다.
/// - 캐시 차감형 개별질문(IQ)과는 완전히 분리 — handler·RPC·상태 재사용 금지.

/// 자격 조회 스냅샷(사실값만 — 한도 판정 없음).
class FreeQuestionEntrySnapshot {
  const FreeQuestionEntrySnapshot({
    required this.roomId,
    required this.totalUsed,
    required this.perMentorUsed,
  });

  /// 현재 학생↔이 멘토의 질문방 id. null = 방 없음(질문 시점에 F2 로 확보).
  final String? roomId;

  /// 내 무료 질문 사용 행 수(전역 — 표시용 사실값).
  final int totalUsed;

  /// 이 멘토와의 무료 질문 사용 행 수(표시용 사실값).
  final int perMentorUsed;
}

/// F2 성공 결과(서버 반환 정본 — §4.1).
class EnsuredQuestionRoom {
  const EnsuredQuestionRoom({
    required this.roomId,
    required this.created,
    required this.entitlement,
  });

  final String roomId;

  /// true = 이번 호출이 방을 만들었다(동일 pair 재호출은 false — 기존 방 재사용).
  final bool created;

  /// 'free' | 'subscription'.
  final String entitlement;
}

/// 생성 성공 결과(서버 반환 정본만).
class CreatedFreeQuestion {
  const CreatedFreeQuestion({
    required this.threadId,
    required this.roomId,
    required this.path,
    required this.usedFreeQuota,
  });

  final String threadId;
  final String roomId;

  /// 'free' | 'subscription' — 서버가 판정한 실제 경로.
  final String path;
  final bool usedFreeQuota;
}

/// CTA 상태 — hidden 은 렌더 자체 없음.
enum FreeQuestionCtaStatus {
  /// 멘토·게스트·관리자·구독자(기존 질문방 진입 유지) → 미노출.
  hidden,

  /// 자격 조회 중 — 활성 CTA 0.
  loading,

  /// 조회 실패 — 재시도 제공, 활성 CTA 0, 생성 RPC 0.
  unavailable,

  /// 조회 성공 → CTA 활성. 방이 없으면 질문 시점에 F2 가 확보한다
  /// (최종 자격 판정은 F2/F3 서버가 한다).
  ready,
}

/// CTA 노출·활성 판정(순수 — 한도 수치 계산 없음).
/// S2-2: 방 부재는 더 이상 차단 사유가 아니다 — F2(ensure_free_question_room)가
/// 질문 시점에 방을 원자 확보한다.
FreeQuestionCtaStatus decideFreeQuestionCta({
  required bool isStudent,
  required bool? alreadySubscribed,
  required bool loading,
  required bool fetchFailed,
  required FreeQuestionEntrySnapshot? snapshot,
}) {
  if (!isStudent) return FreeQuestionCtaStatus.hidden;
  // 구독자는 기존 '질문방으로' 진입 계약 유지 — 무료 CTA 미노출.
  if (alreadySubscribed == true) return FreeQuestionCtaStatus.hidden;
  // 구독 여부 미확정 동안에도 활성 CTA 를 노출하지 않는다.
  if (alreadySubscribed == null || loading) {
    return FreeQuestionCtaStatus.loading;
  }
  if (fetchFailed || snapshot == null) return FreeQuestionCtaStatus.unavailable;
  return FreeQuestionCtaStatus.ready;
}

/// 테스트 주입용 포트.
abstract class FreeQuestionEntryPort {
  Future<FreeQuestionEntrySnapshot> fetch(String mentorId);

  /// F2 — 방 원자 확보(없으면 생성, 있으면 재사용). 실패는 AppError(한글).
  Future<EnsuredQuestionRoom> ensureRoom(String mentorId);

  Future<CreatedFreeQuestion> createFreeThread({
    required String roomId,
    required String title,
    String? subject,
    String? firstMessageBody,
  });
}

/// 운영 구현 — 조회는 본인 행 SELECT(RLS), 확보·생성은 `api_app_v1` wrapper.
class SupabaseFreeQuestionEntryRepository implements FreeQuestionEntryPort {
  const SupabaseFreeQuestionEntryRepository({SupabaseClient? client})
      : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client {
    final SupabaseClient? c = _clientOverride ?? SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw const AppError('로그인이 필요해요.');
    return id;
  }

  @override
  Future<FreeQuestionEntrySnapshot> fetch(String mentorId) async {
    final SupabaseClient client = _client;
    final String uid = _uid;
    final Map<String, dynamic>? room = await client
        .from('mentor_student_rooms')
        .select('id')
        .eq('student_id', uid)
        .eq('mentor_id', mentorId)
        .maybeSingle();
    // 사용 행은 서버 계약상 소수(전역 총량 한도 내) — 행을 읽어 사실값만 센다.
    final List<dynamic> usage = await client
        .from('free_question_usage')
        .select('mentor_id')
        .eq('student_id', uid);
    int per = 0;
    for (final dynamic r in usage) {
      if (r is Map && r['mentor_id'] == mentorId) per++;
    }
    final Object? roomIdValue = room?['id'];
    return FreeQuestionEntrySnapshot(
      roomId: roomIdValue is String ? roomIdValue : null,
      totalUsed: usage.length,
      perMentorUsed: per,
    );
  }

  @override
  Future<EnsuredQuestionRoom> ensureRoom(String mentorId) async {
    final Object? data;
    try {
      // F2 — 학생 ID 미전송(서버 auth.uid 도출). 방 확보는 무료질문권을
      // 소비하지 않는다(소비는 F3 트랜잭션 몫 — §4.2).
      data = await _client.schema('api_app_v1').rpc<dynamic>(
        'ensure_free_question_room',
        params: <String, dynamic>{'p_mentor_id': mentorId},
      );
    } catch (e) {
      throw mapQnaError(e);
    }
    if (data is! Map || data['ok'] is! bool) {
      throw const AppError('질문방 확인 결과를 알 수 없어요. 잠시 후 다시 시도해 주세요.');
    }
    if (data['ok'] != true) {
      throw qnaEnvelopeError((data['code'] as String?) ?? '');
    }
    final Object? roomId = data['room_id'];
    if (roomId is! String || roomId.isEmpty) {
      throw const AppError('질문방 확인 결과를 알 수 없어요. 잠시 후 다시 시도해 주세요.');
    }
    return EnsuredQuestionRoom(
      roomId: roomId,
      created: data['created'] == true,
      entitlement: (data['entitlement'] as String?) ?? 'free',
    );
  }

  @override
  Future<CreatedFreeQuestion> createFreeThread({
    required String roomId,
    required String title,
    String? subject,
    String? firstMessageBody,
  }) async {
    final Object? data;
    try {
      // F3 — envelope 반환 wrapper. IQ·구독 작성 화면 handler 와 공유하지
      // 않는다. 원자성·멱등·한도 판정(무료질문권 소비 포함)은 서버 트랜잭션 몫.
      data = await _client.schema('api_app_v1').rpc<dynamic>(
        'qna_create_question_thread',
        params: <String, dynamic>{
          'p_room_id': roomId,
          'p_title': title,
          'p_subject': subject,
          'p_first_message_body': firstMessageBody,
        },
      );
    } catch (e) {
      throw mapQnaError(e);
    }
    if (data is! Map || data['ok'] is! bool) {
      // 로컬 가짜 성공을 만들지 않는다 — 구조 불명이면 실패로 처리.
      throw const AppError('무료 질문 등록 결과를 확인하지 못했어요. 질문방에서 확인해 주세요.');
    }
    if (data['ok'] != true) {
      throw qnaEnvelopeError((data['code'] as String?) ?? '');
    }
    if (data['thread_id'] is! String) {
      throw const AppError('무료 질문 등록 결과를 확인하지 못했어요. 질문방에서 확인해 주세요.');
    }
    return CreatedFreeQuestion(
      threadId: data['thread_id'] as String,
      roomId: roomId,
      path: (data['path'] as String?) ?? 'free',
      usedFreeQuota: (data['used_free_quota'] as bool?) ?? false,
    );
  }
}
