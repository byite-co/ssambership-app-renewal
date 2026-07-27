import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/data/mappings/subject_labels.dart';

/// A1: 질문 과목 후보 제한 규칙(순수 함수, DB·네트워크 미접촉).
///
/// ★ 계약(2026-07 갱신): DB `mentor_profiles.teaching_subjects` 는 canonical 코드
///   (`math`)·한글 라벨(`수학`)·레거시 값이 **혼재**할 수 있다(구가정 "항상 한글" 폐기 —
///   스테이징 실측상 현재는 코드로 저장). 앱은 이를 정본 코드로 정규화해 제한하며,
///   아래는 코드 입력·라벨 입력 어느 쪽이든 동일하게 제한됨을 검증한다.
void main() {
  test('멘토 담당과목이 한글 라벨(수학·영어)이면 그 과목만 후보로 정규화(math·english)', () {
    // 로컬 실데이터: mentor 5b6dc968… teaching_subjects = {수학,영어}
    final List<String> out = restrictQuestionSubjectCodes(<String>['수학', '영어']);
    expect(out, <String>['math', 'english']);
    // 전체 폴백이 아님을 명시(핵심: 화면에 전체가 뜨면 안 됨)
    expect(out.length, lessThan(subjectLabels.length));
    expect(subjectLabel(out[0]), '수학');
    expect(subjectLabel(out[1]), '영어');
  });

  test('멘토 담당과목이 코드(math·math_calculus)여도 그대로 제한', () {
    final List<String> out =
        restrictQuestionSubjectCodes(<String>['math', 'math_calculus']);
    expect(out, <String>['math', 'math_calculus']);
    expect(out.length, lessThan(subjectLabels.length));
  });

  test('한글 라벨과 코드가 같은 과목이면 중복 제거(수학=math)', () {
    final List<String> out =
        restrictQuestionSubjectCodes(<String>['수학', 'math', '수학']);
    expect(out, <String>['math']);
  });

  test('정규화 안 되는 자유 라벨(코딩)은 DB 전송 후보에서 제외(P2-23)', () {
    // ★ 서버는 정본 밖 subject 를 조용히 NULL 처리한다(스테이징 실측 2026-07).
    //   자유 라벨을 후보로 내밀면 "고른 과목이 사라지는" 버그 → 전송 후보에서 뺀다.
    final List<String> out = restrictQuestionSubjectCodes(<String>['수학', '코딩']);
    expect(out, <String>['math']);
    expect(subjectLabel('코딩'), '코딩'); // 표시(관대)는 그대로 — 전송(엄격)과 분리
    expect(out.length, lessThan(subjectLabels.length));
  });

  test('전부 자유 라벨이면 정본 후보 없음 → restrict 는 전체 폴백(빈 드롭다운 금지)', () {
    expect(mentorSubjectCodesStrict(<String>['코딩', '바리스타']), <String>[]);
    expect(restrictQuestionSubjectCodes(<String>['코딩']),
        subjectLabels.keys.toList());
  });

  test('빈 값이면 전체 과목으로 폴백(빈 드롭다운 금지)', () {
    final List<String> out = restrictQuestionSubjectCodes(<String>[]);
    expect(out, subjectLabels.keys.toList());
    expect(out.isNotEmpty, isTrue);
  });

  test('공백만 있으면 전체 폴백', () {
    final List<String> out = restrictQuestionSubjectCodes(<String>['  ', '\t']);
    expect(out, subjectLabels.keys.toList());
  });

  test('mentorSubjectCodesStrict: 멘토 담당 과목만 + 정본 코드만(전체 폴백 없음)', () {
    // 지정 과목이 있으면 그 과목만 정규화.
    expect(mentorSubjectCodesStrict(<String>['수학', '영어']),
        <String>['math', 'english']);
    // ★ 핵심: 미지정(빈 입력)이면 전체가 아니라 빈 리스트 → 드롭다운엔 '선택 안 함'만.
    expect(mentorSubjectCodesStrict(<String>[]), <String>[]);
    expect(mentorSubjectCodesStrict(<String>['  ', '\t']), <String>[]);
    // 중복 제거 + 자유 라벨 제외(정본 코드만 DB 전송 후보).
    expect(mentorSubjectCodesStrict(<String>['수학', 'math', '코딩']),
        <String>['math']);
  });

  test('subjectCodeForDb: 정본 code 또는 null — 자유 문자열을 절대 돌려주지 않음', () {
    expect(subjectCodeForDb('math'), 'math'); // 정본 코드 그대로
    expect(subjectCodeForDb('수학'), 'math'); // 현재 라벨 → 코드
    expect(subjectCodeForDb('물리'), 'science'); // 레거시 라벨 → 코드
    expect(subjectCodeForDb('사회·역사'), 'social'); // 레거시 라벨 → 코드
    expect(subjectCodeForDb('코딩'), isNull); // 자유 라벨 → null(전송 금지)
    expect(subjectCodeForDb('not_a_code'), isNull);
    expect(subjectCodeForDb(''), isNull);
    expect(subjectCodeForDb(null), isNull);
  });

  test('정본 35개 코드 전부 왕복(코드→라벨→코드) + DB 전송 검증 통과', () {
    expect(subjectLabels.length, 35); // 서버 정본 카탈로그(2026-07 실측)와 동수
    for (final MapEntry<String, String> e in subjectLabels.entries) {
      expect(subjectLabel(e.key), e.value); // 코드 → 정본 라벨
      expect(normalizeSubjectCode(e.value), e.key); // 라벨 → 코드 왕복
      expect(subjectCodeForDb(e.key), e.key); // 정본 코드는 전송 검증 통과
    }
  });

  test('subjectLabel(표시)은 관대 유지: 정본 라벨화·한글 자유 라벨 통과·영문 미매핑 기타', () {
    expect(subjectLabel('math'), '수학'); // 과거엔 '기타'로 나오던 버그
    expect(subjectLabel('korean'), '국어');
    expect(subjectLabel('english'), '영어');
    expect(subjectLabel('코딩'), '코딩'); // 한글 자유 라벨은 그대로(전송과 무관)
    expect(subjectLabel('unknown_ascii_code'), '기타');
    expect(subjectLabel(null), '미분류');
    expect(subjectLabel('   '), '미분류');
  });
}
