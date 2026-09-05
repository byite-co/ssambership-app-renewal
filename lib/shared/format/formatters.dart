/// 표시 포맷터. (가격/캐시 포맷은 Commerce-Zero 원칙상 결제에 쓰지 않으며,
/// 잔액 '표시'가 필요할 때만 사용. 미확정 동안은 키만 유지.)
library;

class Formatters {
  Formatters._();

  /// 날짜 한글 표기(간단). 추후 intl 도입 시 교체.
  static String koreanDate(DateTime dt) {
    return '${dt.year}년 ${dt.month}월 ${dt.day}일';
  }

  /// 짧은 날짜(M/D). 갱신일 등 칩/캡션용.
  static String shortDate(DateTime dt) => '${dt.month}/${dt.day}';

  /// '9월 5일' — 문장 안에 넣는 날짜(예: '9월 5일까지', '9월 9일에 갱신돼요').
  static String monthDay(DateTime dt) => '${dt.month}월 ${dt.day}일';

  /// 요일 — '목요일'.
  static String weekday(DateTime dt) =>
      const <String>['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'][
          dt.weekday - 1];

  /// 상대 시간(방금/N분 전/N시간 전/N일 전/그 이전은 날짜). 채팅·목록 활동시각용.
  static String relativeKorean(DateTime dt, {DateTime? now}) {
    final DateTime ref = now ?? DateTime.now();
    final Duration d = ref.difference(dt);
    if (d.inSeconds < 60) return '방금';
    if (d.inMinutes < 60) return '${d.inMinutes}분 전';
    if (d.inHours < 24) return '${d.inHours}시간 전';
    if (d.inDays < 7) return '${d.inDays}일 전';
    return koreanDate(dt);
  }

  /// 시:분(24h). 채팅 말풍선 시각용.
  static String hourMinute(DateTime dt) {
    final String hh = dt.hour.toString().padLeft(2, '0');
    final String mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// '2026년 7월 25일 15:30' — 서버가 준 마감 시각 표시용(기기 로컬로 변환).
  /// 탈퇴 취소 마감(`cancelable_until`)처럼 **서버 정본 시각**을 그릴 때만 쓴다.
  /// 클라이언트에서 마감을 계산하지 않는다.
  static String dateTimeMinute(DateTime dt) {
    final DateTime local = dt.toLocal();
    return '${koreanDate(local)} ${hourMinute(local)}';
  }
}
