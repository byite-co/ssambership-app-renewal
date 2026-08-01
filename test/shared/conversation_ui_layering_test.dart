import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// lib/shared/conversation_ui/ 가 도메인 프리로 남는지 기계적으로 잠근다.
///
/// 이 저장소에 import 레이어링 린트가 없고(analysis_options.yaml 에 analyzer
/// 블록·custom_lint 없음), lib/shared/ 는 오늘 균일하게 도메인 프리가 아니다
/// (shared/labels/question_room_labels.dart 가 features 모델을 import 한다).
/// 그래서 가드는 선택이 아니라 필수다.
///
/// ★ 주석은 검사 전에 걷어낸다. 이 계층의 문서 주석에는 "어떤 도메인 타입을
///   쓰지 않는다"는 설명이 들어가는 것이 정상이고, 주석까지 통째로 훑으면
///   설명을 쓸수록 가드가 빨개진다. 대신 아래 자기-검증 테스트가 가드 자체의
///   작동을 확인하므로, 주석만 남기는 식으로 가드를 무력화할 수 없다.
const String _layerDir = 'lib/shared/conversation_ui';

/// 계층에 등장하면 안 되는 경로·심볼 조각(코드 기준).
const List<String> _forbiddenSubstrings = <String>[
  'supabase',
  'features/',
  'repository',
  'Repository',
  'individual_question',
  'question_room',
  'connection_note',
  'friendly_error',
  '.rpc(',
  'storage.from',
];

/// 계층에 등장하면 안 되는 도메인 타입(단어 경계 기준).
const List<String> _forbiddenSymbols = <String>[
  'Room',
  'QuestionThread',
  'QuestionMessage',
  'QuestionAttachment',
  'IndividualQuestion',
  'IqMessage',
  'IqAttachment',
  'SubscriptionSummary',
  'WeeklyQuestionUsage',
  'ConnectionNote',
  'PickedImage',
];

/// 허용 import 접두사. 이외의 상대 import 는 전부 거부한다.
final List<RegExp> _allowedImports = <RegExp>[
  RegExp(r"^package:flutter/"),
  RegExp(r"^dart:"),
  RegExp(r"^\.\./\.\./design/"),
  RegExp(r"^\.\./format/"),
  RegExp(r"^\./"), // 계층 내부 파일끼리
];

/// `//`·`///` 주석을 제거한다(문자열 리터럴 안의 `//` 는 보존).
String stripDartComments(String source) {
  final StringBuffer out = StringBuffer();
  for (final String line in source.split('\n')) {
    out.writeln(_stripLine(line));
  }
  return out.toString();
}

String _stripLine(String line) {
  bool inSingle = false;
  bool inDouble = false;
  for (int i = 0; i < line.length; i++) {
    final String c = line[i];
    if (c == r'\') {
      i++; // 이스케이프 다음 문자 건너뜀
      continue;
    }
    if (c == "'" && !inDouble) inSingle = !inSingle;
    if (c == '"' && !inSingle) inDouble = !inDouble;
    if (!inSingle &&
        !inDouble &&
        c == '/' &&
        i + 1 < line.length &&
        line[i + 1] == '/') {
      return line.substring(0, i);
    }
  }
  return line;
}

Iterable<String> _importTargets(String code) sync* {
  final RegExp re = RegExp(r"""import\s+['"]([^'"]+)['"]""");
  for (final RegExpMatch m in re.allMatches(code)) {
    yield m.group(1)!;
  }
}

void main() {
  final Directory dir = Directory(_layerDir);

  test('계층 디렉터리가 존재하고 비어 있지 않다', () {
    expect(dir.existsSync(), isTrue, reason: '$_layerDir 가 없다');
    final List<File> files = dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
  });

  test('계층 코드에 도메인 심볼·경로가 없다(주석 제외)', () {
    for (final File f in dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))) {
      final String code = stripDartComments(f.readAsStringSync());

      for (final String bad in _forbiddenSubstrings) {
        expect(code.contains(bad), isFalse,
            reason: '${f.path} 코드에 금지 조각 "$bad" 가 있다');
      }
      for (final String sym in _forbiddenSymbols) {
        expect(RegExp('\\b$sym\\b').hasMatch(code), isFalse,
            reason: '${f.path} 코드에 금지 도메인 타입 "$sym" 이 있다');
      }
    }
  });

  test('계층 import 는 허용 목록 안에만 있다', () {
    for (final File f in dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))) {
      final String code = stripDartComments(f.readAsStringSync());
      for (final String target in _importTargets(code)) {
        final bool ok =
            _allowedImports.any((RegExp re) => re.hasMatch(target));
        expect(ok, isTrue,
            reason: '${f.path} 의 import "$target" 은 허용 목록에 없다');
      }
    }
  });

  // ── 가드 자체가 살아 있는지 확인 ──────────────────────────────────
  // 주석 제거 로직이 과하게 동작해 코드까지 지워버리면 위 두 테스트가
  // '아무것도 못 찾아서' 통과한다. 합성 입력으로 실제 탐지를 증명한다.
  group('가드 자기-검증', () {
    test('주석 제거는 주석만 지우고 코드는 남긴다', () {
      const String src = '''
/// QuestionThread 를 쓰지 않는다.
import 'package:flutter/material.dart'; // IqMessage 아님
final String s = 'https://example.com/x'; // 링크의 // 는 문자열이라 보존
''';
      final String code = stripDartComments(src);
      expect(code.contains('QuestionThread'), isFalse);
      expect(code.contains('IqMessage'), isFalse);
      expect(code.contains("import 'package:flutter/material.dart';"), isTrue);
      expect(code.contains('https://example.com/x'), isTrue);
    });

    test('금지 심볼이 코드에 있으면 탐지된다', () {
      const String src = "final QuestionThread t = load();";
      final String code = stripDartComments(src);
      expect(RegExp(r'\bQuestionThread\b').hasMatch(code), isTrue);
    });

    test('금지 import 가 있으면 탐지된다', () {
      const String src =
          "import '../../features/question_room/data/models/room.dart';";
      final String code = stripDartComments(src);
      final List<String> targets = _importTargets(code).toList();
      expect(targets, isNotEmpty);
      expect(_allowedImports.any((RegExp re) => re.hasMatch(targets.single)),
          isFalse);
    });
  });
}
