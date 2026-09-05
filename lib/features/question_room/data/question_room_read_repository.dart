import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/entitlement/weekly_question_usage.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'models/connection_note.dart';
import 'models/model_parse.dart';
import 'models/question_attachment.dart';
import 'models/question_message.dart';
import 'models/question_thread.dart';
import 'models/room.dart';

/// 상태 집계 전용 슬림 스레드 행(N20) — 제목·본문 없이 방·상태·활동시각만.
class ThreadStatusRow {
  const ThreadStatusRow({
    required this.roomId,
    required this.status,
    required this.updatedAt,
  });

  final String roomId;
  final ThreadStatus status;
  final DateTime updatedAt;
}

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

  /// 방의 스레드 개수(N23 — 자동 제목 순번용). 전 행 대신 서버 count 1회.
  Future<int> threadCount(String roomId) async {
    final int count = await _client
        .from('question_threads')
        .count(CountOption.exact)
        .eq('mentor_student_room_id', roomId);
    return count;
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

  /// 여러 방의 스레드 상태만 슬림 조회(N20 — 집계 전용). select * 로 제목·
  /// 과목까지 전량 내려받던 인박스·대시보드 집계를 방·상태·활동시각 3컬럼으로
  /// 줄인다. 집계 규칙은 ThreadStatusCounts.fromStatuses 와 짝.
  Future<List<ThreadStatusRow>> threadStatusRowsForRooms(
      List<String> roomIds) async {
    if (roomIds.isEmpty) return <ThreadStatusRow>[];
    final List<Map<String, dynamic>> rows = await _client
        .from('question_threads')
        .select('mentor_student_room_id, status, updated_at')
        .inFilter('mentor_student_room_id', roomIds);
    return <ThreadStatusRow>[
      for (final Map<String, dynamic> r in rows)
        ThreadStatusRow(
          roomId: (r['mentor_student_room_id'] as String?) ?? '',
          status: ThreadStatus.fromCode(r['status'] as String?),
          updatedAt: parseTime(r['updated_at']),
        ),
    ];
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

  /// 주간 질문 사용량. A2 앱-계층 검사·표시용.
  ///
  /// N2: 구 `get_weekly_question_usage(p_student_id, p_mentor_id)` 는 임의
  /// student_id 를 받는 구계약이라 self 봉투 RPC
  /// `api_web_v1.weekly_question_usage_self(p_mentor_id)` 로 이행 — 학생은
  /// 서버가 auth.uid() 로 확정한다(타인 사용량 조회 표면 제거).
  /// 반환값(used/limit/remaining/can_ask)이 정본이다. 실패 봉투({ok:false})/
  /// 조회 실패/미인식 형태면 null → 호출부는 보수적으로 처리한다.
  Future<WeeklyQuestionUsage?> weeklyUsage({required String mentorId}) async {
    try {
      final Object? data = await _client.schema('api_web_v1').rpc(
        'weekly_question_usage_self',
        params: <String, dynamic>{'p_mentor_id': mentorId},
      );
      // 실패 봉투를 fromRpc 에 넘기면 used=0/limit=0 의 날조 소진 상태가
      // 된다 — ok:true 봉투만 파싱한다.
      if (data is! Map || data['ok'] != true) return null;
      return WeeklyQuestionUsage.fromRpc(data);
    } catch (_) {
      return null; // 실패 → 판정 불가(호출부가 보수적으로 처리)
    }
  }

  /// 여러 멘토의 주간 사용량을 왕복 1회로(C15 — 목록 표면용 배치).
  ///
  /// 서버 계약: api_web_v1.weekly_question_usage_self_batch(p_mentor_ids)
  ///   {ok:true, contract_version:1, items:[{mentor_id, used, limit, ...}]}
  /// 실패(봉투 포함)면 빈 맵 — 호출부는 멘토별 null(판정 불가)로 처리한다.
  Future<Map<String, WeeklyQuestionUsage?>> weeklyUsageBatch(
      Iterable<String> mentorIds) async {
    final List<String> ids = mentorIds.toSet().toList();
    if (ids.isEmpty) return const <String, WeeklyQuestionUsage?>{};
    try {
      final Object? data = await _client.schema('api_web_v1').rpc(
        'weekly_question_usage_self_batch',
        params: <String, dynamic>{'p_mentor_ids': ids},
      );
      if (data is! Map || data['ok'] != true) {
        return const <String, WeeklyQuestionUsage?>{};
      }
      final Object? items = data['items'];
      final Map<String, WeeklyQuestionUsage?> out =
          <String, WeeklyQuestionUsage?>{};
      if (items is List) {
        for (final Object? item in items) {
          if (item is! Map) continue;
          final Object? mid = item['mentor_id'];
          if (mid is String) out[mid] = WeeklyQuestionUsage.fromRpc(item);
        }
      }
      return out;
    } catch (_) {
      return const <String, WeeklyQuestionUsage?>{};
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

  /// 스레드의 메시지 목록(대화 순서 = created_at 오름차순) — **무제한 전량**.
  /// ★ N21: 화면(채팅·답변)은 [recentMessages]/[messagesBefore] 페이지 경로를
  ///   쓴다. 이 메서드는 dev 인스펙터 등 소량 확정 표면 전용으로 남긴다.
  Future<List<QuestionMessage>> messages(String threadId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('question_messages')
        .select('*')
        .eq('thread_id', threadId)
        .order('created_at', ascending: true);
    return rows.map(QuestionMessage.fromMap).toList();
  }

  /// 최근 메시지 [limit]건(N21 완결 — 무제한 전량 조회 제거). 반환은
  /// 대화순(asc). 반환 길이 == limit 이면 이전 페이지가 더 있을 수 있다.
  /// ★ 정렬은 (created_at DESC, id DESC) 복합 — 동일 시각 다건에서도
  ///   페이지 경계가 결정론적이다(커서 계약과 동일 축).
  Future<List<QuestionMessage>> recentMessages(
    String threadId, {
    required int limit,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('question_messages')
        .select('*')
        .eq('thread_id', threadId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(QuestionMessage.fromMap).toList().reversed.toList();
  }

  /// [cursor] 이전(과거 방향) 메시지 [limit]건 — '이전 대화 불러오기'용(asc).
  ///
  /// 복합 커서(created_at, id): `created_at < c.ts OR (created_at = c.ts AND
  /// id < c.id)` — 동일 created_at 경계에서도 누락 0·중복 0. 타임스탬프는
  /// UTC ISO(마이크로초 보존 — PG µs 정밀도와 일치)로 보낸다.
  Future<List<QuestionMessage>> messagesBefore(
    String threadId, {
    required MessageCursor cursor,
    required int limit,
  }) async {
    final String ts = cursor.createdAt.toUtc().toIso8601String();
    final List<Map<String, dynamic>> rows = await _client
        .from('question_messages')
        .select('*')
        .eq('thread_id', threadId)
        .or(messageCursorBeforeFilter(ts: ts, id: cursor.id))
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(QuestionMessage.fromMap).toList().reversed.toList();
  }

  /// 방의 연결노트 전부(학생·멘토 섞여 옴, 최근 수정순).
  /// 작성자 구분은 각 행의 authorRole 로 — 호출부에서 역할별로 나눠 쓸 수 있다.
  Future<List<ConnectionNote>> notes(String roomId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('connection_notes')
        .select('*')
        .eq('mentor_student_room_id', roomId)
        // A-5: 노트는 INSERT 전용 이력 — created_at 최신순(수정 시각 없음).
        .order('created_at', ascending: false);
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

/// N21: 메시지 페이지네이션 복합 커서 — 현재 로드된 가장 오래된 행의
/// (created_at, id). created_at 단독 커서는 동일 시각 다건에서 경계 행을
/// 건너뛴다 — id 타이브레이크로 무손실을 보장한다.
class MessageCursor {
  const MessageCursor({required this.createdAt, required this.id});

  /// 커서 행의 created_at(서버 정본 파싱값 — µs 정밀 보존).
  final DateTime createdAt;

  /// 커서 행의 id(uuid — PostgREST uuid 비교는 바이트 순).
  final String id;

  /// 대화순(asc) 목록의 첫 행 = 가장 오래된 행에서 커서를 만든다.
  factory MessageCursor.oldestOf(List<QuestionMessage> ascMessages) =>
      MessageCursor(
        createdAt: ascMessages.first.createdAt,
        id: ascMessages.first.id,
      );
}

/// PostgREST or= 필터 문자열(과거 방향):
/// `created_at.lt.TS , and(created_at.eq.TS, id.lt.ID)`.
/// 순수 함수 — 테스트가 형식을 고정한다(따옴표 규약: 타임스탬프는 콤마·콜론
/// 포함 값이라 쌍따옴표로 감싼다 — PostgREST reserved-char 규약).
String messageCursorBeforeFilter({required String ts, required String id}) {
  return 'created_at.lt."$ts",and(created_at.eq."$ts",id.lt."$id")';
}
