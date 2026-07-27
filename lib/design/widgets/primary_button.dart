import 'package:flutter/material.dart';
import '../tokens/color_tokens.dart';
import '../tokens/dimens.dart';

/// 주요 액션 버튼.
/// ★ 색 위계(2026-07 QA4): 액션 CTA 는 역할 정체성 색이 아니라 **고정 액션
///   파랑**(ColorTokens.accent = #2563EB)을 쓴다 — 멘토 테마에서도 동일.
///   멘토 정체성(초록)은 배지·탭·아이콘·장식(AppAccent 경유)에만 남긴다.
///   위험 액션은 기존 danger, 중립/취소는 기존 neutral 계열 그대로.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.expand = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final IconData? icon;

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

    final Widget button = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: ColorTokens.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: ColorTokens.muted,
        disabledForegroundColor: ColorTokens.secondary,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
