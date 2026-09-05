import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_typography.dart';
import 'glass_surface.dart';

/// A translucent top app bar for v3 screens.
///
/// [leading] 이 없고 [automaticallyImplyLeading] 이면 Material [AppBar] 와 같은
/// 규칙으로 뒤로 가기([BackButton])를 붙인다 — push 된 화면에서만 나타난다.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const <Widget>[],
    this.automaticallyImplyLeading = true,
  });

  final Widget title;
  final Widget? leading;
  final List<Widget> actions;

  /// Material [AppBar.automaticallyImplyLeading] 과 같다.
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    Widget? leading = this.leading;
    if (leading == null && automaticallyImplyLeading) {
      final ModalRoute<Object?>? route = ModalRoute.of(context);
      if (route?.impliesAppBarDismissal ?? false) {
        leading = const GlassBackButton();
      }
    }
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

/// 유리 앱바의 뒤로 가기 — Material [BackButton] 그대로(플랫폼 아이콘·pop 규칙).
///
/// 바깥 [Tooltip] 은 앱 로케일과 무관하게 `'뒤로'` 로 찾을 수 있게 하는 파인더용
/// 껍데기다(`triggerMode.manual` 이라 화면에는 뜨지 않고, 의미상 툴팁은 안쪽
/// [BackButton] 의 로케일 문자열 하나만 남는다).
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '뒤로',
      excludeFromSemantics: true,
      triggerMode: TooltipTriggerMode.manual,
      child: BackButton(color: AppColors.textPrimary, onPressed: onPressed),
    );
  }
}

/// 하단 탭 하나의 정의. 라벨은 한글만.
class GlassTabItem {
  const GlassTabItem({
    required this.icon,
    required this.label,
    this.badgeLabel,
  });

  final IconData icon;
  final String label;

  /// 아이콘 우상단 배지 문자열(예: '3' · '99+'). null 이면 배지 없음.
  final String? badgeLabel;
}

/// Five-tab role-aware navigation with no selected-tab background indicator.
///
/// 안쪽은 Material [NavigationBar] 다 — 선택 인덱스·목적지 라벨을 그대로 읽는
/// 셸 테스트(`home_shell_test` 등)와 접근성 의미론을 그대로 유지하고, 겉만
/// 유리 바([GlassSurface.bar])로 감싼다. [items] 를 주지 않으면 역할별 기본 5탭.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.items,
  }) : assert(selectedIndex >= 0 && selectedIndex < 5);

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 탭 정의. null 이면 [RoleTheme] 역할에 따라 [studentItems]·[mentorItems].
  final List<GlassTabItem>? items;

  static const double height = 64;

  static const List<GlassTabItem> studentItems = <GlassTabItem>[
    GlassTabItem(icon: Icons.forum_outlined, label: '질문방'),
    GlassTabItem(icon: Icons.chat_bubble_outline, label: '개별질문'),
    GlassTabItem(icon: Icons.person_search_outlined, label: '멘토찾기'),
    GlassTabItem(icon: Icons.groups_outlined, label: '커뮤니티'),
    GlassTabItem(icon: Icons.notifications_none, label: '알림'),
  ];

  static const List<GlassTabItem> mentorItems = <GlassTabItem>[
    GlassTabItem(icon: Icons.forum_outlined, label: '질문방'),
    GlassTabItem(icon: Icons.chat_bubble_outline, label: '개별질문'),
    GlassTabItem(icon: Icons.account_balance_wallet_outlined, label: '정산'),
    GlassTabItem(icon: Icons.groups_outlined, label: '커뮤니티'),
    GlassTabItem(icon: Icons.notifications_none, label: '알림'),
  ];

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final List<GlassTabItem> tabs = items ??
        (roleTheme.role == AppRole.student ? studentItems : mentorItems);
    final Color selectedColor = roleTheme.color;

    return GlassSurface.bar(
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: height,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          overlayColor: WidgetStatePropertyAll<Color>(roleTheme.tint),
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
            (Set<WidgetState> states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected)
                  ? selectedColor
                  : AppColors.textSecondary,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
            (Set<WidgetState> states) => AppTypography.caption.copyWith(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: states.contains(WidgetState.selected)
                  ? selectedColor
                  : AppColors.textSecondary,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: <NavigationDestination>[
            for (final GlassTabItem tab in tabs)
              NavigationDestination(
                icon: tab.badgeLabel == null
                    ? Icon(tab.icon)
                    : Badge(label: Text(tab.badgeLabel!), child: Icon(tab.icon)),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
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
