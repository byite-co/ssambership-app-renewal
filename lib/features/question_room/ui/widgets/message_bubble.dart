import 'package:flutter/material.dart';

import '../../../../shared/conversation_ui/conversation_bubble.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/models/question_message.dart';

/// 카카오톡식 말풍선(질문방). 학생 채팅·멘토 답변 화면이 함께 쓴다.
///
/// ★ [mine] = 현재 로그인 사용자의 메시지 → 우측(accent). 상대 → 좌측(surface).
///   학생 화면에선 학생=우측/멘토=좌측, 멘토 화면에선 멘토=우측/학생=좌측로
///   자동으로 '거울상'이 된다(author_id == 내 uid 기준).
///
/// 외관은 공용 [ConversationBubble] 이 소유한다. 이 위젯은 질문방 모델을
/// 그 계층의 표현 파라미터로 옮기는 얇은 어댑터다 — 시각 계약은 바뀌지 않는다.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.attachments = const <Widget>[],
  });

  final QuestionMessage message;
  final bool mine;

  /// 이 메시지에 연결된 이미지 첨부 위젯(썸네일). 상위(LiveMessageList)가 만들어 넣는다.
  final List<Widget> attachments;

  @override
  Widget build(BuildContext context) {
    return ConversationBubble(
      body: message.body,
      align: mine ? ConversationAlign.end : ConversationAlign.start,
      tone: mine ? ConversationTone.accent : ConversationTone.neutral,
      // 표시 직전 로컬 변환(방어). DB 파싱 경로는 이미 로컬(parseTime)이라
      // toLocal() 이 no-op 이고, UTC 로 들어온 값만 기기 시간대로 맞춰진다.
      // → 중복 변환 없음. 전역 Formatters 는 건드리지 않는다.
      timeLabel: Formatters.hourMinute(message.createdAt.toLocal()),
      attachments: attachments,
    );
  }
}
