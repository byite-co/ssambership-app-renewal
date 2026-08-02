/// 질문방 안전 조치 동선(학생 채팅·멘토 답변 화면 공용).
///
/// ★ 취소는 **쓰기 0회** — 시트/다이얼로그를 닫으면 어떤 repository 호출도 하지 않는다.
/// ★ 성공·실패 모두 사용자 문구로 피드백하고, 실패는 성공으로 위장하지 않는다.
/// ★ 서버 오류 원문·SQL·UUID 는 문구에 싣지 않는다.
library;

import 'package:flutter/material.dart';

import '../../../community/ui/widgets/report_sheet.dart';
import '../../data/room_counterparty.dart';
import '../../data/room_safety_repository.dart';

const String _reportGuidance =
    '이 질문방 상대의 부적절한 언행, 외부 연락처 유도, 광고·스팸을 신고할 수 있어요.'
    ' 접수 내용은 운영팀이 검토해요.';

/// 상대 사용자 신고. 사유 선택 시트 → 접수. 접수됐으면 true.
Future<bool> reportRoomCounterparty(
  BuildContext context, {
  required RoomCounterparty counterparty,
  required RoomSafetyPort safety,
}) async {
  final String? reason =
      await showReportSheet(context, guidance: _reportGuidance);
  if (reason == null) return false; // 취소 — 쓰기 0회.
  if (!context.mounted) return false;

  final SafetyOutcome r = await safety.reportUser(
    targetUserId: counterparty.userId,
    reason: reason,
  );
  if (!context.mounted) return r == SafetyOutcome.ok;
  _snack(context, switch (r) {
    SafetyOutcome.ok => '신고를 접수했어요. 운영팀이 검토할게요.',
    SafetyOutcome.self => '자기 자신은 신고할 수 없어요.',
    SafetyOutcome.notLoggedIn => '로그인하면 신고할 수 있어요.',
    SafetyOutcome.failed => '신고 접수에 실패했어요. 잠시 후 다시 시도해 주세요.',
  });
  return r == SafetyOutcome.ok;
}

/// 상대 사용자 차단. 확인 다이얼로그 → 차단. 차단됐으면 true.
Future<bool> confirmAndBlockRoomCounterparty(
  BuildContext context, {
  required RoomCounterparty counterparty,
  required RoomSafetyPort safety,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text('${counterparty.displayName} 님을 차단할까요?'),
      content: const Text(
        '차단하면 이 질문방에서 새 메시지·첨부를 보낼 수 없어요.'
        ' 지금까지의 대화는 그대로 볼 수 있고, 해제는 설정 > 차단 사용자 관리에서 할 수 있어요.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('차단'),
        ),
      ],
    ),
  );
  if (ok != true) return false; // 취소 — 쓰기 0회.
  if (!context.mounted) return false;

  final SafetyOutcome r = await safety.blockUser(counterparty.userId);
  if (!context.mounted) return r == SafetyOutcome.ok;
  _snack(context, switch (r) {
    SafetyOutcome.ok => '차단했어요. 이 질문방에서 새 메시지를 보낼 수 없어요.',
    SafetyOutcome.self => '자기 자신은 차단할 수 없어요.',
    SafetyOutcome.notLoggedIn => '로그인하면 차단할 수 있어요.',
    SafetyOutcome.failed => '차단에 실패했어요. 잠시 후 다시 시도해 주세요.',
  });
  return r == SafetyOutcome.ok;
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
