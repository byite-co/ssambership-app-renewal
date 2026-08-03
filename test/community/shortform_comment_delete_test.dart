import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_write_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import 'fakes.dart';

/// 숏폼 댓글 본인 소프트삭제 — RPC 계약(community_comment_soft_delete_self)
/// 봉투 검증·오류 매핑을 fake 게이트웨이로 고정한다(Supabase 미접촉).
void main() {
  CommunityWriteRepository repoOf(RecordingCommentsGateway g) =>
      CommunityWriteRepository(gateway: g);

  test('성공 봉투 {ok, contract_version:1} → 정상 종료 + comment_id 전달', () async {
    final RecordingCommentsGateway g = RecordingCommentsGateway();
    await repoOf(g).deleteMyShortformComment('c-1');
    expect(g.softDeletedCommentIds, <String>['c-1']);
  });

  test('멱등 히트(idempotent_hit=true)도 정상 성공(이중 탭 안전)', () async {
    final RecordingCommentsGateway g = RecordingCommentsGateway()
      ..softDeleteResult = <String, dynamic>{
        'ok': true,
        'contract_version': 1,
        'comment_id': 'c-1',
        'idempotent_hit': true,
      };
    await expectLater(repoOf(g).deleteMyShortformComment('c-1'), completes);
  });

  test('실패 봉투 코드 → 한글 문구(코드 비노출)', () async {
    const Map<String, String> cases = <String, String>{
      'COMMENT_NOT_FOUND': '댓글을 찾을 수 없어요',
      'COMMENT_TYPE_NOT_SUPPORTED': '앱에서 삭제할 수 없어요',
      'COMMENT_NOT_OWNED': '내가 쓴 댓글만',
      'COMMENT_MODERATED': '운영팀이 처리한 댓글',
      'ACCOUNT_NOT_ACTIVE': '현재 계정 상태에서는 이 기능을 사용할 수 없어요.',
    };
    for (final MapEntry<String, String> c in cases.entries) {
      final RecordingCommentsGateway g = RecordingCommentsGateway()
        ..softDeleteResult = <String, dynamic>{'ok': false, 'code': c.key};
      await expectLater(
        repoOf(g).deleteMyShortformComment('c-1'),
        throwsA(isA<AppError>().having(
          (AppError e) => e.userMessage,
          'userMessage',
          contains(c.value),
        )),
        reason: c.key,
      );
    }
  });

  test('raise exception 형태(예외 메시지에 코드)도 같은 문구로 매핑', () async {
    final RecordingCommentsGateway g = RecordingCommentsGateway()
      ..softDeleteError = Exception('COMMENT_NOT_OWNED');
    await expectLater(
      repoOf(g).deleteMyShortformComment('c-1'),
      throwsA(isA<AppError>().having(
        (AppError e) => e.userMessage,
        'userMessage',
        contains('내가 쓴 댓글만'),
      )),
    );
  });

  test('계약 밖 응답(ok 누락·버전 불일치) → 성공 위장 없이 AppError', () async {
    for (final Object? bad in <Object?>[
      null,
      'weird',
      <String, dynamic>{'ok': true, 'contract_version': 2},
      <String, dynamic>{'contract_version': 1},
    ]) {
      final RecordingCommentsGateway g = RecordingCommentsGateway()
        ..softDeleteResult = bad;
      await expectLater(
        repoOf(g).deleteMyShortformComment('c-1'),
        throwsA(isA<AppError>()),
        reason: '$bad',
      );
    }
  });

  test('미지 예외는 원본 그대로 전파(문구 날조 금지)', () async {
    final RecordingCommentsGateway g = RecordingCommentsGateway()
      ..softDeleteError = const FormatException('boom');
    await expectLater(
      repoOf(g).deleteMyShortformComment('c-1'),
      throwsA(isA<FormatException>()),
    );
  });
}
