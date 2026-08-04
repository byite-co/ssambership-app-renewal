import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import 'models/individual_question_models.dart';

/// 개별질문(IQ) 실시간 포트 — 새 메시지/첨부(insert)와 질문 상태 변경(update)을
/// 콜백으로 전달한다(thread_realtime 과 동일 구조).
///
/// 화면(IQ 상세)은 이 포트를 주입받아 구독한다. 테스트에서는 fake 를 주입해
/// 실제 네트워크 없이 이벤트 방출을 흉내낸다. ★ 실시간은 보조 채널일 뿐 —
/// 정본은 언제나 서버 재조회(전송 후 재조회·수동 새로고침)다.
abstract class IqRealtimePort {
  /// 구독 시작. [onMessageInsert] 는 새 메시지마다, [onQuestionUpdate] 는 질문
  /// 행 변경(answered 전이 등) 시, [onAttachmentInsert] 는 첨부 행 생성 시 호출.
  /// [onReconnected] 는 채널이 끊겼다 다시 붙었을 때 1회 호출(부모가 전체
  /// 재조회로 공백을 메운다 — 실시간을 유일 소스로 두지 않는 계약).
  void start({
    required void Function(IqMessage message) onMessageInsert,
    void Function()? onQuestionUpdate,
    void Function()? onAttachmentInsert,
    void Function()? onReconnected,
  });

  /// 구독 정리(누수 금지). 화면 dispose·질문 전환·로그아웃에서 호출.
  Future<void> dispose();
}

/// Supabase Realtime 구현(postgres_changes).
///
/// ★ 인프라 의존: individual_questions / individual_question_messages /
///   individual_question_attachments 가 `supabase_realtime` publication 에
///   포함돼 있어야 이벤트가 도착한다(계약 8 — 서버 마이그레이션이 추가).
///   미포함이면 콜백이 오지 않으며, 화면은 '전송 후 재조회 / 수동 새로고침'
///   폴백으로 계속 동작한다(thread_realtime 과 동일 규약).
class SupabaseIqRealtime implements IqRealtimePort {
  SupabaseIqRealtime(this.questionId);

  final String questionId;
  RealtimeChannel? _channel;

  /// 최초 subscribed 이후의 재-subscribed 만 재연결로 판정하기 위한 플래그.
  bool _subscribedOnce = false;

  @override
  void start({
    required void Function(IqMessage message) onMessageInsert,
    void Function()? onQuestionUpdate,
    void Function()? onAttachmentInsert,
    void Function()? onReconnected,
  }) {
    final SupabaseClient? client = SupabaseInit.clientOrNull;
    if (client == null) return; // 백엔드 미연결 → 조용히 무시(폴백만 동작).

    final RealtimeChannel channel = client.channel('iq_$questionId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'individual_question_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'question_id',
        value: questionId,
      ),
      callback: (PostgresChangePayload payload) {
        try {
          onMessageInsert(IqMessage.fromMap(payload.newRecord));
        } catch (_) {
          // 파싱 실패는 무시(폴백 재조회가 보완).
        }
      },
    );

    if (onAttachmentInsert != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'individual_question_attachments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'question_id',
          value: questionId,
        ),
        callback: (_) => onAttachmentInsert(),
      );
    }

    if (onQuestionUpdate != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'individual_questions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: questionId,
        ),
        callback: (_) => onQuestionUpdate(),
      );
    }

    channel.subscribe((RealtimeSubscribeStatus status, Object? error) {
      if (status != RealtimeSubscribeStatus.subscribed) return;
      if (_subscribedOnce) {
        // 재연결 — 끊긴 사이의 이벤트 공백은 부모의 전체 재조회가 메운다.
        onReconnected?.call();
      }
      _subscribedOnce = true;
    });
    _channel = channel;
  }

  @override
  Future<void> dispose() async {
    final RealtimeChannel? ch = _channel;
    _channel = null;
    if (ch != null) {
      await SupabaseInit.clientOrNull?.removeChannel(ch);
    }
  }
}
