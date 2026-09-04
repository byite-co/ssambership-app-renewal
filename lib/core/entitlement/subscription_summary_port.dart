import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';
import 'subscription_summary.dart';

/// 학생 구독 요약 조회 포트 — 화면이 [SubscriptionReader.fetchForStudent] 를
/// 클라이언트 인자와 함께 직접 부르던 것을 주입 가능하게 감싼다(A-2).
///
/// 로직은 [SubscriptionReader] 그대로다 — 이 포트는 클라이언트 획득만 대신한다.
abstract class SubscriptionSummaryPort {
  /// 학생의 구독을 멘토 id 별로 요약. 백엔드 미연결이면 빈 맵.
  Future<Map<String, SubscriptionSummary>> fetchForStudent(String studentId);
}

/// 운영 구현 — 초기화된 Supabase 클라이언트로 기존 리더를 호출한다.
class SupabaseSubscriptionSummaryPort implements SubscriptionSummaryPort {
  const SupabaseSubscriptionSummaryPort();

  @override
  Future<Map<String, SubscriptionSummary>> fetchForStudent(
      String studentId) async {
    final SupabaseClient? client = SupabaseInit.clientOrNull;
    if (client == null) return const <String, SubscriptionSummary>{};
    return SubscriptionReader.fetchForStudent(client, studentId);
  }
}
