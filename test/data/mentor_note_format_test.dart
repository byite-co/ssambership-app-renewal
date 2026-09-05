import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/connection_note_errors.dart';
import 'package:ssambership_app/features/question_room/data/mentor_note_format.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A-5 연결노트 — 멘토 노트 본문 규약(두 질문) · 23505(UNIQUE 잔존) 문구 매핑.
void main() {
  group('composeMentorNote / MentorNoteParts', () {
    test('두 답 → 두 줄 규약, 하나만 있으면 한 줄, 둘 다 비면 null', () {
      expect(
        composeMentorNote(weakness: ' 분모 조건을 놓쳐요 ', next: '좌·우극한 문제'),
        '약점: 분모 조건을 놓쳐요\n다음에 풀 유형: 좌·우극한 문제',
      );
      expect(composeMentorNote(weakness: '분모 조건'), '약점: 분모 조건');
      expect(composeMentorNote(next: '그래프 해석'), '다음에 풀 유형: 그래프 해석');
      expect(composeMentorNote(weakness: '  ', next: ''), isNull);
    });

    test('규약 본문은 두 항목으로, 자유 본문은 그대로', () {
      final MentorNoteParts p =
          MentorNoteParts.parse('약점: 분모 조건\n다음에 풀 유형: 그래프');
      expect(p.isStructured, isTrue);
      expect(p.weakness, '분모 조건');
      expect(p.next, '그래프');
      expect(p.summary, '분모 조건');

      final MentorNoteParts free = MentorNoteParts.parse('공식은 외웠는데\n조건을 안 봤다');
      expect(free.isStructured, isFalse);
      expect(free.plain, '공식은 외웠는데\n조건을 안 봤다');
      expect(free.summary, '공식은 외웠는데');

      expect(MentorNoteParts.parse(null).summary, '');
    });
  });

  group('mapNoteInsertError', () {
    test('23505 → 지시서 문구(이미 남긴 노트가 있어요…)', () {
      final Object e = mapNoteInsertError(
        const PostgrestException(message: 'duplicate key', code: '23505'),
      );
      expect(e, isA<NoteAlreadyExistsError>());
      expect((e as AppError).userMessage, kNoteAlreadyExistsMessage);
      expect(kNoteAlreadyExistsMessage, '이미 남긴 노트가 있어요. 곧 여러 개를 남길 수 있게 돼요');
    });

    test('그 외 qna 코드는 공통 매핑, 미지 예외는 그대로', () {
      final Object mapped = mapNoteInsertError(
        const PostgrestException(message: 'NOT_ROOM_PARTY', code: 'P0001'),
      );
      expect(mapped, isA<AppError>());
      expect((mapped as AppError).userMessage, '이 질문방에서 할 수 없는 동작이에요.');
      final Object raw = Exception('x');
      expect(identical(mapNoteInsertError(raw), raw), isTrue);
    });
  });
}
