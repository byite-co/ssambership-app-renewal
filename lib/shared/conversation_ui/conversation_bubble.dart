/// 대화 말풍선 — **외관 전용** 공용 위젯.
///
/// 이 계층은 도메인을 모른다. 모델·레포지토리·Supabase·RPC·정산 규칙을
/// import 하지 않으며, "누가 썼는가"도 판정하지 않는다. 호출부(각 도메인의
/// presentation adapter)가 이미 판정한 결과를 [align]·[tone]·[authorLabel] 로
/// 넘겨준다. 강제 규칙은 test/shared/conversation_ui_layering_test.dart 참조.
library;

import 'package:flutter/material.dart';

import '../../design/role_accent.dart';
import '../../design/shape_tokens.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';

/// 말풍선이 붙는 레이아웃 모서리.
///
/// 이름이 mine/theirs 가 아닌 이유: mine 은 '보는 사람'에 대한 문장인데
/// 이 계층에는 보는 사람이 없다. start/end 는 배치에 대한 문장이라
/// 판정 책임을 호출부에 남겨둔다. [center] 는 작성자를 확정할 수 없을 때 쓴다.
enum ConversationAlign { start, center, end }

/// 말풍선 채움 톤. [accent] 는 현재 테마의 역할 강조색 옅은 틴트를 쓴다
/// (학생 테마=파랑 계열, 멘토 테마=초록 계열 — 테마가 결정하며 이 계층은 모른다).
enum ConversationTone { neutral, accent }

/// 대화 표면의 고정 기하값. 화면마다 매직 넘버가 흩어지지 않도록 한 곳에 모은다.
abstract final class ConversationMetrics {
  /// 말풍선 최대 폭 = 화면 폭 × 이 비율.
  static const double maxWidthFactor = 0.72;

  /// 보낸 쪽 아래 모서리만 각지게 만드는 '꼬리' 반경.
  static const double tailRadius = 4;

  /// 말풍선 내부 여백.
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 10);

  /// 말풍선 사이 세로 간격.
  static const double gap = 10;

  /// 본문과 첨부 사이 간격.
  static const double attachmentGap = 8;

  /// 본문 줄 높이.
  static const double bodyHeight = 1.35;
}

class ConversationBubble extends StatelessWidget {
  const ConversationBubble({
    super.key,
    required this.body,
    this.align = ConversationAlign.start,
    this.tone = ConversationTone.neutral,
    this.timeLabel,
    this.authorLabel,
    this.attachments = const <Widget>[],
  });

  /// 본문. 비어 있으면 렌더하지 않는다(첨부만 있는 말풍선을 허용).
  final String body;

  final ConversationAlign align;
  final ConversationTone tone;

  /// 이미 사람이 읽을 수 있게 가공된 시각 문자열. null 이면 시각을 표시하지 않는다.
  /// (계층은 DateTime 포맷 규칙을 소유하지 않는다 — 도메인마다 다르다.)
  final String? timeLabel;

  /// 작성자 표기(예: '학생'). null 이면 표시하지 않는다.
  /// 내부 id·영문 코드를 그대로 넘기지 말 것 — 화면 노출 금지 규약.
  final String? authorLabel;

  /// 이 말풍선에 딸린 첨부 위젯(썸네일·파일 칩). 상위가 만들어 넣는다.
  final List<Widget> attachments;

  bool get _isEnd => align == ConversationAlign.end;

  MainAxisAlignment get _rowAlignment {
    switch (align) {
      case ConversationAlign.start:
        return MainAxisAlignment.start;
      case ConversationAlign.center:
        return MainAxisAlignment.center;
      case ConversationAlign.end:
        return MainAxisAlignment.end;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = tone == ConversationTone.accent
        ? AppAccent.of(context).accentSoft
        : ColorTokens.elevated;
    final double maxBubbleWidth =
        MediaQuery.sizeOf(context).width * ConversationMetrics.maxWidthFactor;

    const Radius r = Radius.circular(AppShape.card);
    const Radius tail = Radius.circular(ConversationMetrics.tailRadius);
    final BorderRadius bubbleRadius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: _isEnd ? r : tail,
      bottomRight: _isEnd ? tail : r,
    );

    final Widget? time = timeLabel == null
        ? null
        : Text(timeLabel!, style: AppType.caption);

    return Padding(
      padding: const EdgeInsets.only(bottom: ConversationMetrics.gap),
      child: Row(
        mainAxisAlignment: _rowAlignment,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (_isEnd && time != null)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: time,
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              padding: ConversationMetrics.padding,
              decoration:
                  BoxDecoration(color: bg, borderRadius: bubbleRadius),
              child: Column(
                crossAxisAlignment: _isEnd
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (authorLabel != null) ...<Widget>[
                    Text(authorLabel!, style: AppType.caption),
                    const SizedBox(height: 4),
                  ],
                  if (body.isNotEmpty)
                    Text(
                      body,
                      style: AppType.body.copyWith(
                        color: ColorTokens.primary,
                        height: ConversationMetrics.bodyHeight,
                      ),
                    ),
                  for (final Widget a in attachments) ...<Widget>[
                    if (body.isNotEmpty || a != attachments.first)
                      const SizedBox(height: ConversationMetrics.attachmentGap),
                    a,
                  ],
                ],
              ),
            ),
          ),
          if (!_isEnd && time != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: time,
            ),
        ],
      ),
    );
  }
}
