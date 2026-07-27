import 'package:flutter/material.dart';
import '../tokens/color_tokens.dart';
import '../tokens/dimens.dart';

/// 보조 액션 버튼(외곽선).
/// ★ 색 위계(2026-07 QA4): 액션 의미의 외곽선 버튼도 **고정 액션 파랑**
///   (ColorTokens.accent = #2563EB) — 멘토 테마에서도 동일. 멘토 정체성(초록)은
///   배지·탭·장식(AppAccent 경유)에만 남긴다.
///
/// [neutral]=true 면 액션색 대신 중립 회색 외곽선을 쓴다(웹 이동 등 '보조 탈출' 버튼 —
/// 강조색 절제 원칙 유지).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.expand = true,
    this.icon,
    this.neutral = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final IconData? icon;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final Widget child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

    final Color fg = neutral ? ColorTokens.secondary : ColorTokens.accent;
    final Color side = neutral ? ColorTokens.border : ColorTokens.accent;
    final Widget button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        disabledForegroundColor: ColorTokens.muted,
        minimumSize: const Size(0, 52),
        side: BorderSide(color: side, width: 1.4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
