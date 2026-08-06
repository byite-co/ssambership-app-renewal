import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// N21 와이어 계약 — 복합 커서 쿼리가 PostgREST 로 나가는 **실제 요청 URL** 검증.
///
/// 네트워크·시크릿 없이 mock http 로 요청을 캡처한다. 쿼리 체인은
/// QuestionRoomReadRepository.recentMessages/messagesBefore 와 동일하게
/// 구성한다(리포지토리는 전역 SupabaseInit 클라이언트를 쓰므로 여기서는
/// 같은 체인을 미러링 — 체인 변경 시 이 테스트도 함께 갱신할 것).
void main() {
  late Uri captured;
  late SupabaseClient client;

  setUp(() {
    final MockClient mock = MockClient((http.Request req) async {
      captured = req.url;
      return http.Response(jsonEncode(<Object>[]), 200,
          request: req,
          headers: <String, String>{'content-type': 'application/json'});
    });
    client = SupabaseClient('http://mock.local', 'test-key-not-a-secret',
        httpClient: mock);
  });

  test('recentMessages 체인 — 복합 정렬(created_at desc, id desc) + limit', () async {
    await client
        .from('question_messages')
        .select('*')
        .eq('thread_id', 't1')
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(200);

    final String q = captured.query;
    expect(captured.path, '/rest/v1/question_messages');
    expect(q, contains('thread_id=eq.t1'));
    expect(Uri.decodeComponent(q),
        contains('order=created_at.desc.nullslast,id.desc.nullslast'));
    expect(q, contains('limit=200'));
  });

  test('messagesBefore 체인 — or=(lt, and(eq, id.lt)) 복합 커서 필터', () async {
    const String ts = '2026-08-06T09:00:00.123456Z';
    const String id = '0f0e0d0c-0b0a-0908-0706-050403020100';
    await client
        .from('question_messages')
        .select('*')
        .eq('thread_id', 't1')
        .or(messageCursorBeforeFilter(ts: ts, id: id))
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(200);

    final String decoded = Uri.decodeComponent(captured.query);
    expect(
        decoded,
        contains(
            'or=(created_at.lt."$ts",and(created_at.eq."$ts",id.lt."$id"))'));
    expect(
        decoded, contains('order=created_at.desc.nullslast,id.desc.nullslast'));
  });
}
