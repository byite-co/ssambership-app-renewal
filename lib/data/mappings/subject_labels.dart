/// 과목 정본(단일 소스) — 웹 `lib/subjects/subjectCatalog.ts` 와 code/label/parent 를 맞춘다.
///
/// ★ 왜 이 어휘인가(실측): DB `mentor_profiles.teaching_subjects` 는 **정본 코드·한글 라벨·
///   레거시 값이 혼재**할 수 있고(스테이징 실측 2026-07: 현재는 `math`,`math_calculus`
///   같은 코드로 저장), `question_threads.subject` 는 **정본 코드**(예: `math`,`korean`)로
///   저장된다. 과거 이 파일은 이 둘 어디에도 없는 제3의 코드(`math_common` 등)를 써서 A1
///   과목 제한이 항상 전체 폴백되었다(멘토 과목 `수학`을 못 알아봄). 이제 웹 정본과 동일
///   어휘 + 라벨↔코드 정규화로 일치시킨다(코드든 한글 라벨이든 정본 코드로 수렴).
///
/// 화면에는 영문 코드를 노출하지 않는다 — 코드는 [subjectLabel] 로 한글 라벨화한다.
library;

class _Subject {
  const _Subject(this.code, this.label, this.parent, this.sort);
  final String code;
  final String label;
  final String? parent;
  final int sort;
}

/// 웹 SUBJECT_CATALOG 와 1:1 (계층: 대분류 parent=null → 소분류 parent=대분류 code).
const List<_Subject> _catalog = <_Subject>[
  // 국어
  _Subject('korean', '국어', null, 10),
  _Subject('korean_speech_writing', '화법과작문', 'korean', 11),
  _Subject('korean_language_media', '언어와매체', 'korean', 12),
  _Subject('korean_reading', '독서', 'korean', 13),
  _Subject('korean_literature', '문학', 'korean', 14),
  // 영어(단일)
  _Subject('english', '영어', null, 20),
  // 수학
  _Subject('math', '수학', null, 30),
  _Subject('math_1', '수학Ⅰ', 'math', 31),
  _Subject('math_2', '수학Ⅱ', 'math', 32),
  _Subject('math_calculus', '미적분', 'math', 33),
  _Subject('math_statistics', '확률과통계', 'math', 34),
  _Subject('math_geometry', '기하', 'math', 35),
  // 한국사(단일)
  _Subject('korean_history', '한국사', null, 40),
  // 사회
  _Subject('social', '사회', null, 50),
  _Subject('social_life_ethics', '생활과윤리', 'social', 51),
  _Subject('social_ethics_thought', '윤리와사상', 'social', 52),
  _Subject('social_korea_geo', '한국지리', 'social', 53),
  _Subject('social_world_geo', '세계지리', 'social', 54),
  _Subject('social_east_asia_history', '동아시아사', 'social', 55),
  _Subject('social_world_history', '세계사', 'social', 56),
  _Subject('social_economics', '경제', 'social', 57),
  _Subject('social_politics_law', '정치와법', 'social', 58),
  _Subject('social_culture', '사회문화', 'social', 59),
  // 과학
  _Subject('science', '과학', null, 60),
  _Subject('science_physics_1', '물리학Ⅰ', 'science', 61),
  _Subject('science_chemistry_1', '화학Ⅰ', 'science', 62),
  _Subject('science_biology_1', '생명과학Ⅰ', 'science', 63),
  _Subject('science_earth_1', '지구과학Ⅰ', 'science', 64),
  _Subject('science_physics_2', '물리학Ⅱ', 'science', 65),
  _Subject('science_chemistry_2', '화학Ⅱ', 'science', 66),
  _Subject('science_biology_2', '생명과학Ⅱ', 'science', 67),
  _Subject('science_earth_2', '지구과학Ⅱ', 'science', 68),
  // 단일 대분류
  _Subject('essay', '논술·글쓰기', null, 70),
  _Subject('career', '진로·입시', null, 80),
  _Subject('etc', '기타', null, 99),
];

final Map<String, _Subject> _byCode = <String, _Subject>{
  for (final _Subject s in _catalog) s.code: s,
};
final Map<String, String> _labelToCode = <String, String>{
  for (final _Subject s in _catalog) s.label: s.code,
};

/// 레거시/자유입력 라벨 → 정본 code (웹 LEGACY_LABEL_TO_CODE 와 동일 흡수).
const Map<String, String> _legacyLabelToCode = <String, String>{
  '사회·역사': 'social',
  '사회/역사': 'social',
  '역사': 'korean_history',
  '한국사': 'korean_history',
  '미적분': 'math',
  '확률과통계': 'math',
  '확률과 통계': 'math',
  '수학Ⅰ': 'math',
  '수학 I': 'math',
  '수학Ⅱ': 'math',
  '수학 II': 'math',
  '기하': 'math',
  '대수': 'math',
  '물리': 'science',
  '화학': 'science',
};

/// code → 한글 라벨 맵(정본). 외부 호환용(코드 집합 열람).
final Map<String, String> subjectLabels = <String, String>{
  for (final _Subject s in _catalog) s.code: s.label,
};

/// 임의 입력(정본 code / 현재 라벨 / 레거시 라벨) → 정본 code. 못 찾으면 null.
String? normalizeSubjectCode(String? input) {
  if (input == null) return null;
  final String t = input.trim();
  if (t.isEmpty) return null;
  if (_byCode.containsKey(t)) return t;
  return _labelToCode[t] ?? _legacyLabelToCode[t];
}

/// ★ DB 전송용 과목 코드 검증(단일 관문) — 정본 code 또는 null, 자유 문자열 절대 금지.
///
/// 서버(질문 생성 RPC)는 정본 카탈로그에 없는 subject 를 **조용히 NULL 처리**한다
/// (스테이징 실측 2026-07). 자유 라벨을 그대로 보내면 사용자는 과목을 골랐다고
/// 믿지만 DB 에는 미분류로 남는다 → DB 로 보내는 값은 반드시 이 함수를 통과시킨다.
/// 화면 표시는 [subjectLabel] 이 따로 관대하게 처리한다(표시 관용 ≠ 전송 엄격).
String? subjectCodeForDb(String? input) => normalizeSubjectCode(input);

/// 코드/라벨 → 화면용 한글 라벨.
///
/// 정본 코드·한글 라벨은 정본 라벨로, 미매핑이지만 이미 한글(자유 라벨: 예 `코딩`)이면
/// 그대로 표시한다(웹 getSubjectLabel 과 동일 관용). 영문 등 미매핑 코드는 '기타'로 폴백해
/// 화면에 영문 코드가 새지 않게 한다. 빈 값은 '미분류'.
String subjectLabel(String? code) {
  final String t = code?.trim() ?? '';
  if (t.isEmpty) return '미분류';
  final String? norm = normalizeSubjectCode(t);
  if (norm != null) return _byCode[norm]!.label;
  // 미매핑: 한글 등 비ASCII 문자가 있으면 이미 사람이 읽는 라벨 → 그대로. 아니면 '기타'.
  final bool hasNonAscii = t.runes.any((int r) => r > 0x7f);
  return hasNonAscii ? t : '기타';
}

/// 질문 작성 시 노출할 과목 후보 코드(A1 — 멘토 담당 과목만).
///
/// 멘토의 `teaching_subjects`(한글 라벨 `수학` 또는 코드 `math` 혼재 가능)를 정본 코드로
/// 정규화한다. 정규화 안 되는 자유 라벨(예 `코딩`)은 **제외**한다 — 서버가 미정본
/// subject 를 조용히 NULL 처리하므로 후보로 내밀면 안 된다(P2-23). 순서 유지·중복 제거.
/// 정본 후보가 하나도 없으면(미지정·전부 자유 라벨) **전체 과목으로 폴백**한다 — 웹과
/// 동일하게 "정본 지정 과목이 있으면 제한, 없으면 전체 허용"이며 절대 빈 드롭다운으로
/// 막지 않는다.
List<String> restrictQuestionSubjectCodes(List<String> mentorTeachingCodes) {
  final List<String> out = mentorSubjectCodesStrict(mentorTeachingCodes);
  if (out.isNotEmpty) return out;
  // 멘토 미지정 → 전체 폴백(정본 카탈로그 전체, sort 순).
  return subjectLabels.keys.toList();
}

/// 질문 작성 드롭다운 전용 — **해당 멘토의 담당 과목만**(전체 과목 폴백 없음).
///
/// `teaching_subjects`(한글 라벨 `수학` 또는 코드 `math` 혼재)를 [subjectCodeForDb]
/// 로 검증해 **정본 코드만** 돌려준다. 정규화 안 되는 자유 라벨(예 `코딩`)은 제외한다
/// — 이 목록은 그대로 DB 전송 후보가 되는데, 서버는 정본 밖 subject 를 조용히 NULL
/// 처리하므로(스테이징 실측 2026-07) 자유 문자열을 후보로 내밀면 "고른 과목이 사라지는"
/// 버그가 된다(P2-23: 표시 관용 ≠ 전송 엄격). 순서 유지·중복 제거.
/// 정본 후보가 하나도 없으면 **빈 리스트**를 돌려준다(전체 과목을 뿌리지 않음).
List<String> mentorSubjectCodesStrict(List<String> mentorTeachingCodes) {
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  for (final String raw in mentorTeachingCodes) {
    final String? code = subjectCodeForDb(raw); // 정본 code 또는 null
    if (code == null) continue; // 자유 라벨은 DB 전송 후보에서 제외
    if (seen.add(code)) out.add(code);
  }
  return out;
}
