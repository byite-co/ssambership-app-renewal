import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';

/// D-10: 개별질문 스레드 메시지의 작성자 방향 판정(순수 로직).
///
/// 서버 정본이 `auth.uid()` 를 멘토 신원과 대조한 뒤 같은 uid 를 author_id 로
/// 저장하므로, 질문 행의 student_id / claimed_mentor_id 와 직접 비교할 수 있다.
void main() {
  group('iqMessageAuthorOf', () {
    test('author_id == student_id → 학생', () {
      expect(
        iqMessageAuthorOf(authorId: 's1', studentId: 's1', mentorId: 'm1'),
        IqMessageAuthor.student,
      );
    });

    test('author_id == mentor_id → 멘토', () {
      expect(
        iqMessageAuthorOf(authorId: 'm1', studentId: 's1', mentorId: 'm1'),
        IqMessageAuthor.mentor,
      );
    });

    test('제3자(관리자·시스템) → unknown (한쪽으로 몰아붙이지 않는다)', () {
      expect(
        iqMessageAuthorOf(authorId: 'x9', studentId: 's1', mentorId: 'm1'),
        IqMessageAuthor.unknown,
      );
    });

    test('author_id 빈 문자열 → unknown', () {
      expect(
        iqMessageAuthorOf(authorId: '', studentId: 's1', mentorId: 'm1'),
        IqMessageAuthor.unknown,
      );
    });

    test('student_id 가 빈 문자열이어도 빈 author_id 와 매칭되지 않는다', () {
      // 둘 다 null 을 '' 로 접기 때문에 순진한 비교는 여기서 학생으로 오분류된다.
      expect(
        iqMessageAuthorOf(authorId: '', studentId: '', mentorId: null),
        IqMessageAuthor.unknown,
      );
    });

    test('공백만 있는 author_id → unknown', () {
      expect(
        iqMessageAuthorOf(authorId: '   ', studentId: 's1', mentorId: 'm1'),
        IqMessageAuthor.unknown,
      );
    });

    test('mentor_id 가 null(미클레임 공개형) → 멘토 판정 불가', () {
      expect(
        iqMessageAuthorOf(authorId: 'm1', studentId: 's1', mentorId: null),
        IqMessageAuthor.unknown,
      );
      // 같은 상황에서 학생 판정은 계속 정상 동작한다.
      expect(
        iqMessageAuthorOf(authorId: 's1', studentId: 's1', mentorId: null),
        IqMessageAuthor.student,
      );
    });

    test('IqMessage.authorId 를 그대로 넣어도 동작한다(파싱 경로 정합)', () {
      final IqMessage m = IqMessage.fromMap(<String, dynamic>{
        'id': 'msg1',
        'question_id': 'q1',
        'author_id': 'm1',
        'body': '답변입니다',
      });
      expect(
        iqMessageAuthorOf(
            authorId: m.authorId, studentId: 's1', mentorId: 'm1'),
        IqMessageAuthor.mentor,
      );
    });

    test('author_id 키가 아예 없는 레거시 행 → unknown', () {
      final IqMessage m = IqMessage.fromMap(<String, dynamic>{
        'id': 'msg1',
        'question_id': 'q1',
        'body': '본문',
      });
      expect(
        iqMessageAuthorOf(
            authorId: m.authorId, studentId: 's1', mentorId: 'm1'),
        IqMessageAuthor.unknown,
      );
    });
  });

  group('iqMessageAuthorLabel — 내부 id·영문 코드 비노출', () {
    test('한글 라벨만 돌려준다', () {
      expect(iqMessageAuthorLabel(IqMessageAuthor.student), '학생');
      expect(iqMessageAuthorLabel(IqMessageAuthor.mentor), '멘토');
      expect(iqMessageAuthorLabel(IqMessageAuthor.unknown), '작성자 미확인');
    });

    test('미확인은 학생·멘토 어느 쪽으로도 표기하지 않는다', () {
      final String s = iqMessageAuthorLabel(IqMessageAuthor.unknown);
      expect(s, isNot('학생'));
      expect(s, isNot('멘토'));
    });
  });

  group('iqMessageIsMine — 모를 때는 null(false 아님)', () {
    test('내 uid 와 일치 → true', () {
      expect(iqMessageIsMine(authorId: 'u1', viewerId: 'u1'), isTrue);
    });

    test('다른 uid → false', () {
      expect(iqMessageIsMine(authorId: 'u2', viewerId: 'u1'), isFalse);
    });

    test('뷰어 uid 없음(비로그인·미초기화) → null', () {
      expect(iqMessageIsMine(authorId: 'u1', viewerId: null), isNull);
    });

    test('author_id 미기록 → null', () {
      expect(iqMessageIsMine(authorId: '', viewerId: 'u1'), isNull);
    });
  });

  group('iqReadOnlyNotice', () {
    test('환불·만료·취소는 안내 문구가 있다', () {
      for (final IndividualQuestionStatus s in <IndividualQuestionStatus>[
        IndividualQuestionStatus.refunded,
        IndividualQuestionStatus.expired,
        IndividualQuestionStatus.canceled,
      ]) {
        expect(iqReadOnlyNotice(s), isNotNull, reason: '$s 안내 문구 누락');
        expect(iqReadOnlyNotice(s)!.trim(), isNotEmpty);
      }
    });

    test('진행 중·완료 상태는 null (기존 문구가 따로 있다)', () {
      for (final IndividualQuestionStatus s in <IndividualQuestionStatus>[
        IndividualQuestionStatus.escrowed,
        IndividualQuestionStatus.open,
        IndividualQuestionStatus.assigned,
        IndividualQuestionStatus.claimed,
        IndividualQuestionStatus.answered,
        IndividualQuestionStatus.released,
        IndividualQuestionStatus.unknown,
      ]) {
        expect(iqReadOnlyNotice(s), isNull, reason: '$s 는 null 이어야 한다');
      }
    });
  });
}
