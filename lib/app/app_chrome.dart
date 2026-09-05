import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart' as auth;
import '../design/app_theme.dart';
import '../design/role_theme.dart';
import '../design/widgets/app_background.dart';

/// 앱 루트가 [MaterialApp] 에 두르는 v3 껍데기 — 골든·테스트 하네스도 같은 함수를
/// 쓴다(앱과 다른 껍데기로 그리지 않기 위해).
///
/// 로그인 역할 → 테마 역할: 멘토만 초록, 그 외(학생·게스트·관리자)는 학생 파랑.
AppRole themeRoleOf(auth.AppRole role) =>
    role == auth.AppRole.mentor ? AppRole.mentor : AppRole.student;

/// [MaterialApp.builder] 용 — 라우터(Navigator) 아래 전체에 배경 그라디언트를 깐다.
/// 페이지 스캐폴드([AppPage])도 자기 배경을 그리므로 route 전환 중에도 비치지 않는다.
Widget appBackgroundBuilder(BuildContext context, Widget? child) =>
    AppBackground(child: child ?? const SizedBox.shrink());

/// 역할 컨텍스트 + 테마를 [MaterialApp] 바깥에 두른다. [child] 는 [MaterialApp] 을
/// 만드는 빌더 — 테마 데이터를 넘겨받아 `theme:` 에 꽂는다.
Widget appChrome({
  required AppRole role,
  required Widget Function(ThemeData theme) child,
}) =>
    RoleTheme(role: role, child: child(AppTheme.build(role: role)));
