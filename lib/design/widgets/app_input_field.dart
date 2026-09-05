import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_typography.dart';
import 'glass_inner.dart';

/// Text input whose glass decoration cannot be replaced by callers.
///
/// 유리 안쪽 채움(α0.58) + 링. 포커스면 역할색 링, [errorText] 가 있으면 위험색
/// 링과 아래 안내 문장. 아이콘·글자 수 제한·도움말은 인자로만 열어 둔다 —
/// 장식(border·fill)은 호출부가 바꿀 수 없다.
class AppInputField extends StatefulWidget {
  const AppInputField({
    super.key,
    this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.showCursor,
    this.inputFormatters,
    this.autofillHints,
  })  : assert(minLines > 0),
        assert(maxLines == null || maxLines >= minLines);

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? labelText;
  final String? hintText;

  /// 입력 아래 안내(글자 수·형식). [errorText] 가 있으면 그 문장이 대신 나온다.
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final GestureTapCallback? onTap;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool obscureText;
  final int minLines;
  final int? maxLines;

  /// 글자 수 제한. 카운터는 기본 표시(Material) — 유리 안쪽에 작게 보인다.
  final int? maxLength;
  final bool? showCursor;

  /// 입력 필터(숫자만 등). null 이면 없음.
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;

  @override
  State<AppInputField> createState() => _AppInputFieldState();
}

class _AppInputFieldState extends State<AppInputField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _attachFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(AppInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusNode();
      _attachFocusNode(widget.focusNode);
    }
  }

  void _attachFocusNode(FocusNode? external) {
    _ownsFocusNode = external == null;
    _focusNode = external ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  void _detachFocusNode() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _detachFocusNode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final String? error = widget.errorText;
    final Color? ring = error != null
        ? AppColors.danger.withValues(alpha: 0.6)
        : _focusNode.hasFocus
            ? roleTheme.color.withValues(alpha: 0.45)
            : null;
    final Widget field = GlassInner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ringColor: ring,
      fillColor: AppColors.inputFill,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        showCursor: widget.showCursor,
        inputFormatters: widget.inputFormatters,
        autofillHints: widget.autofillHints,
        cursorColor: roleTheme.color,
        style: AppTypography.body.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          hintStyle: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
          ),
          labelStyle: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
          ),
          counterStyle: AppTypography.meta,
          prefixIcon: widget.prefixIcon,
          prefixIconColor: AppColors.textSecondary,
          suffixIcon: widget.suffixIcon,
          suffixIconColor: AppColors.textSecondary,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
    final String? note = error ?? widget.helperText;
    if (note == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        field,
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            note,
            style: AppTypography.caption.copyWith(
              color: error != null ? AppColors.danger : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
