import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_typography.dart';
import 'glass_surface.dart';

/// A translucent top app bar for v3 screens.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const <Widget>[],
  });

  final Widget title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return GlassSurface.bar(
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: <Widget>[
              if (leading != null)
                SizedBox(width: kToolbarHeight, child: Center(child: leading)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: leading == null ? 20 : 0),
                  child: DefaultTextStyle(
                    style: AppTypography.section.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                ),
              ),
              ...actions,
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Five-tab role-aware navigation with no selected-tab background indicator.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  }) : assert(selectedIndex >= 0 && selectedIndex < 5);

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const List<_TabSpec> _studentTabs = <_TabSpec>[
    _TabSpec(Icons.forum_outlined, '질문방'),
    _TabSpec(Icons.chat_bubble_outline, '개별질문'),
    _TabSpec(Icons.person_search_outlined, '멘토찾기'),
    _TabSpec(Icons.groups_outlined, '커뮤니티'),
    _TabSpec(Icons.notifications_none, '알림'),
  ];

  static const List<_TabSpec> _mentorTabs = <_TabSpec>[
    _TabSpec(Icons.forum_outlined, '질문방'),
    _TabSpec(Icons.chat_bubble_outline, '개별질문'),
    _TabSpec(Icons.account_balance_wallet_outlined, '정산'),
    _TabSpec(Icons.groups_outlined, '커뮤니티'),
    _TabSpec(Icons.notifications_none, '알림'),
  ];

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final List<_TabSpec> tabs =
        roleTheme.role == AppRole.student ? _studentTabs : _mentorTabs;

    return GlassSurface.bar(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              for (int index = 0; index < tabs.length; index++)
                Expanded(
                  child: _GlassTab(
                    spec: tabs[index],
                    selected: index == selectedIndex,
                    selectedColor: roleTheme.color,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassTab extends StatelessWidget {
  const _GlassTab({
    required this.spec,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? selectedColor : AppColors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: spec.label,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(spec.icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              spec.label,
              maxLines: 1,
              style: AppTypography.caption.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Glass content and modal wrapper for v3 bottom sheets.
class GlassBottomSheet extends StatelessWidget {
  const GlassBottomSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 10, 20, 26),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.navy.withValues(alpha: AppGlass.scrimAlpha),
      elevation: 0,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: (BuildContext sheetContext) => GlassBottomSheet(
        child: builder(sheetContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface.bar(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      padding: padding,
      child: SafeArea(top: false, child: child),
    );
  }
}
