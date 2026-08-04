import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachment_grouping.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';

/// §2-1·§3 첨부 귀속 그룹(순수 함수) — message_id 정본, 업로더 기록 기반 분류,
/// 작성자 추측 금지, created_at 안정 정렬.
const String kStudent = 's1';
const String kMentor = 'm1';

IqMessage _msg(String id, String authorId, {int minute = 0}) => IqMessage(
      id: id,
      questionId: 'q1',
      authorId: authorId,
      body: '본문 $id',
      createdAt: DateTime(2026, 7, 2, 10, minute),
    );

IqAttachment _att(
  String id, {
  String? messageId,
  String? authorId,
  int? minute,
}) =>
    IqAttachment(
      id: id,
      storagePath: 'q1/$id.png',
      messageId: messageId,
      authorId: authorId,
      fileName: '$id.png',
      mimeType: 'image/png',
      createdAt: minute == null ? null : DateTime(2026, 7, 2, 11, minute),
    );

IqAttachmentGroups _build(
  List<IqAttachment> attachments, {
  List<IqMessage> messages = const <IqMessage>[],
  String studentId = kStudent,
  String? mentorId = kMentor,
}) =>
    IqAttachmentGroups.build(
      attachments: attachments,
      messages: messages,
      studentId: studentId,
      mentorId: mentorId,
    );

void main() {
  group('message_id 연결 — 메시지 그룹 정본', () {
    test('메시지에 연결된 첨부는 그 메시지 그룹으로만 간다', () {
      final IqAttachmentGroups g = _build(
        <IqAttachment>[
          _att('a1', messageId: 'm-1', authorId: kStudent),
          _att('a2', messageId: 'm-2', authorId: kMentor),
        ],
        messages: <IqMessage>[_msg('m-1', kStudent), _msg('m-2', kMentor)],
      );

      expect(g.forMessage('m-1').map((IqAttachment a) => a.id), <String>['a1']);
      expect(g.forMessage('m-2').map((IqAttachment a) => a.id), <String>['a2']);
      expect(g.initialQuestion, isEmpty);
      expect(g.unlinkedMentor, isEmpty);
      expect(g.legacyUnknown, isEmpty);
    });

    test('연결 메시지가 목록에 없으면(방어) 업로더 기록으로 폴백한다', () {
      final IqAttachmentGroups g = _build(
        <IqAttachment>[_att('a1', messageId: 'ghost', authorId: kMentor)],
      );
      expect(g.unlinkedMentor.single.id, 'a1');
    });

    test('없는 메시지 조회는 빈 목록(널 아님)', () {
      expect(_build(const <IqAttachment>[]).forMessage('nope'), isEmpty);
    });
  });

  group('미연결 첨부 — 업로더 기록으로만 분류(추측 금지)', () {
    test('학생 작성 → 최초 질문 그룹', () {
      final IqAttachmentGroups g =
          _build(<IqAttachment>[_att('a1', authorId: kStudent)]);
      expect(g.initialQuestion.single.id, 'a1');
      expect(g.legacyUnknown, isEmpty);
    });

    test('담당 멘토 작성 → 멘토 미연결 그룹(학생 말풍선 금지)', () {
      final IqAttachmentGroups g =
          _build(<IqAttachment>[_att('a1', authorId: kMentor)]);
      expect(g.unlinkedMentor.single.id, 'a1');
      expect(g.initialQuestion, isEmpty);
    });

    test('업로더 미기록(레거시) → 중립 그룹 — 학생·멘토 어느 쪽도 아니다', () {
      final IqAttachmentGroups g = _build(<IqAttachment>[_att('legacy')]);
      expect(g.legacyUnknown.single.id, 'legacy');
      expect(g.initialQuestion, isEmpty);
      expect(g.unlinkedMentor, isEmpty);
    });

    test('당사자가 아닌 업로더 uid → 중립 그룹(임의 매칭 금지)', () {
      final IqAttachmentGroups g =
          _build(<IqAttachment>[_att('a1', authorId: 'x9')]);
      expect(g.legacyUnknown.single.id, 'a1');
    });

    test('빈 studentId 는 절대 매칭하지 않는다 — 미기록 행 오분류 방지', () {
      final IqAttachmentGroups g = _build(
        <IqAttachment>[_att('legacy')],
        studentId: '',
      );
      expect(g.legacyUnknown.single.id, 'legacy');
      expect(g.initialQuestion, isEmpty);
    });

    test('mentorId null(미클레임) — 멘토 단정 없이 중립', () {
      final IqAttachmentGroups g = _build(
        <IqAttachment>[_att('a1', authorId: kMentor)],
        mentorId: null,
      );
      expect(g.legacyUnknown.single.id, 'a1');
    });
  });

  group('정렬 — created_at 오름차순·미상은 입력 순서 유지(안정)', () {
    test('원본이 먼저, 첨삭본이 뒤(작성순)', () {
      final IqAttachmentGroups g = _build(<IqAttachment>[
        _att('later', authorId: kStudent, minute: 5),
        _att('earlier', authorId: kStudent, minute: 1),
      ]);
      expect(g.initialQuestion.map((IqAttachment a) => a.id),
          <String>['earlier', 'later']);
    });

    test('시각 미상 행이 섞여도 결정적(입력 순서 유지)', () {
      final IqAttachmentGroups g = _build(<IqAttachment>[
        _att('n1', authorId: kStudent),
        _att('n2', authorId: kStudent),
        _att('t1', authorId: kStudent, minute: 3),
      ]);
      expect(g.initialQuestion.map((IqAttachment a) => a.id),
          <String>['n1', 'n2', 't1']);
    });
  });

  group('iqAttachmentAuthorOf — 첨삭 대상(학생 작성) 판정', () {
    final Map<String, IqMessage> byId = <String, IqMessage>{
      'm-s': _msg('m-s', kStudent),
      'm-m': _msg('m-m', kMentor),
    };

    IqMessageAuthor call(IqAttachment a) => iqAttachmentAuthorOf(
          attachment: a,
          messagesById: byId,
          studentId: kStudent,
          mentorId: kMentor,
        );

    test('연결 메시지 작성자 우선 — 메시지 정본', () {
      expect(call(_att('a', messageId: 'm-s')), IqMessageAuthor.student);
      expect(call(_att('a', messageId: 'm-m')), IqMessageAuthor.mentor);
    });

    test('미연결이면 업로더 기록', () {
      expect(call(_att('a', authorId: kStudent)), IqMessageAuthor.student);
      expect(call(_att('a', authorId: kMentor)), IqMessageAuthor.mentor);
    });

    test('아무 기록도 없으면 unknown — 추측 금지', () {
      expect(call(_att('a')), IqMessageAuthor.unknown);
    });
  });
}
