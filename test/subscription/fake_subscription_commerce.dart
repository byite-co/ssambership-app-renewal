import 'dart:async';

import 'package:ssambership_app/features/mentor_console/data/api_web_v1_envelope.dart';
import 'package:ssambership_app/features/subscription/data/subscription_commerce_messages.dart';
import 'package:ssambership_app/features/subscription/data/subscription_commerce_models.dart';
import 'package:ssambership_app/features/subscription/data/subscription_commerce_repository.dart';

/// 구독 결제·해지·환불 포트 fake — 호출을 기록하고 정해진 결과/실패를 돌려준다.
class FakeSubscriptionCommerce implements SubscriptionCommercePort {
  FakeSubscriptionCommerce({
    this.balanceCents = 0,
    this.identityVerified = true,
    this.balanceError,
    this.identityError,
  });

  int balanceCents;
  bool identityVerified;
  Object? balanceError;
  Object? identityError;

  /// 다음 subscribe 호출의 실패 코드(봉투 코드). null 이면 성공.
  String? subscribeFailCode;
  Map<String, dynamic> subscribeFailBody = <String, dynamic>{};

  /// 봉투 밖 예외(네트워크 등)로 실패시킬 때.
  Object? subscribeThrow;

  /// 호출을 잡아두는 게이트(이중 탭 테스트).
  Completer<void>? subscribeGate;

  SubscribeSuccess subscribeResult = const SubscribeSuccess(
    subscriptionId: 'sub-1',
    roomId: 'room-1',
    planTier: 'standard',
    debitedCents: 8490000,
    balanceAfterCents: 0,
  );

  final List<Map<String, String>> subscribeCalls = <Map<String, String>>[];
  int balanceCalls = 0;
  int identityCalls = 0;

  String? cancelFailCode;
  final List<String> cancelCalls = <String>[];
  final List<String> undoCalls = <String>[];
  CancelScheduleResult? cancelResult;
  CancelScheduleResult? undoResult;

  RefundEstimate? estimate;
  Object? estimateError;
  String? refundFailCode;
  final List<String> estimateCalls = <String>[];
  final List<Map<String, String>> refundCalls = <Map<String, String>>[];
  RefundRequestResult refundResult = const RefundRequestResult(
    refundId: 'rf-1',
    subscriptionId: 'sub-1',
    amountCents: 8490000,
    rule: '이용 개시 전',
  );

  @override
  Future<int> fetchWalletBalanceCents() async {
    balanceCalls++;
    if (balanceError != null) throw balanceError!;
    return balanceCents;
  }

  @override
  Future<bool> fetchIdentityVerified() async {
    identityCalls++;
    if (identityError != null) throw identityError!;
    return identityVerified;
  }

  @override
  Future<SubscribeSuccess> subscribeWithCash({
    required String mentorId,
    required String tier,
    required String idempotencyKey,
  }) async {
    subscribeCalls.add(<String, String>{
      'mentorId': mentorId,
      'tier': tier,
      'key': idempotencyKey,
    });
    final Completer<void>? gate = subscribeGate;
    if (gate != null) await gate.future;
    if (subscribeThrow != null) throw subscribeThrow!;
    final String? code = subscribeFailCode;
    if (code != null) {
      throw ApiEnvelopeFailure(
        code,
        subscribeMessageForCode(code, subscribeFailBody),
        subscribeFailBody,
      );
    }
    return subscribeResult;
  }

  @override
  Future<CancelScheduleResult> cancelAtPeriodEnd(String subscriptionId) async {
    cancelCalls.add(subscriptionId);
    final String? code = cancelFailCode;
    if (code != null) {
      throw ApiEnvelopeFailure(
          code, cancelScheduleMessageForCode(code, const {}), const {});
    }
    return cancelResult ??
        CancelScheduleResult(
          subscriptionId: subscriptionId,
          cancelAtPeriodEnd: true,
        );
  }

  @override
  Future<CancelScheduleResult> cancelUndo(String subscriptionId) async {
    undoCalls.add(subscriptionId);
    final String? code = cancelFailCode;
    if (code != null) {
      throw ApiEnvelopeFailure(
          code, cancelScheduleMessageForCode(code, const {}), const {});
    }
    return undoResult ??
        CancelScheduleResult(
          subscriptionId: subscriptionId,
          cancelAtPeriodEnd: false,
          wasScheduled: true,
        );
  }

  @override
  Future<RefundEstimate> refundEstimate(String subscriptionId) async {
    estimateCalls.add(subscriptionId);
    if (estimateError != null) throw estimateError!;
    return estimate ??
        const RefundEstimate(
          refundableCents: 0,
          amountCents: 0,
          rule: '계산 불가',
          bracketReason: 'invalid',
        );
  }

  @override
  Future<RefundRequestResult> refundRequestCreate({
    required String subscriptionId,
    required String reason,
  }) async {
    refundCalls.add(<String, String>{'id': subscriptionId, 'reason': reason});
    final String? code = refundFailCode;
    if (code != null) {
      throw ApiEnvelopeFailure(
          code, refundMessageForCode(code, const {}), const {});
    }
    return refundResult;
  }
}
