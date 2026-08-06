import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_write_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// N3: 게시판 글 본인 소프트삭제 — 서버 봉투 계약 검증(성공 위장 금지).
void main() {
  group('ensurePostSoftDeleteOk', () {
    test('정상 성공 봉투 → 통과', () {
      CommunityWriteRepository.ensurePostSoftDeleteOk(<String, dynamic>{
        'ok': true,
        'contract_version': 1,
        'post_id': 'p-1',
        'deleted_at': '2026-08-06T00:00:00Z',
      });
    });

    test('이미 삭제(already_deleted) → 정상 성공(이중 탭 안전)', () {
      CommunityWriteRepository.ensurePostSoftDeleteOk(<String, dynamic>{
        'ok': true,
        'contract_version': 1,
        'post_id': 'p-1',
        'deleted_at': '2026-08-06T00:00:00Z',
        'already_deleted': true,
      });
    });

    test('계약 버전 불일치 → 성공으로 취급하지 않는다', () {
      expect(
        () => CommunityWriteRepository.ensurePostSoftDeleteOk(
            <String, dynamic>{'ok': true, 'contract_version': 2}),
        throwsA(isA<AppError>()),
      );
    });

    test('실패 봉투(소유 아님) → 한글 문구', () {
      expect(
        () => CommunityWriteRepository.ensurePostSoftDeleteOk(<String, dynamic>{
          'ok': false,
          'code': 'POST_NOT_FOUND_OR_NOT_OWNED',
        }),
        throwsA(predicate((Object? e) =>
            e is AppError && e.userMessage.contains('내가 쓴 글만'))),
      );
    });

    test('계약 밖 응답(null·비맵) → 공통 실패 문구', () {
      expect(
        () => CommunityWriteRepository.ensurePostSoftDeleteOk(null),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('postDeleteError 코드 매핑', () {
    test('AUTH_REQUIRED → 로그인 안내', () {
      expect(CommunityWriteRepository.postDeleteError('AUTH_REQUIRED')?.userMessage,
          contains('로그인'));
    });

    test('ACCOUNT_* 공통 코드는 댓글 삭제 매퍼 재사용', () {
      expect(
          CommunityWriteRepository.postDeleteError('ACCOUNT_DELETION_IN_PROGRESS')
              ?.userMessage,
          contains('탈퇴 처리 중'));
      expect(CommunityWriteRepository.postDeleteError('ACCOUNT_SUSPENDED')?.userMessage,
          contains('제한'));
    });

    test('미지 코드 → null(호출부 공통 문구 폴백)', () {
      expect(CommunityWriteRepository.postDeleteError('UNKNOWN_X'), isNull);
    });
  });
}
