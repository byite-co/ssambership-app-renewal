import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S3-E 질문방 신고·차단 계약 문서 드리프트 회귀 가드.
///
/// 과거 초안의 `SERVER_BLOCK_CONTRACT_MISSING: YES` / append·register 차단 없음 /
/// 신고 어휘 `comment`·`shortform` 이 현행 정본 문서로 되돌아가지 않도록 고정한다.
/// 단순 문자열이 아니라 해당 절을 읽어 최소 current contract 를 잠근다.
void main() {
  const String path = 'docs/S3E_QUESTION_ROOM_SAFETY_CONTRACT.md';
  final String doc = File(path).readAsStringSync();

  // 현행 절만 검사한다 — "변경 이력" 절(과거 상태 서술 허용)은 제외.
  final int historyIdx = doc.indexOf('## 6. 변경 이력');
  final String current = historyIdx > 0 ? doc.substring(0, historyIdx) : doc;

  test('과거 결함 플래그가 현행 절에 없다', () {
    expect(current.contains('SERVER_BLOCK_CONTRACT_MISSING: YES'), isFalse,
        reason: '과거 결함 플래그가 현행 계약 절에 남아 있다');
    // append/register 를 "차단 없음(❌)" 으로 표기하지 않는다.
    expect(RegExp(r'qna_append_message.*❌').hasMatch(current), isFalse);
    expect(RegExp(r'qna_register_attachment.*❌').hasMatch(current), isFalse);
    expect(current.contains('양방향 차단 검사'), isTrue,
        reason: '차단 계약 절이 존재해야 한다');
  });

  test('신고 target 정본 어휘 고정', () {
    expect(current.contains('`board_comment`'), isTrue, reason: 'board_comment 정본 누락');
    expect(current.contains('`shortform_post`'), isTrue, reason: 'shortform_post 정본 누락');
    expect(current.contains('`community_comment`'), isTrue);
    expect(current.contains('`community_post`'), isTrue);
    // 금지 어휘를 신규 정본으로 표기하지 않는다(코드 span 정확 토큰).
    expect(current.contains('`comment` 신규 사용 금지'), isTrue,
        reason: 'comment 금지 명시 누락');
    expect(current.contains('`shortform` 신규 사용 금지'), isTrue,
        reason: 'shortform 금지 명시 누락');
  });

  test('서버 차단·수렴 PASS 플래그 고정', () {
    expect(current.contains('SERVER_BLOCK_CONTRACT: PASS'), isTrue);
    expect(current.contains('APP_BLOCK_UI_CONTRACT: PASS'), isTrue);
    expect(current.contains('REPORT_TARGET_CONTRACT: PASS'), isTrue);
    expect(current.contains('QUESTION_ROOM_SAFETY_CONVERGENCE: PASS'), isTrue);
  });

  test('세 RPC 모두 서버 양방향 차단 적용으로 표기', () {
    // §3-1 표: create/append/register 모두 "적용".
    expect(current.contains('`qna_create_question_thread`'), isTrue);
    expect(current.contains('`qna_append_message`'), isTrue);
    expect(current.contains('`qna_register_attachment`'), isTrue);
    // append/register 가 "적용" 으로 표기되는지(차단 검사 있음).
    final RegExp appliedRows = RegExp(r'qna_(append_message|register_attachment)`\s*\|\s*✅ 적용');
    expect(appliedRows.allMatches(current).length, greaterThanOrEqualTo(2),
        reason: 'append/register 가 서버 차단 "적용" 으로 표기돼야 한다');
  });
}
