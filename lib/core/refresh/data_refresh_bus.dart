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
}
