import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import '../../question_room/data/qna_error_mapper.dart';

/// 무료 질문 진입(세션1 §3) — 자격 '조회'와 생성 RPC 만 담당한다.
///
/// 서버 정본 계약(staging 실측 2026-07-24):
/// - 생성: `qna_create_free_question_thread(p_room_id, p_title, p_subject,
///   p_topic, p_first_message_body)` (authenticated 전용·SECURITY DEFINER·
///   search_path 고정·auth.uid 본인성·원자/멱등 — 본체 qna_create_question_thread
///   위임). 성공 payload {ok, thread_id, message_id, path, used_free_quota}.
/// - 자격(entitlement) scope = **가입 후 7일 창 + 사용자 전역 총량 + 멘토쌍 한도**
///   의 이중 스코프이며, 수량·기간 '판정'은 전부 서버가 한다(FREE_QUOTA_EXPIRED /
///   FREE_QUOTA_TOTAL_EXHAUSTED / FREE_QUOTA_MENTOR_EXHAUSTED).
///   앱은 질문권 수량·기간을 하드코딩하지 않고, 조회 가능한 사실값
///   (본인 free_question_usage 행 — RLS fqu_select_own)과 방 존재 여부만 읽는다.
/// - 방(mentor_student_rooms) 은 SELECT 정책만 있고 앱이 만들 수 없다(생성은
///   웹 서버 전용) → 방 부재 학생의 무료 질문 생성은 WAITING_SERVER_GATE.
/// - 캐시 차감형 개별질문(IQ)과는 완전히 분리 — handler·RPC·상태 재사용 금지.

/// 자격 조회 스냅샷(사실값만 — 한도 판정 없음).
class FreeQuestionEntrySnapshot {
  const FreeQuestionEntrySnapshot({
    required this.roomId,
    required this.totalUsed,
    required this.perMentorUsed,
  });

  /// 현재 학생↔이 멘토의 질문방 id. null = 방 없음(앱에서 생성 불가 — 서버 게이트).
  final String? roomId;

  /// 내 무료 질문 사용 행 수(전역 — 표시용 사실값).
  final int totalUsed;

  /// 이 멘토와의 무료 질문 사용 행 수(표시용 사실값).
  final int perMentorUsed;
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

  /// 방 없음 — 앱은 방을 만들 수 없다(서버 게이트). 활성 CTA 0.
  roomMissing,

  /// 조회 성공 + 방 존재 → CTA 활성(최종 자격 판정은 생성 RPC 가 한다).
  ready,
}

/// CTA 노출·활성 판정(순수 — 한도 수치 계산 없음).
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
  if (snapshot.roomId == null) return FreeQuestionCtaStatus.roomMissing;
  return FreeQuestionCtaStatus.ready;
}

/// 테스트 주입용 포트.
abstract class FreeQuestionEntryPort {
  Future<FreeQuestionEntrySnapshot> fetch(String mentorId);

  Future<CreatedFreeQuestion> createFreeThread({
    required String roomId,
    required String title,
    String? subject,
    String? firstMessageBody,
  });
}

/// 운영 구현 — 조회는 본인 행 SELECT(RLS), 생성은 무료 전용 RPC 1회.
class SupabaseFreeQuestionEntryRepository implements FreeQuestionEntryPort {
  const SupabaseFreeQuestionEntryRepository();

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
  Future<CreatedFreeQuestion> createFreeThread({
    required String roomId,
    required String title,
    String? subject,
    String? firstMessageBody,
  }) async {
    final Object? data;
    try {
      // 무료 전용 진입점 RPC — 개별질문(IQ)·구독 작성 화면의 handler 와 공유하지
      // 않는다. 원자성·멱등·한도 판정은 서버 트랜잭션 몫.
      data = await _client.rpc<dynamic>(
        'qna_create_free_question_thread',
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
    if (data is! Map || data['ok'] != true || data['thread_id'] is! String) {
      // 로컬 가짜 성공을 만들지 않는다 — 구조 불명이면 실패로 처리.
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
