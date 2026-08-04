import 'models/individual_question_models.dart';

/// 첨부 귀속 그룹 — 대화 타임라인 렌더 전에 **한 번만** 만든다(매 build 검색 금지).
///
/// 귀속 규칙(증거 기반 — 추측 금지):
/// 1. `message_id` 가 있고 그 메시지가 이 질문의 메시지 목록에 있으면 해당
///    메시지 그룹([byMessageId]) — 표시 방향은 메시지 작성자를 따른다.
/// 2. `message_id` 가 있는데 메시지 목록에 없으면 **fail-closed** —
///    [unresolvedMessage] 중립 그룹('연결 메시지 미확인'). 업로더 기록으로
///    재분류하지 않는다: 연결 메시지가 정본인데 그 정본을 확인할 수 없는
///    상태(로드 공백·향후 pagination)에서 다른 위치에 붙이면 재조회 후
///    귀속이 '이동'하는 것으로 보인다.
/// 3. 미연결(`message_id = null`)이면 서버가 기록한 업로더([IqAttachment.authorId],
///    `auth.uid()` 정본)로만 분류한다:
///    - 학생 작성 → [initialQuestion] (최초 질문 말풍선의 학생 첨부)
///    - 담당 멘토 작성 → [unlinkedMentor] (멘토 방향 별도 그룹 — 구버전 앱이
///      메시지 연결 없이 등록한 멘토 첨부·첨삭본)
///    - 업로더 미기록·당사자 불일치 → [legacyUnknown] (중립 그룹 —
///      '이전 첨부 · 작성자 미확인'. 학생·멘토 어느 쪽에도 넣지 않는다)
/// 4. 파일명·시간 근접값·정렬 순서로 작성자를 추측하지 않는다. 백필도 없다.
///
/// 각 그룹은 `created_at` 오름차순(미상은 입력 순서 유지)으로 정렬된다 —
/// 원본이 먼저, 이후 첨삭본이 뒤에 붙는 작성순.
class IqAttachmentGroups {
  IqAttachmentGroups._({
    required this.byMessageId,
    required this.initialQuestion,
    required this.unlinkedMentor,
    required this.legacyUnknown,
    required this.unresolvedMessage,
  });

  /// message_id → 그 메시지에 연결된 첨부(작성순).
  final Map<String, List<IqAttachment>> byMessageId;

  /// 최초 질문 말풍선에 붙는 학생 작성·미연결 첨부(작성순).
  final List<IqAttachment> initialQuestion;

  /// 담당 멘토 작성·미연결 첨부(작성순) — 멘토 방향 별도 그룹으로 표시.
  final List<IqAttachment> unlinkedMentor;

  /// 작성자 미확인 레거시 첨부(작성순) — 중립 그룹으로만 표시.
  final List<IqAttachment> legacyUnknown;

  /// message_id 는 있으나 현재 메시지 목록에서 확인되지 않는 첨부(작성순) —
  /// fail-closed 중립 그룹('연결 메시지 미확인'). 재조회로 메시지가 확인되면
  /// 자연히 해당 메시지 그룹으로 수렴한다.
  final List<IqAttachment> unresolvedMessage;

  factory IqAttachmentGroups.build({
    required List<IqAttachment> attachments,
    required List<IqMessage> messages,
    required String studentId,
    required String? mentorId,
  }) {
    final Set<String> messageIds =
        messages.map((IqMessage m) => m.id).toSet();
    final Map<String, List<IqAttachment>> byMessage =
        <String, List<IqAttachment>>{};
    final List<IqAttachment> initial = <IqAttachment>[];
    final List<IqAttachment> mentor = <IqAttachment>[];
    final List<IqAttachment> unknown = <IqAttachment>[];
    final List<IqAttachment> unresolved = <IqAttachment>[];

    for (final IqAttachment a in attachments) {
      final String? mid = a.messageId;
      if (mid != null) {
        if (messageIds.contains(mid)) {
          (byMessage[mid] ??= <IqAttachment>[]).add(a);
        } else {
          // fail-closed: 연결 메시지가 정본인데 현재 목록에서 확인되지 않는다
          // (로드 공백·향후 pagination) — 업로더 기반 재분류 없이 중립 유지.
          unresolved.add(a);
        }
        continue;
      }
      // 미연결(message_id = null) → 업로더 정본 판정.
      switch (iqMessageAuthorOf(
        authorId: a.authorId ?? '',
        studentId: studentId,
        mentorId: mentorId,
      )) {
        case IqMessageAuthor.student:
          initial.add(a);
        case IqMessageAuthor.mentor:
          mentor.add(a);
        case IqMessageAuthor.unknown:
          unknown.add(a);
      }
    }

    _sortByCreatedAt(initial);
    _sortByCreatedAt(mentor);
    _sortByCreatedAt(unknown);
    _sortByCreatedAt(unresolved);
    for (final List<IqAttachment> list in byMessage.values) {
      _sortByCreatedAt(list);
    }
    return IqAttachmentGroups._(
      byMessageId: byMessage,
      initialQuestion: initial,
      unlinkedMentor: mentor,
      legacyUnknown: unknown,
      unresolvedMessage: unresolved,
    );
  }

  /// 메시지에 연결된 첨부. 없으면 빈 목록(널 대신 — 호출부 단순화).
  List<IqAttachment> forMessage(String messageId) =>
      byMessageId[messageId] ?? const <IqAttachment>[];

  /// created_at 오름차순 **안정** 정렬 — 시각 미상·동률은 입력 순서 유지.
  /// (List.sort 는 불안정하므로 입력 인덱스를 타이브레이커로 쓴다.)
  static void _sortByCreatedAt(List<IqAttachment> list) {
    final Map<IqAttachment, int> order = <IqAttachment, int>{
      for (int i = 0; i < list.length; i++) list[i]: i,
    };
    list.sort((IqAttachment a, IqAttachment b) {
      final int c = (a.createdAt ?? _epoch).compareTo(b.createdAt ?? _epoch);
      if (c != 0) return c;
      return (order[a] ?? 0).compareTo(order[b] ?? 0);
    });
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
}

/// 첨부 1건의 작성자 방향 — 연결 메시지 작성자 우선, 미연결이면 업로더 기록.
/// 화면의 '학생 작성 첨부인가'(첨삭 대상 판정) 등에 쓴다.
IqMessageAuthor iqAttachmentAuthorOf({
  required IqAttachment attachment,
  required Map<String, IqMessage> messagesById,
  required String studentId,
  required String? mentorId,
}) {
  final String? mid = attachment.messageId;
  final IqMessage? linked = mid == null ? null : messagesById[mid];
  return iqMessageAuthorOf(
    authorId: linked?.authorId ?? attachment.authorId ?? '',
    studentId: studentId,
    mentorId: mentorId,
  );
}
