import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_typography.dart';
import 'glass_inner.dart';

/// Text input whose glass decoration cannot be replaced by callers.
class AppInputField extends StatefulWidget {
  const AppInputField({
    super.key,
    this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.showCursor,
  })  : assert(minLines > 0),
        assert(maxLines == null || maxLines >= minLines);

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? labelText;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final int minLines;
  final int? maxLines;
  final bool? showCursor;

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
    return GlassInner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ringColor:
          _focusNode.hasFocus ? roleTheme.color.withValues(alpha: 0.45) : null,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        showCursor: widget.showCursor,
        cursorColor: roleTheme.color,
        style: AppTypography.body,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
      ),
    );
  }
}
