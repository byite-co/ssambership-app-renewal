/// 멘토 연결노트 본문 규약(A-5 §2-2) — 두 질문의 답을 한 본문에 담는다.
///
/// DB `connection_notes.body` 는 자유 문장이다. 앱은 "약점 / 다음에 풀 유형"
/// 두 줄 규약으로 쓰고, 읽을 때는 규약을 따르면 두 항목으로, 아니면 본문
/// 그대로 보여준다(과거 노트·웹 작성 노트와 호환).
library;

const String kMentorNoteWeaknessLabel = '약점';
const String kMentorNoteNextLabel = '다음에 풀 유형';

/// 두 답을 본문으로 합친다. 둘 다 비면 null(저장하지 않는다).
String? composeMentorNote({String? weakness, String? next}) {
  final String w = (weakness ?? '').trim();
  final String n = (next ?? '').trim();
  final List<String> lines = <String>[
    if (w.isNotEmpty) '$kMentorNoteWeaknessLabel: $w',
    if (n.isNotEmpty) '$kMentorNoteNextLabel: $n',
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

/// 본문에서 규약 항목을 뽑는다. 규약이 아니면 [MentorNoteParts.plain] 로 돌려준다.
class MentorNoteParts {
  const MentorNoteParts({this.weakness, this.next, this.plain});

  final String? weakness;
  final String? next;

  /// 규약을 따르지 않는 본문(그대로 표시).
  final String? plain;

  bool get isStructured => weakness != null || next != null;

  /// 한 줄 요약(배너·목록용): 약점 → 다음 유형 → 본문 첫 줄 순.
  String get summary =>
      weakness ?? next ?? (plain ?? '').split('\n').first.trim();

  static MentorNoteParts parse(String? body) {
    final String text = (body ?? '').trim();
    if (text.isEmpty) return const MentorNoteParts(plain: '');
    String? weakness;
    String? next;
    bool structured = false;
    for (final String raw in text.split('\n')) {
      final String line = raw.trim();
      if (line.startsWith('$kMentorNoteWeaknessLabel:')) {
        weakness = line.substring(kMentorNoteWeaknessLabel.length + 1).trim();
        structured = true;
      } else if (line.startsWith('$kMentorNoteNextLabel:')) {
        next = line.substring(kMentorNoteNextLabel.length + 1).trim();
        structured = true;
      } else if (line.isNotEmpty) {
        structured = false;
        break;
      }
    }
    if (!structured) return MentorNoteParts(plain: text);
    return MentorNoteParts(
      weakness: (weakness ?? '').isEmpty ? null : weakness,
      next: (next ?? '').isEmpty ? null : next,
    );
  }
}
