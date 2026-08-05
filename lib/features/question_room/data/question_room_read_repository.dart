import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/entitlement/weekly_question_usage.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'models/connection_note.dart';
import 'models/question_attachment.dart';
import 'models/question_message.dart';
import 'models/question_thread.dart';
import 'models/room.dart';

/// 질문방 읽기 전용 레포지토리.
///
/// ★ 권한 필터는 추가 코드로 만들지 않는다 — DB RLS('그 방의 student/mentor 본인만')에 의존.
///   즉 myRooms()는 별도 where 없이도 RLS가 내 방만 돌려준다.
///   에러는 삼키지 않고 그대로 전파한다(호출부/화면에서 처리).
class QuestionRoomReadRepository {
  const QuestionRoomReadRepository();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  /// 내가 참여한 방 목록(최근 활동순). RLS가 student_id/mentor_id 본인 방만 통과시킨다.
  Future<List<Room>> myRooms() async {
    final List<Map<String, dynamic>> rows = await _client
        .from('mentor_student_rooms')
        .select('*')
        .order('updated_at', ascending: false);
    return rows.map(Room.fromMap).toList();
  }

  /// 방 1건(N16 — 알림 딥링크용 단건 조회). RLS 로 당사자만 통과하므로
  /// 없거나 권한 밖이면 null — 내 방 전량을 받아 뒤지지 않는다.
  Future<Room?> roomById(String roomId) async {
    final Map<String, dynamic>? row = await _client
        .from('mentor_student_rooms')
        .select('*')
        .eq('id', roomId)
        .maybeSingle();
    return row == null ? null : Room.fromMap(row);
  }

  /// 방의 질문 스레드 목록(최근 활동순 = updated_at desc).
  /// 웹 정본(questionRoomQueries: updated_at→created_at→id) 및 앱 threadsForRooms 와 정렬 일치(XV-QUERY-1).
  Future<List<QuestionThread>> threads(String roomId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('question_threads')
        .select('*')
        .eq('mentor_student_room_id', roomId)
        .order('updated_at', ascending: false);
    return rows.map(QuestionThread.fromMap).toList();
  }

  /// 여러 방의 질문 스레드를 한 번에(최신순). 멘토 받은-학생 목록의 상태 요약용.
  /// roomIds 가 비면 쿼리 없이 빈 리스트.
  Future<List<QuestionThread>> threadsForRooms(List<String> roomIds) async {
    if (roomIds.isEmpty) return <QuestionThread>[];
    final List<Map<String, dynamic>> rows = await _client
        .from('question_threads')
        .select('*')
        .inFilter('mentor_student_room_id', roomIds)
        .order('updated_at', ascending: false);
    return rows.map(QuestionThread.fromMap).toList();
  }

  /// 방 멘토의 담당 과목 코드 목록(mentor_profiles.teaching_subjects, text[]).
  ///
  /// 질문 작성 시 과목 후보 제한(A1)용. 공개 프로필 필드만 읽는다.
  /// 없거나 조회 실패면 빈 리스트 → 호출부가 전체 과목으로 폴백한다(빈 드롭다운 금지).
  Future<List<String>> mentorTeachingSubjects(String mentorId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('mentor_profiles')
          .select('teaching_subjects')
          .eq('user_id', mentorId)
          .maybeSingle();
      final Object? raw = row?['teaching_subjects'];
      if (raw is List) {
        return raw
            .map((Object? e) => e?.toString().trim() ?? '')
            .where((String s) => s.isNotEmpty)
            .toList();
      }
      return <String>[];
    } catch (_) {
      return <String>[]; // 조회 실패 → 전체 폴백
    }
  }

  /// 주간 질문 사용량(읽기 전용 RPC `get_weekly_question_usage`). A2 앱-계층 검사·표시용.
  ///
  /// 반환값(used/limit/remaining/can_ask)이 정본이다. 조회 실패/미인식 형태면 null →
  /// 호출부는 흐름을 막지 않고(보수적 진행) 검사 없이 넘긴다(DB 미강제 한계 감안).
  Future<WeeklyQuestionUsage?> weeklyUsage({
    required String studentId,
    required String mentorId,
  }) async {
    try {
      final Object? data = await _client.rpc(
        'get_weekly_question_usage',
        params: <String, dynamic>{
          'p_student_id': studentId,
          'p_mentor_id': mentorId,
        },
      );
      return WeeklyQuestionUsage.fromRpc(data);
    } catch (_) {
      return null; // 실패 → 판정 불가(호출부가 보수적으로 처리)
    }
  }

  /// 스레드 1건의 최신 상태(실시간 상태 변경 후 재조회용). 없으면 null.
  Future<QuestionThread?> threadById(String threadId) async {
    final Map<String, dynamic>? row = await _client
        .from('question_threads')
        .select('*')
        .eq('id', threadId)
        .maybeSingle();
    return row == null ? null : QuestionThread.fromMap(row);
  }

  /// 스레드의 메시지 목록(대화 순서 = created_at 오름차순).
  Future<List<QuestionMessage>> messages(String threadId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('question_messages')
        .select('*')
        .eq('thread_id', threadId)
        .order('created_at', ascending: true);
    return rows.map(QuestionMessage.fromMap).toList();
  }

  /// 방의 연결노트 전부(학생·멘토 섞여 옴, 최근 수정순).
  /// 작성자 구분은 각 행의 authorRole 로 — 호출부에서 역할별로 나눠 쓸 수 있다.
  Future<List<ConnectionNote>> notes(String roomId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('connection_notes')
        .select('*')
        .eq('mentor_student_room_id', roomId)
        .order('updated_at', ascending: false);
    return rows.map(ConnectionNote.fromMap).toList();
  }

  /// 스레드의 첨부 목록(골격). 화면 연결은 S6.
  Future<List<QuestionAttachment>> attachments(String threadId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('question_attachments')
        .select('*')
        .eq('thread_id', threadId)
        .order('created_at', ascending: false);
    return rows.map(QuestionAttachment.fromMap).toList();
  }
}
