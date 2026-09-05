import 'package:flutter/material.dart';
import 'package:scribble/scribble.dart';

import '../ink_input_mode.dart';
import '../scribble_ink_adapter.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/widgets/glass_surface.dart';

/// 하단 고정 P0 툴바(모바일 1차).
///
/// 구성: 펜/지우개 · 색 프리셋 3개(검정·빨강·파랑) · 굵기 3단 · undo/redo ·
///       전체 지우기(확인 다이얼로그) · 손가락 그리기 토글(InkInputMode).
/// ※ 형광펜·템플릿은 P1 이라 제외.
///
/// ScribbleNotifier 를 주입받아 ValueListenableBuilder 로 현재 상태
/// (선택 색·굵기·지우개 모드·undo/redo 가능 여부)를 반영한다.
class InkToolbar extends StatefulWidget {
  const InkToolbar({
    super.key,
    required this.notifier,
    required this.inputMode,
    required this.onInputModeChanged,
  });

  final ScribbleNotifier notifier;

  /// 현재 입력 모드(펜 전용/손가락 허용). 상위(화면)가 소유·내보내기에 사용.
  final InkInputMode inputMode;

  /// 손가락 토글 결과를 상위에 알린다(상위가 모드를 보관).
  final ValueChanged<InkInputMode> onInputModeChanged;

  @override
  State<InkToolbar> createState() => _InkToolbarState();
}

/// 잉크 색 프리셋 — 필기 '내용물' 색이라 Colors 직접 사용 허용(디자인 토큰 예외).
const List<_InkColor> _colorPresets = <_InkColor>[
  _InkColor(Colors.black, '검정'),
  _InkColor(Colors.red, '빨강'),
  _InkColor(Colors.blue, '파랑'),
];

/// 굵기 3단(가는/중간/굵은 펜).
const List<_InkWidth> _widthPresets = <_InkWidth>[
  _InkWidth(3, '가는 펜'),
  _InkWidth(6, '중간 펜'),
  _InkWidth(12, '굵은 펜'),
];

class _InkToolbarState extends State<InkToolbar> {
  /// 지우개로 전환하면 scribble state 에서 색 정보가 사라지므로,
  /// 펜으로 돌아올 때 복원할 '마지막 펜 색'을 로컬에 보관한다.
  late Color _penColor;

  @override
  void initState() {
    super.initState();
    _penColor = widget.notifier.value.map(
      drawing: (Drawing d) => Color(d.selectedColor),
      erasing: (_) => Colors.black,
    );
  }

  void _selectColor(Color color) {
    _penColor = color;
    widget.notifier.setColor(color); // 지우개였다면 자동으로 펜(그리기)으로 전환.
  }

  void _selectPen() => widget.notifier.setColor(_penColor);

  void _selectEraser() => widget.notifier.setEraser();

  Future<void> _confirmClearAll() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('전체 지우기'),
        content: const Text('필기 전체를 지울까요? 되돌릴 수 없어요.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('전체 지우기'),
          ),
        ],
      ),
    );
    if (ok == true) widget.notifier.clear();
  }

  void _toggleInputMode() {
    final InkInputMode next = widget.inputMode == InkInputMode.penOnly
        ? InkInputMode.penAndTouch
        : InkInputMode.penOnly;
    ScribbleInkAdapter.applyInputMode(widget.notifier, next);
    widget.onInputModeChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface.bar(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: ValueListenableBuilder<ScribbleState>(
            valueListenable: widget.notifier,
            builder: (BuildContext context, ScribbleState state, _) {
              final bool erasing = state.map(
                drawing: (_) => false,
                erasing: (_) => true,
              );
              final int? selectedColor = state.map(
                drawing: (Drawing d) => d.selectedColor,
                erasing: (_) => null,
              );
              final double selectedWidth = state.selectedWidth;
              final bool fingerAllowed =
                  widget.inputMode == InkInputMode.penAndTouch;

              return Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  // 펜 / 지우개
                  _ToolIconButton(
                    icon: Icons.edit_rounded,
                    tooltip: '펜',
                    selected: !erasing,
                    onPressed: _selectPen,
                  ),
                  _ToolIconButton(
                    icon: Icons.auto_fix_normal,
                    tooltip: '지우개',
                    selected: erasing,
                    onPressed: _selectEraser,
                  ),
                  const _ToolSeparator(),
                  // 색 프리셋 3개
                  for (final _InkColor preset in _colorPresets)
                    _ColorSwatch(
                      color: preset.color,
                      label: preset.label,
                      selected:
                          !erasing && selectedColor == preset.color.toARGB32(),
                      onPressed: () => _selectColor(preset.color),
                    ),
                  const _ToolSeparator(),
                  // 굵기 3단
                  for (final _InkWidth preset in _widthPresets)
                    _WidthDot(
                      width: preset.width,
                      label: preset.label,
                      selected: selectedWidth == preset.width,
                      onPressed: () =>
                          widget.notifier.setStrokeWidth(preset.width),
                    ),
                  const _ToolSeparator(),
                  // undo / redo
                  _ToolIconButton(
                    icon: Icons.undo,
                    tooltip: '실행 취소',
                    onPressed:
                        widget.notifier.canUndo ? widget.notifier.undo : null,
                  ),
                  _ToolIconButton(
                    icon: Icons.redo,
                    tooltip: '다시 실행',
                    onPressed:
                        widget.notifier.canRedo ? widget.notifier.redo : null,
                  ),
                  const _ToolSeparator(),
                  // 전체 지우기
                  _ToolIconButton(
                    icon: Icons.delete_outline,
                    tooltip: '전체 지우기',
                    onPressed: _confirmClearAll,
                  ),
                  // 손가락 그리기 토글
                  _ToolIconButton(
                    icon: fingerAllowed
                        ? Icons.front_hand
                        : Icons.do_not_touch_outlined,
                    tooltip: fingerAllowed ? '손가락 허용' : '펜 전용',
                    selected: fingerAllowed,
                    onPressed: _toggleInputMode,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 색 프리셋 정의(내용물 색 — Colors 직접 사용 허용).
class _InkColor {
  const _InkColor(this.color, this.label);
  final Color color;
  final String label;
}

/// 굵기 프리셋 정의.
class _InkWidth {
  const _InkWidth(this.width, this.label);
  final double width;
  final String label;
}

/// 아이콘 툴 버튼(선택 시 강조). 모든 버튼에 한글 tooltip.
class _ToolIconButton extends StatelessWidget {
  const _ToolIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      color: selected ? RoleTheme.of(context).color : AppColors.textPrimary,
      disabledColor: AppColors.textSecondary,
      iconSize: 22,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// 색 스와치(선택 시 강조 링). 내용물 색이라 Colors 직접 사용.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? RoleTheme.of(context).color : AppColors.ring,
                width: selected ? 3 : 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 굵기 점(선택 시 강조 링). 굵기가 클수록 점이 커진다.
class _WidthDot extends StatelessWidget {
  const _WidthDot({
    required this.width,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final double width;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? RoleTheme.of(context).color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Container(
            width: 4 + width,
            height: 4 + width,
            decoration: const BoxDecoration(
              color: AppColors.textPrimary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// 툴 그룹 구분선.
class _ToolSeparator extends StatelessWidget {
  const _ToolSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: AppColors.ring,
    );
  }
}
