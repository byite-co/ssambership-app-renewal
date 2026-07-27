import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mentors/data/mentor_subject.dart';

/// 멘토 지도 과목 canonical 계약(순수 — DB·네트워크 미접촉).
///
/// ★ 새 계약: `teaching_subjects` 는 canonical 코드(`math`)·한글 라벨(`수학`)·레거시
///   값이 혼재할 수 있으며, 앱은 이를 정규화해 화면에 한글로 표시한다. (구계약
///   "DB 과목은 항상 한글" 은 폐기 — 스테이징 실측: 현재는 코드로 저장된다.)
void main() {
  test('code → 표시 라벨 한글 (math=수학) · raw 는 원본 보존(화면 비노출)', () {
    final MentorSubject s = MentorSubject.fromRaw('math');
    expect(s.label, '수학');
    expect(s.key, 'math');
    expect(s.raw, 'math'); // raw 는 검색 호환용으로만 보존
  });

  test('세부 과목 코드 math_calculus → 미적분', () {
    final MentorSubject s = MentorSubject.fromRaw('math_calculus');
    expect(s.label, '미적분');
    expect(s.key, 'math_calculus');
  });

  test('수학 + math + 수학 → key 기준 1개(순서 보존)', () {
    final List<MentorSubject> out =
        canonicalizeSubjects(<String>['수학', 'math', '수학']);
    expect(out.length, 1);
    expect(out.single.key, 'math');
    expect(out.single.label, '수학');
  });

  test('미매핑 ASCII 코드 → 표시 기타 · raw 는 화면 라벨로 새지 않음', () {
    final MentorSubject s = MentorSubject.fromRaw('unknown_subject');
    expect(s.label, '기타');
    expect(s.label, isNot('unknown_subject')); // raw code 가 라벨로 노출되지 않음
    expect(s.raw, 'unknown_subject'); // raw 는 내부(검색)용으로만 보존
  });

  test('한글 자유 라벨(코딩)은 그대로 표시', () {
    final MentorSubject s = MentorSubject.fromRaw('코딩');
    expect(s.label, '코딩');
    expect(s.key, '코딩');
  });

  test('미지 ASCII 여러 개는 모두 기타 → 칩 1개로 수렴(중복 없음)', () {
    final List<MentorSubject> out =
        canonicalizeSubjects(<String>['unknown_one', 'another_unknown', 'zzz']);
    expect(out.length, 1);
    expect(out.single.label, '기타');
  });

  test('빈 값·공백은 제외', () {
    final List<MentorSubject> out =
        canonicalizeSubjects(<String>['', '  ', '\t', 'math']);
    expect(out.length, 1);
    expect(out.single.label, '수학');
  });

  test('입력 순서 보존(영어→수학)', () {
    final List<MentorSubject> out =
        canonicalizeSubjects(<String>['english', 'math']);
    expect(
        out.map((MentorSubject s) => s.label).toList(), <String>['영어', '수학']);
  });
}
