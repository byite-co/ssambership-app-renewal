import 'package:flutter/material.dart';

import 'tokens/app_colors.dart';
import 'tokens/app_glass.dart';

enum AppRole { student, mentor }

/// Supplies the role accent without coupling the v3 design system to auth.
///
/// 앱 루트(`lib/app/app.dart`)가 로그인 역할을 읽어 [MaterialApp] 위에 한 번 두른다.
/// 조상에 없으면 학생(파랑) 기본값으로 떨어진다 — 화면을 단독으로 pump 하는
/// 위젯 테스트·골든이 역할 래핑 없이도 그려지게 하기 위해서다(A-6b).
class RoleTheme extends InheritedWidget {
  const RoleTheme({
    super.key,
    required this.role,
    required super.child,
  });

  final AppRole role;

  /// 조상 없음 폴백(학생). `child` 는 쓰이지 않는다.
  static const RoleTheme fallback = RoleTheme(
    role: AppRole.student,
    child: SizedBox.shrink(),
  );

  Color get color => colorOf(role);

  Color get button => color.withValues(alpha: AppGlass.buttonAlpha);

  Color get tint => color.withValues(alpha: AppGlass.tintAlpha);

  /// 역할 → 역할색(위젯 밖에서도 쓸 수 있게 static).
  static Color colorOf(AppRole role) =>
      role == AppRole.student ? RoleColors.student : RoleColors.mentor;

  static RoleTheme of(BuildContext context) => maybeOf(context) ?? fallback;

  static RoleTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoleTheme>();

  @override
  bool updateShouldNotify(RoleTheme oldWidget) => role != oldWidget.role;
}
