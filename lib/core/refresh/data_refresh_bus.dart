import 'package:flutter/foundation.dart';

/// 도메인 무효화 신호(세션1 §4) — "값이 바뀌었다"는 사실만 전달한다.
///
/// - 데이터 자체는 싣지 않는다: 각 표면이 자기 repository 로 서버 정본을 재조회.
/// - 전역 polling·전역 리빌드·realtime 채널 추가 없이, 기존 구조(Future 교체 +
///   FutureBuilder)에 가장 작은 침습으로 교차 화면 무효화를 잇는다.
/// - 예: IQ 환불 성공 → 지갑 세대 +1 → 마이페이지(잔액·최근 내역)가 살아 있으면
///   즉시 재조회, 죽어 있으면 다음 진입 시 어차피 fresh 조회.
class DataRefreshBus {
  DataRefreshBus._();

  /// 캐시 지갑(잔액·원장) 세대. 값 자체는 의미 없고 변경 통지만 쓴다.
  static final ValueNotifier<int> walletGeneration = ValueNotifier<int>(0);

  /// 지갑에 영향을 주는 mutation 성공 지점에서 호출(IQ 생성 예치·환불·정산 등).
  static void bumpWallet() => walletGeneration.value++;

  /// 구독 상태 세대. 멘토 상세 CTA(질문방으로 / 무료질문)가 구독 여부에 갈리는데,
  /// 구독 자체는 앱 밖(웹)에서 일어난다(Commerce-Zero — 앱 내 결제·구독 진입 없음).
  /// 앱 안에서 구독 상태 변화를 알게 된 지점만 이 세대를 올리고, 각 표면은
  /// 자기 repository 로 서버 정본을 재조회한다(값 미탑재 — walletGeneration 과 동일 계약).
  ///
  /// ★ 앱 밖 변경(웹 구독 완료 후 앱 복귀)은 세대 신호가 올 수 없으므로
  ///   화면 resume 재조회가 정본 경로다 — 이 세대는 그 보완재지 대체재가 아니다.
  static final ValueNotifier<int> subscriptionGeneration =
      ValueNotifier<int>(0);

  /// 구독 상태에 영향을 주는 mutation 성공 지점에서 호출.
  static void bumpSubscription() => subscriptionGeneration.value++;
}
