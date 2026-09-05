import '../../../core/auth/auth_service.dart';
import '../../../core/entitlement/subscription_status_display.dart';
import '../../../core/entitlement/weekly_question_usage.dart';
import '../../../design/widgets/status_pill.dart';
import '../../../shared/constants/plan_constants.dart';

/// 마이페이지 뷰모델(읽기 전용 조합). 화면은 이 데이터만 보고 그린다(role-aware).
/// ★ 결제·금액 mutate 없음. 미확정 값(요금제명·잔여수)은 비우고 날조하지 않는다.
class MyPageData {
  const MyPageData({
    required this.role,
    required this.profile,
    this.subscriptions = const <SubscriptionCardInfo>[],
    this.cash,
    this.mentor,
  });

  final AppRole role;
  final MyProfile profile;

  /// 학생: 멘토별 구독 카드.
  final List<SubscriptionCardInfo> subscriptions;

  /// 학생: 캐시 잔액·내역(조회). null 이면 섹션 비표시/안내.
  final CashSummary? cash;

  /// 멘토: 답변·정산 요약(조회). null 이면 비표시.
  final MentorDashboard? mentor;

  bool get isMentor => role == AppRole.mentor;
}

/// 프로필 기본 정보.
class MyProfile {
  const MyProfile({
    required this.name,
    required this.roleLabel,
    this.email,
    this.grade,
  });

  final String name;
  final String roleLabel;
  final String? email;

  /// 학년(예: '고2'). DB grade_level 이 이미 한글 표기라 그대로 쓴다. 없으면 비움.
  final String? grade;
}

/// 멘토별 구독 카드(조회). 요금제명은 미확정(planLabels 비어있음)이라 보통 null → 표시 생략.
class SubscriptionCardInfo {
  const SubscriptionCardInfo({
    required this.mentorName,
    required this.isActive,
    this.subscriptionId,
    this.status,
    this.planTier,
    this.nextRenewal,
    this.remaining,
    this.usage,
    this.cancelAtPeriodEnd = false,
  });

  final String mentorName;
  final bool isActive;

  /// `subscriptions.id` — 해지 예약·취소·환불 신청의 인자(A-4b). null 이면 동작 버튼 없음.
  final String? subscriptionId;

  /// 해지 예약 플래그(`cancel_at_period_end`). 상태값이 active 여도 true 면 해지 예정.
  final bool cancelAtPeriodEnd;

  /// 해지 예정 여부 — 플래그 또는 상태값(`cancel_scheduled`).
  bool get isCancelScheduled =>
      cancelAtPeriodEnd || status?.trim() == 'cancel_scheduled';

  /// 원본 상태값(표시 세분화용). null 이면 [isActive] 로 폴백.
  final String? status;

  /// 내부 코드(limited|standard|premium). 화면엔 [planLabel] 로만.
  final String? planTier;
  final DateTime? nextRenewal;

  /// 잔여 질문수. ★ 미확정이면 null → 숫자 대신 구독 상태로 표기(S4와 동일).
  final int? remaining;

  /// A2: 주간 질문 사용량(RPC `get_weekly_question_usage`). 있으면 "주 N개·잔여 X/N"
  /// 표시에 쓰고, 없으면(조회 실패·미구독) 상태 문구로 폴백한다.
  final WeeklyQuestionUsage? usage;

  /// 구독 상태 한글(정본 세분화: 이용 중/결제 확인 필요/해지됨/만료됨/환불됨 등).
  String get statusLabel =>
      subscriptionStatusDisplay(status, isActive: isActive).label;

  /// 상태 칩 톤(정본 매핑).
  StatusTone get statusTone =>
      subscriptionStatusDisplay(status, isActive: isActive).tone;

  /// 확정된 요금제 한글 라벨만 반환(미확정이면 null → 표시 생략, 날조 없음).
  String? get planLabel {
    final String? code = planTier?.trim();
    if (code == null || code.isEmpty) return null;
    for (final PlanTier t in PlanTier.values) {
      if (t.name == code) {
        final String label = planLabels[t] ?? '';
        return label.isEmpty ? null : label;
      }
    }
    return null;
  }
}

/// 캐시 잔액 요약(조회). balanceCents null → 잔액 미확인(비움).
class CashSummary {
  const CashSummary({this.balanceCents, this.recent = const <CashEntry>[]});

  final int? balanceCents;
  final List<CashEntry> recent;

  bool get hasBalance => balanceCents != null;
}

/// cash_ledger.reason 정본 4종 → 한글 라벨 (세션1 §5).
/// ★ exact 매핑만 허용 — contains/접두사/부분 문자열/부호 추론 금지.
///   (구 동작은 부호로 라벨을 추론해 '개별질문 환불'(+delta)이 '충전'으로 보였다.)
const Map<String, String> kCashLedgerReasonLabels = <String, String>{
  'cash_topup': '충전',
  'subscription_payment': '구독 결제',
  'individual_question_escrow_hold': '개별질문 안전 결제',
  'individual_question_refund': '개별질문 환불',
};

/// 미지·null·빈 값 reason 은 크래시 없이 중립 표기(영문 코드 비노출).
String cashLedgerReasonLabel(String? reason) =>
    kCashLedgerReasonLabels[reason] ?? '기타 내역';

/// 캐시 내역 한 줄(조회). 라벨은 reason exact 매핑, 금액 부호·색은 실제
/// delta 가 정본 — 라벨과 부호를 서로 추론하지 않는다.
class CashEntry {
  const CashEntry(
      {required this.deltaCents, required this.createdAt, this.reason});

  final int deltaCents;
  final DateTime createdAt;

  /// cash_ledger.reason 원문 코드(표시엔 kindLabel 만 사용).
  final String? reason;

  bool get isCredit => deltaCents >= 0;

  /// 유형 한글: 정본 4종 exact → 그 외 '기타 내역'.
  String get kindLabel => cashLedgerReasonLabel(reason);
}

/// 멘토 대시보드 요약(조회만). 정산 출금은 웹에서.
class MentorDashboard {
  const MentorDashboard({
    required this.studentCount,
    required this.pendingAnswers,
    this.latestSettlementCents,
  });

  /// 구독(연결) 학생 수.
  final int studentCount;

  /// 답변 대기(pending) 합계 — 멘토가 답할 차례.
  final int pendingAnswers;

  /// 가장 최근 정산 금액(cents, 조회용). 없으면 null → 표시 생략.
  final int? latestSettlementCents;
}
