import '../../mentors/format/mentor_price_format.dart';

/// 정산 화면 표시 포맷 — cents 원문을 원 단위로 바꾸기만 한다(재계산 0).
String settlementWon(int cents) => formatWon(cents ~/ 100);

/// 'YYYY-MM-DD' → 'M월 D일'. 형식이 다르면 원문.
String settlementRunDateLabel(String ymd) {
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd);
  if (m == null) return ymd;
  return '${int.parse(m.group(2)!)}월 ${int.parse(m.group(3)!)}일';
}

/// 'YYYY-MM' → 'YYYY년 M월'. 형식이 다르면 원문.
String settlementMonthLabel(String ym) {
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(ym);
  if (m == null) return ym;
  return '${m.group(1)}년 ${int.parse(m.group(2)!)}월';
}

/// 로컬 시각 → 'M/D'.
String settlementShortDate(DateTime dt) => '${dt.month}/${dt.day}';

/// 로컬 시각 → 'YYYY년 M월'(월 그룹 헤더).
String settlementMonthOf(DateTime dt) => '${dt.year}년 ${dt.month}월';
