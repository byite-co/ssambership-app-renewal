import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import '../../mentor_console/data/api_web_v1_envelope.dart';
import 'subscription_commerce_messages.dart';
import 'subscription_commerce_models.dart';

/// 구독 결제·해지 예약·환불 — `api_app_v1` 래퍼(DB-4 199·200) 포트.
///
/// ★ 자금 판정·차감·방 확보는 전부 DB(정본 F12)가 한다. 앱은 봉투를 strict 로 읽고
///   (`ok` 없는 응답은 성공이 아니다), 코드는 문구 사전으로만 바꾼다.
/// ★ 자금 호출(`subscribeWithCash`)은 반드시 멱등 키와 함께 — 재시도에 같은 키.
abstract class SubscriptionCommercePort {
  /// 내 캐시 잔액(cents). 지갑 미생성이면 0. 조회 실패는 예외(호출부가 '미확인' 처리).
  Future<int> fetchWalletBalanceCents();

  /// 본인인증 완료 여부(`users.identity_verified_at`). 판독 실패는 예외 → 호출부 fail-closed.
  Future<bool> fetchIdentityVerified();

  /// 캐시로 구독 결제. 성공 시 방 id 포함. 실패는 [ApiEnvelopeFailure](코드 보존).
  Future<SubscribeSuccess> subscribeWithCash({
    required String mentorId,
    required String tier,
    required String idempotencyKey,
  });

  Future<CancelScheduleResult> cancelAtPeriodEnd(String subscriptionId);
  Future<CancelScheduleResult> cancelUndo(String subscriptionId);

  Future<RefundEstimate> refundEstimate(String subscriptionId);
  Future<RefundRequestResult> refundRequestCreate({
    required String subscriptionId,
    required String reason,
  });
}

class SupabaseSubscriptionCommerceRepository
    implements SubscriptionCommercePort {
  const SupabaseSubscriptionCommerceRepository();

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

  /// `api_app_v1` 스키마 — 래퍼 RPC 는 전부 여기(리터럴 호출 — 매니페스트 스캔 대상).
  SupabaseQuerySchema get _api => _client.schema('api_app_v1');

  @override
  Future<int> fetchWalletBalanceCents() async {
    // N5: 본인 한정 invoker 뷰(api_web_v1.my_wallet_v1).
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

  @override
  Future<bool> fetchIdentityVerified() async {
    final Map<String, dynamic>? row = await _client
        .from('users')
        .select('identity_verified_at')
        .eq('id', _uid)
        .maybeSingle();
    final Object? v = row?['identity_verified_at'];
    return v is String && v.isNotEmpty;
  }

  @override
  Future<SubscribeSuccess> subscribeWithCash({
    required String mentorId,
    required String tier,
    required String idempotencyKey,
  }) async {
    final Object? data = await _api.rpc('subscribe_with_cash', params: <String, dynamic>{
      'p_mentor_id': mentorId,
      'p_tier': tier,
      'p_idempotency_key': idempotencyKey,
    });
    final ApiEnvelope env =
        ApiEnvelope.parse(data).requireOk(subscribeMessageForCode);
    return SubscribeSuccess.fromBody(env.body);
  }

  @override
  Future<CancelScheduleResult> cancelAtPeriodEnd(String subscriptionId) async {
    final Object? data = await _api.rpc(
      'subscription_cancel_at_period_end',
      params: <String, dynamic>{'p_subscription_id': subscriptionId},
    );
    final ApiEnvelope env =
        ApiEnvelope.parse(data).requireOk(cancelScheduleMessageForCode);
    return CancelScheduleResult.fromBody(env.body);
  }

  @override
  Future<CancelScheduleResult> cancelUndo(String subscriptionId) async {
    final Object? data = await _api.rpc(
      'subscription_cancel_undo',
      params: <String, dynamic>{'p_subscription_id': subscriptionId},
    );
    final ApiEnvelope env =
        ApiEnvelope.parse(data).requireOk(cancelScheduleMessageForCode);
    return CancelScheduleResult.fromBody(env.body);
  }

  @override
  Future<RefundEstimate> refundEstimate(String subscriptionId) async {
    final Object? data = await _api.rpc(
      'refund_estimate',
      params: <String, dynamic>{'p_subscription_id': subscriptionId},
    );
    final ApiEnvelope env =
        ApiEnvelope.parse(data).requireOk(refundMessageForCode);
    return RefundEstimate.fromBody(env.body);
  }

  @override
  Future<RefundRequestResult> refundRequestCreate({
    required String subscriptionId,
    required String reason,
  }) async {
    final Object? data = await _api.rpc(
      'refund_request_create',
      params: <String, dynamic>{
        'p_subscription_id': subscriptionId,
        'p_reason': reason,
      },
    );
    final ApiEnvelope env =
        ApiEnvelope.parse(data).requireOk(refundMessageForCode);
    return RefundRequestResult.fromBody(env.body);
  }
}
