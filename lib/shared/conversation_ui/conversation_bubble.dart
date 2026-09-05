/// 대화 말풍선 — **외관 전용** 공용 위젯.
///
/// 이 계층은 도메인을 모른다. 모델·레포지토리·Supabase·RPC·정산 규칙을
/// import 하지 않으며, "누가 썼는가"도 판정하지 않는다. 호출부(각 도메인의
/// presentation adapter)가 이미 판정한 결과를 [align]·[tone]·[authorLabel] 로
/// 넘겨준다. 강제 규칙은 test/shared/conversation_ui_layering_test.dart 참조.
library;

import 'package:flutter/material.dart';

import '../../design/role_theme.dart';
import '../../design/tokens/app_colors.dart';
import '../../design/tokens/app_glass.dart';
import '../../design/tokens/app_spacing.dart';
import '../../design/tokens/app_typography.dart';

/// 말풍선이 붙는 레이아웃 모서리.
///
/// 이름이 mine/theirs 가 아닌 이유: mine 은 '보는 사람'에 대한 문장인데
/// 이 계층에는 보는 사람이 없다. start/end 는 배치에 대한 문장이라
/// 판정 책임을 호출부에 남겨둔다. [center] 는 작성자를 확정할 수 없을 때 쓴다.
enum ConversationAlign { start, center, end }

/// 말풍선 채움 톤(design-v3 §3-2). [accent] 는 현재 역할색 불투명 채움 + 흰 글자
/// (학생 화면=파랑, 멘토 화면=초록 — 테마가 결정하며 이 계층은 모른다),
/// [neutral] 은 유리 패널 실효색(불투명) + 링 + 본문색.
enum ConversationTone { neutral, accent }

/// 대화 표면의 고정 기하값. 화면마다 매직 넘버가 흩어지지 않도록 한 곳에 모은다.
abstract final class ConversationMetrics {
  /// 말풍선 최대 폭 = 화면 폭 × 이 비율(수식·사진이 섞이므로 넓게 — §3-2).
  static const double maxWidthFactor = 0.8;

  /// 보낸 쪽 아래 모서리만 각지게 만드는 '꼬리' 반경.
  static const double tailRadius = 4;

  /// 말풍선 내부 여백.
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  /// 말풍선 사이 세로 간격.
  static const double gap = 14;

  /// 본문과 첨부 사이 간격.
  static const double attachmentGap = 10;

  /// 본문 줄 높이.
  static const double bodyHeight = 1.5;
}

class ConversationBubble extends StatelessWidget {
  const ConversationBubble({
    super.key,
    required this.body,
    this.align = ConversationAlign.start,
    this.tone = ConversationTone.neutral,
    this.timeLabel,
    this.authorLabel,
    this.titleLabel,
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

  /// 제목 줄(본문 위에 굵게). 제목이 있는 메시지(예: 최초 게시 글)를 하나의
  /// 말풍선으로 통합할 때 쓴다. null 이면 표시하지 않는다 — 기존 호출부 불변.
  final String? titleLabel;

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
    final bool accent = tone == ConversationTone.accent;
    // ★ 둘 다 불투명 — 뒤 배경·첨부가 비쳐 글자 대비가 흔들리지 않게(A-6b 3번).
    final Color bg = accent ? RoleTheme.of(context).color : AppColors.glass;
    final Color fg = accent ? Colors.white : AppColors.textPrimary;
    final Color fgSoft =
        accent ? Colors.white.withValues(alpha: 0.82) : AppColors.textSecondary;
    final double maxBubbleWidth =
        MediaQuery.sizeOf(context).width * ConversationMetrics.maxWidthFactor;

    const Radius r = Radius.circular(AppRadius.card);
    const Radius tail = Radius.circular(ConversationMetrics.tailRadius);
    final BorderRadius bubbleRadius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: _isEnd ? r : tail,
      bottomRight: _isEnd ? tail : r,
    );

    final Widget? time = timeLabel == null
        ? null
        : Text(
            timeLabel!,
            style: AppTypography.meta.copyWith(fontSize: 11),
          );

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
              decoration: BoxDecoration(
                color: bg,
                borderRadius: bubbleRadius,
                border: accent ? null : Border.all(color: AppColors.ring),
                boxShadow: accent
                    ? null
                    : const <BoxShadow>[AppGlass.panelShadow],
              ),
              child: Column(
                crossAxisAlignment:
                    _isEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (authorLabel != null) ...<Widget>[
                    Text(
                      authorLabel!,
                      style: AppTypography.meta.copyWith(color: fgSoft),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (titleLabel != null) ...<Widget>[
                    Text(
                      titleLabel!,
                      style: AppTypography.bodyStrong.copyWith(
                        color: fg,
                        height: ConversationMetrics.bodyHeight,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (body.isNotEmpty)
                    Text(
                      body,
                      style: AppTypography.body.copyWith(
                        color: fg,
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
