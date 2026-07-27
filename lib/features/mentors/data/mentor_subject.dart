import '../../../data/mappings/subject_labels.dart';

/// 멘토 지도 과목 1건의 3분리 계약 — 화면 표시(label) · 필터 비교(key) · 검색(raw) 분리.
///
/// DB `mentor_profiles.teaching_subjects` 는 정본 코드(`math`)·한글 라벨(`수학`)·레거시
/// 값이 혼재할 수 있다(스테이징 실측: 현재는 코드 저장). 어느 경우든:
/// - [label] : 화면용 한글(정본 라벨 / 한글 자유 라벨 그대로 / 미매핑 ASCII 는 '기타').
/// - [key]   : 필터·중복제거용 canonical identity(정본 code 또는 안전한 라벨 identity).
/// - [raw]   : 원본 문자열(검색 호환용 — 화면에 직접 노출하지 않는다).
class MentorSubject {
  const MentorSubject({
    required this.key,
    required this.label,
    required this.raw,
  });

  /// 필터 비교·중복 제거 identity. 정본 코드(`math`) 또는 미매핑 라벨 identity.
  final String key;

  /// 화면 표시용 한글 라벨.
  final String label;

  /// DB 원본 값(검색 haystack 호환용, 화면 직접 노출 금지).
  final String raw;

  /// 임의 raw 값 → 표시/필터/검색 3분리 계약으로 변환.
  factory MentorSubject.fromRaw(String raw) {
    final String trimmed = raw.trim();
    final String? code = normalizeSubjectCode(trimmed);
    if (code != null) {
      // 정본 코드/라벨/레거시 라벨 → 정본 code 를 key, 정본 라벨을 표시.
      return MentorSubject(key: code, label: subjectLabel(code), raw: trimmed);
    }
    // 미매핑: 한글 자유 라벨(예 `코딩`)은 그대로, ASCII 미지 코드는 '기타'.
    final String label = subjectLabel(trimmed);
    // 미매핑 ASCII 여러 개는 모두 '기타' → 동일 key('etc')로 수렴해 칩이 중복되지 않게 한다.
    final String key = label == '기타' ? 'etc' : label;
    return MentorSubject(key: key, label: label, raw: trimmed);
  }
}

/// raw 과목 목록 → canonical 과목 목록.
///
/// 입력 순서를 보존하면서 [MentorSubject.key] 기준으로 중복을 제거하고 빈 값은 제외한다.
/// (`수학`+`math` → 1개, 미매핑 ASCII 여러 개 → '기타' 1개.)
List<MentorSubject> canonicalizeSubjects(Iterable<String> raw) {
  final List<MentorSubject> out = <MentorSubject>[];
  final Set<String> seen = <String>{};
  for (final String r in raw) {
    if (r.trim().isEmpty) continue;
    final MentorSubject s = MentorSubject.fromRaw(r);
    if (seen.add(s.key)) out.add(s);
  }
  return out;
}
