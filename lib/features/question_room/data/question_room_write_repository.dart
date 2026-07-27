import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'models/connection_note.dart';
import 'models/question_message.dart';
import 'qna_error_mapper.dart';

/// 질문 생성 RPC 결과(서버는 전체 행이 아니라 id·경로만 돌려준다).
class CreatedQuestionThread {
  const CreatedQuestionThread({
    required this.threadId,
    this.messageId,
    required this.path,
    required this.usedFreeQuota,
  });

  final String threadId;

  /// 첫 메시지 id(본문이 비었으면 서버가 메시지를 만들지 않아 null).
  final String? messageId;

  /// 'subscription' | 'free' — 서버가 판정한 소비 경로.
  final String path;
  final bool usedFreeQuota;
}

/// append RPC 결과. [answeredTransition]=true 면 이번 메시지로 서버가
/// pending→answered 전이(+question_answered 알림)를 수행했다는 뜻.
class AppendedMessage {
  const AppendedMessage(
      {required this.message, required this.answeredTransition});

  final QuestionMessage message;
  final bool answeredTransition;
}

/// 질문방 쓰기 레포지토리 — v16부터 질문 워크플로 쓰기는 전부 서버 원자 RPC.
///
/// ★ question_threads/question_messages 직접 INSERT/UPDATE 금지(P1-8).
///   생성·append·확인·오답은 qna_* RPC만 사용한다 — 사용량 소비·answered 전이·
///   question_answered 알림은 전부 서버 트랜잭션 책임이고 앱은 결과만 반영한다.
/// ★ 방(mentor_student_rooms) 생성 메서드는 두지 않는다(앱에서 INSERT 정책 없음 = 불가).
/// ★ 메시지는 append 전용 — 수정/삭제 메서드 없음.
class QuestionRoomWriteRepository {
  const QuestionRoomWriteRepository();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  /// 현재 로그인 사용자 id(세션). 없으면 에러.
  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AppError('로그인이 필요해요.');
    }
    return id;
  }

  /// 질문 생성 — 서버 원자 RPC `qna_create_question_thread` 한 번만 호출한다.
  ///
  /// thread + 첫 메시지 + 사용량 소비(주간/무료)가 서버 한 트랜잭션이라
  /// 실패 시 빈 thread 가 남지 않는다. status 는 앱이 보내지 않는다(서버가
  /// 'pending' 고정). 무료/구독 경로 분기도 서버 몫(qna_create_free_question_thread
  /// 는 동일 함수 위임 래퍼라 별도 호출 불필요).
  /// subject 는 정본 subjects.code 만 — catalog 밖 값은 서버가 조용히 NULL 처리한다.
  Future<CreatedQuestionThread> createThread({
    required String roomId,
    required String title,
    String? subject,
    String? topic,
    required String firstMessageBody,
  }) async {
    final Object? data;
    try {
      data = await _client.rpc(
        'qna_create_question_thread',
        params: <String, dynamic>{
          'p_room_id': roomId,
          'p_title': title,
          'p_subject': subject,
          'p_topic': topic,
          'p_first_message_body': firstMessageBody,
        },
      );
    } catch (e) {
      throw mapQnaError(e);
    }
    if (data is! Map) {
      throw const AppError('질문 등록 결과를 확인하지 못했어요. 목록을 새로고침해 주세요.');
    }
    return CreatedQuestionThread(
      threadId: data['thread_id'] as String,
      messageId: data['message_id'] as String?,
      path: (data['path'] as String?) ?? 'subscription',
      usedFreeQuota: (data['used_free_quota'] as bool?) ?? false,
    );
  }

  /// 메시지 append — RPC `qna_append_message`.
  ///
  /// 첫 멘토 메시지면 서버가 answered 전이 + question_answered 알림까지 수행하고
  /// answered_transition=true 를 돌려준다(이후 메시지는 재전이·재알림 없음).
  /// 앱은 별도 status UPDATE 를 하지 않는다.
  /// 반환 메시지는 서버 id + 로컬 필드로 구성한 낙관적 표현 — 실측 행은
  /// 새로고침/Realtime 재조회로 수렴한다.
  Future<AppendedMessage> appendMessage({
    required String threadId,
    required String body,
  }) async {
    final String uid = _uid;
    final Object? data;
    try {
      data = await _client.rpc(
        'qna_append_message',
        params: <String, dynamic>{'p_thread_id': threadId, 'p_body': body},
      );
    } catch (e) {
      throw mapQnaError(e);
    }
    if (data is! Map) {
      throw const AppError('메시지 전송 결과를 확인하지 못했어요. 새로고침해 주세요.');
    }
    return AppendedMessage(
      message: QuestionMessage(
        id: data['message_id'] as String,
        threadId: threadId,
        authorId: uid,
        body: body.trim(),
        createdAt: DateTime.now().toUtc(),
      ),
      answeredTransition: (data['answered_transition'] as bool?) ?? false,
    );
  }

  /// 학생 답변 확인(answered → confirmed) — RPC `qna_confirm_thread`.
  /// 이미 confirmed 면 서버가 멱등 성공을 돌려준다. 직접 UPDATE 금지.
  Future<void> confirmThread(String threadId) async {
    try {
      await _client.rpc(
        'qna_confirm_thread',
        params: <String, dynamic>{'p_thread_id': threadId},
      );
    } catch (e) {
      throw mapQnaError(e);
    }
  }

  /// 오답 표시/해제 — RPC `qna_flag_wrong_answer`(학생 전용).
  /// is_wrong_answer + mastery_status 갱신은 서버 책임. 직접 UPDATE 금지.
  Future<void> flagWrongAnswer(String threadId, {bool isWrong = true}) async {
    try {
      await _client.rpc(
        'qna_flag_wrong_answer',
        params: <String, dynamic>{
          'p_thread_id': threadId,
          'p_is_wrong': isWrong
        },
      );
    } catch (e) {
      throw mapQnaError(e);
    }
  }

  /// 내 연결노트 추가/수정. 본인(author_id=현재 사용자) 행만 다룬다.
  /// 같은 방에 내 노트가 있으면 body 갱신, 없으면 새 행 삽입.
  /// author_role 은 현재 사용자 역할에서 채운다(남의 노트는 RLS가 차단).
  Future<ConnectionNote> upsertMyNote({
    required String roomId,
    required String body,
  }) async {
    final String uid = _uid;

    // 내 기존 노트 찾기(본인 것만).
    final Map<String, dynamic>? existing = await _client
        .from('connection_notes')
        .select('id')
        .eq('mentor_student_room_id', roomId)
        .eq('author_id', uid)
        .maybeSingle();

    if (existing != null) {
      final Map<String, dynamic> row = await _client
          .from('connection_notes')
          .update(<String, dynamic>{
            'body': body,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', existing['id'] as String)
          .select()
          .single();
      return ConnectionNote.fromMap(row);
    }

    final Map<String, dynamic> row = await _client
        .from('connection_notes')
        .insert(<String, dynamic>{
          'mentor_student_room_id': roomId,
          'author_id': uid,
          'author_role': _currentAuthorRoleCode(),
          'body': body,
        })
        .select()
        .single();
    return ConnectionNote.fromMap(row);
  }

  /// 현재 사용자 역할 → connection_notes.author_role 코드(student|mentor).
  /// 그 외 역할은 노트 작성 대상이 아니므로 명시적 에러.
  String _currentAuthorRoleCode() {
    switch (AuthService.instance.currentRole) {
      case AppRole.student:
        return 'student';
      case AppRole.mentor:
        return 'mentor';
      case AppRole.admin:
      case AppRole.guest:
        throw const AppError('이 계정은 연결노트를 작성할 수 없어요.');
    }
  }
}
