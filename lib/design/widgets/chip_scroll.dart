import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// 가로 스크롤 칩 행(필터·탭 전환). 활성 칩은 역할 틴트 + 역할색 글자, 비활성은
/// 유리 안쪽 채움 + 링(design-v3 §5-2 '수학 · 고등 · 10만원 이하').
/// 라벨은 한글만(영문 코드 노출 금지).
class ChipScroll extends StatelessWidget {
  const ChipScroll({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 가로 스크롤 영역의 안쪽 여백. 화면 가장자리까지 스크롤되며 끝 칩이 잘리지 않도록
  /// 좌우 여백을 스크롤 영역 '안'에 둔다(부모가 좌우 패딩으로 감싸면 끝이 잘려 보임).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      clipBehavior: Clip.none,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                label: labels[i],
                active: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final BorderRadius radius = BorderRadius.circular(AppRadius.input);
    return Material(
      color: active
          ? roleTheme.tint
          : Colors.white.withValues(alpha: AppGlass.innerFill),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: active
              ? roleTheme.color.withValues(alpha: 0.35)
              : AppColors.ring,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            // 스타일 계약: 활성 w800 · 비활성 w600(board_filter_chip_test 가 읽는다).
            style: AppTypography.caption.copyWith(
              color: active ? roleTheme.color : AppColors.textSecondary,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
