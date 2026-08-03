import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ssambership_app/features/community/data/user_blocks_repository.dart';

/// S3-E §6 — 중복 차단 멱등 처리.
/// `user_blocks` PK 는 (blocker_id, blocked_id) 라 재차단은 23505 로 떨어진다.
void main() {
  test('unique_violation(23505) 은 이미 차단됨 = 멱등 성공', () {
    const PostgrestException e = PostgrestException(
      message: 'duplicate key value violates unique constraint "user_blocks_pkey"',
      code: '23505',
    );
    expect(isAlreadyBlockedError(e), isTrue);
  });

  test('코드가 비어도 문구 폴백으로 판정한다', () {
    const PostgrestException e = PostgrestException(
      message: 'Duplicate key value violates unique constraint',
    );
    expect(isAlreadyBlockedError(e), isTrue);
  });

  test('다른 오류는 멱등 성공으로 보지 않는다(fail-closed)', () {
    const PostgrestException rls = PostgrestException(
      message: 'new row violates row-level security policy',
      code: '42501',
    );
    expect(isAlreadyBlockedError(rls), isFalse);
    expect(isAlreadyBlockedError(Exception('network unreachable')), isFalse);
  });
}
