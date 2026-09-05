import 'package:flutter/material.dart';

import '../../../../design/tokens/color_tokens.dart';
import '../../data/room_counterparty.dart';

/// 질문방 안전 메뉴 항목. [markWrong]·[unmarkWrong] 은 학생 오답 표시(A-4a α6).
enum RoomSafetyAction { report, block, markWrong, unmarkWrong }

/// 질문방 앱바 메뉴(오답 표시 / 신고하기 / 사용자 차단).
///
/// ★ [counterparty] 가 null 이면(상대 미확인) 메뉴 자체를 **비활성화**한다(S3-E §7).
/// ★ 상대 raw UUID 는 어떤 경우에도 표기하지 않는다 — 표시명만 쓴다.
class RoomSafetyMenu extends StatelessWidget {
  const RoomSafetyMenu({
    super.key,
    required this.counterparty,
    required this.onSelected,
    this.blocked = false,
    this.wrongAnswerToggle = false,
    this.wrongAnswer = false,
  });

  final RoomCounterparty? counterparty;
  final void Function(RoomSafetyAction action) onSelected;

  /// 이미 차단한 상대면 '차단' 항목을 비활성 표기한다(중복 실행 방지).
  final bool blocked;

  /// 학생 채팅에서만 true — '오답으로 표시 / 오답 표시 해제' 항목을 보인다.
  final bool wrongAnswerToggle;

  /// 현재 오답 표시 상태(항목 문구 결정).
  final bool wrongAnswer;

  @override
  Widget build(BuildContext context) {
    final bool enabled = counterparty != null;
    return PopupMenuButton<RoomSafetyAction>(
      enabled: enabled,
      icon: Icon(
        Icons.more_vert,
        color: enabled ? null : ColorTokens.muted,
      ),
      tooltip: enabled ? '신고·차단' : '상대를 확인할 수 없어요',
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<RoomSafetyAction>>[
        if (wrongAnswerToggle)
          PopupMenuItem<RoomSafetyAction>(
            value: wrongAnswer
                ? RoomSafetyAction.unmarkWrong
                : RoomSafetyAction.markWrong,
            child: Text(wrongAnswer ? '오답 표시 해제' : '오답으로 표시'),
          ),
        const PopupMenuItem<RoomSafetyAction>(
          value: RoomSafetyAction.report,
          child: Text('신고하기'),
        ),
        PopupMenuItem<RoomSafetyAction>(
          value: RoomSafetyAction.block,
          enabled: !blocked,
          child: Text(blocked ? '차단한 사용자' : '사용자 차단'),
        ),
      ],
    );
  }
}
