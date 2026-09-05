import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A-6b 디자인 잠금(design lock) — v3 유리 디자인 시스템으로 이관을 끝낸 뒤
/// 옛 토큰·옛 버튼·임시 셸이 다시 들어오면 실패한다.
///
/// 이 테스트는 정적 검사다(위젯 렌더 없음). 실패 메시지가 위반 파일·줄을 가리킨다.
void main() {
  List<File> productionDartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  /// 파일별 위반 줄 수집(주석 줄은 제외 — 이관 기록·설명은 허용).
  List<String> violations(RegExp pattern, {bool Function(String path)? skip}) {
    final List<String> out = <String>[];
    for (final File f in productionDartFiles()) {
      if (skip != null && skip(f.path)) continue;
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(line)) out.add('${f.path}:${i + 1}: ${line.trim()}');
      }
    }
    return out;
  }

  group('A-6b 디자인 잠금', () {
    test('옛 토큰·옛 버튼·임시 셸 파일은 존재하지 않는다', () {
      const List<String> deleted = <String>[
        'lib/design/theme.dart',
        'lib/design/typography_tokens.dart',
        'lib/design/shape_tokens.dart',
        'lib/design/spacing_tokens.dart',
        'lib/design/role_accent.dart',
        'lib/design/tokens/color_tokens.dart',
        'lib/design/tokens/dimens.dart',
        'lib/design/tokens/typography.dart',
        'lib/design/widgets/app_card.dart',
        'lib/design/widgets/primary_button.dart',
        'lib/design/widgets/secondary_button.dart',
        'lib/design/widgets/empty_state.dart',
        'lib/design/widgets/empty_screen.dart',
        'lib/design/widgets/skeleton.dart',
        'lib/design/widgets/glass_badge.dart',
        'lib/shared/widgets/v3_page.dart',
      ];
      final List<String> present =
          deleted.where((String p) => File(p).existsSync()).toList();
      expect(present, isEmpty, reason: '삭제된 옛 디자인 파일이 되살아났다');
    });

    test('옛 클래스 이름이 production 코드에 없다', () {
      final RegExp old = RegExp(
        r'\b(ColorTokens|AppType|AppShape|AppAccent|RoleAccent|AppCard|'
        r'V3Page|V3LoadingView|V3ErrorView|GlassBadge|EmptyScreen|showV3BottomSheet)\b'
        r'|(?<![A-Za-z_])(EmptyState|PrimaryButton|SecondaryButton|Skeleton)\(',
      );
      expect(violations(old), isEmpty);
    });

    test('옛 hex 색(#1A56DB·#16A34A·#8B95A1)이 없다', () {
      final RegExp hex = RegExp(r'1A56DB|16A34A|8B95A1', caseSensitive: false);
      expect(violations(hex), isEmpty);
    });

    test('Divider 위젯 대신 링색 1px 선을 쓴다', () {
      final RegExp divider = RegExp(r'(?<![A-Za-z_])(Vertical)?Divider\(');
      expect(violations(divider), isEmpty);
    });

    test('elevation 은 디자인 시스템(테마·유리 위젯)만 0 으로 고정한다 — 화면 코드에는 없다',
        () {
      final RegExp elevation = RegExp(r'\belevation:');
      expect(
        violations(elevation, skip: (String p) => p.startsWith('lib/design/')),
        isEmpty,
      );
      // 디자인 시스템 안에서도 그림자 높이는 0 뿐이다.
      final RegExp nonZero = RegExp(
          r'\belevation:(?!\s*(?:0\b|const WidgetStatePropertyAll<double>\(0\)))');
      expect(violations(nonZero), isEmpty);
    });

    test('BackdropFilter 는 GlassSurface 한 곳에만 있다(콘텐츠 카드 블러 금지)', () {
      final RegExp blur = RegExp(r'\bBackdropFilter\b');
      expect(
        violations(blur,
            skip: (String p) => p == 'lib/design/widgets/glass_surface.dart'),
        isEmpty,
      );
    });

    test('Scaffold 를 직접 쓰는 화면은 셸·미디어 뷰어·전체화면 진입만이다', () {
      // AppPage/HomeShellChrome 이 v3 껍데기다. 예외는 명시 목록으로 잠근다.
      const Set<String> allowed = <String>{
        'lib/design/widgets/app_page.dart',
        'lib/app/home_shell.dart',
        'lib/core/version_gate/version_gate_screens.dart',
        'lib/features/auth/splash_screen.dart',
        'lib/features/auth/login_screen.dart',
        'lib/features/auth/blocked_screen.dart',
        'lib/features/onboarding/onboarding_screen.dart',
        'lib/features/community/community_screen.dart',
        'lib/features/question_room/ui/attachment_viewer_screen.dart',
        'lib/features/individual_question/ui/iq_detail_screen.dart',
      };
      final RegExp scaffold = RegExp(r'\bScaffold\(');
      final List<String> found = violations(
        scaffold,
        skip: (String p) => allowed.contains(p),
      );
      expect(found, isEmpty, reason: '새 Scaffold 화면은 AppPage 를 써야 한다');
    });

    test('삭제된 옛 파일을 import 하는 곳이 없다', () {
      final RegExp oldImport = RegExp(
        r"design/(theme|typography_tokens|shape_tokens|spacing_tokens|role_accent)\.dart"
        r"|tokens/(color_tokens|dimens|typography)\.dart"
        r"|widgets/(app_card|primary_button|secondary_button|empty_state|empty_screen|skeleton|glass_badge)\.dart"
        r"|shared/widgets/v3_page\.dart",
      );
      expect(violations(oldImport), isEmpty);
    });
  });
}
