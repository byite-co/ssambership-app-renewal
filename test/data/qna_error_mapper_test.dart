import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ssambership_app/features/question_room/data/qna_error_mapper.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';
import 'package:ssambership_app/shared/errors/friendly_error.dart';

/// qna_* RPC 구조화 오류코드 → 한글 UX 매핑(서버 계약 스냅샷 §1 기준).
void main() {
  PostgrestException pg(String message, {String? code}) =>
      PostgrestException(message: message, code: code ?? 'P0001');

  group('qnaErrorCode — 코드 토큰 추출', () {
    test('raise exception 코드 문자열을 그대로 추출한다', () {
      expect(
          qnaErrorCode(pg('WEEKLY_LIMIT_EXHAUSTED')), 'WEEKLY_LIMIT_EXHAUSTED');
      expect(qnaErrorCode(pg('THREAD_LOCKED')), 'THREAD_LOCKED');
    });

    test('일반 영문 에러 문장/비Postgrest 예외는 null', () {
      expect(qnaErrorCode(pg('duplicate key value violates unique constraint')),
          isNull);
      expect(qnaErrorCode(Exception('WEEKLY_LIMIT_EXHAUSTED')), isNull);
      expect(qnaErrorCode(const AppError('x')), isNull);
    });
  });

  group('qnaErrorMessage — 사용자 문구 매핑', () {
    test('사용량·질문권 소진 코드를 구분해 안내한다', () {
      expect(qnaErrorMessage(pg('WEEKLY_LIMIT_EXHAUSTED')), contains('이번 주'));
      expect(qnaErrorMessage(pg('FREE_QUOTA_TOTAL_EXHAUSTED')),
          contains('무료 질문권'));
      expect(qnaErrorMessage(pg('FREE_QUOTA_MENTOR_EXHAUSTED')),
          contains('무료 질문권'));
      expect(qnaErrorMessage(pg('FREE_QUOTA_EXPIRED')), contains('무료 질문 기간'));
    });

    test('환불 보류·잠긴 스레드·계정 제한·멘토 미승인 각각 다른 안내', () {
      expect(
          qnaErrorMessage(pg('SUBSCRIPTION_REFUND_PENDING')), contains('환불'));
      expect(qnaErrorMessage(pg('THREAD_LOCKED')), contains('종료'));
      expect(qnaErrorMessage(pg('ACCOUNT_SUSPENDED')), contains('제한'));
      expect(qnaErrorMessage(pg('ACCOUNT_BANNED')), contains('제한'));
      expect(qnaErrorMessage(pg('MENTOR_NOT_APPROVED')), contains('멘토'));
      expect(qnaErrorMessage(pg('NOT_ROOM_PARTY')), isNotNull);
      expect(qnaErrorMessage(pg('BLOCKED')), contains('차단'));
    });

    test('첨부 소유권·경로 오류는 첨부 안내로 묶인다', () {
      for (final String code in <String>[
        'STORAGE_PATH_REQUIRED',
        'STORAGE_PATH_MISMATCH',
        'STORAGE_OBJECT_NOT_OWNED',
        'MESSAGE_THREAD_MISMATCH',
      ]) {
        expect(qnaErrorMessage(pg(code)), contains('첨부'), reason: code);
      }
    });

    test('알 수 없는 코드는 null → 호출부가 일반 재시도 문구로 폴백', () {
      expect(qnaErrorMessage(pg('SOME_NEW_CODE')), isNull);
      expect(qnaErrorMessage(Exception('boom')), isNull);
    });

    test('매핑 문구에 내부 SQL/RPC명·영문 코드가 노출되지 않는다', () {
      for (final String code in <String>[
        'WEEKLY_LIMIT_EXHAUSTED',
        'SUBSCRIPTION_REFUND_PENDING',
        'THREAD_LOCKED',
        'STORAGE_OBJECT_NOT_OWNED',
      ]) {
        final String msg = qnaErrorMessage(pg(code))!;
        expect(msg.contains(code), isFalse);
        expect(msg.toLowerCase().contains('qna'), isFalse);
        expect(msg.toLowerCase().contains('rpc'), isFalse);
      }
    });
  });

  group('mapQnaError — AppError 변환', () {
    test('알려진 코드는 AppError(한글)로, friendlyError 로 그대로 표시 가능', () {
      final Object mapped = mapQnaError(pg('WEEKLY_LIMIT_EXHAUSTED'));
      expect(mapped, isA<AppError>());
      expect(friendlyError(mapped), contains('이번 주'));
    });

    test('알 수 없는 예외는 원본 그대로 → friendlyError 가 일반 문구', () {
      final Object raw = pg('unexpected');
      expect(identical(mapQnaError(raw), raw), isTrue);
      expect(friendlyError(raw), contains('잠시 후'));
    });
  });

  group('isUniqueViolation', () {
    test('23505 만 true', () {
      expect(isUniqueViolation(pg('duplicate key', code: '23505')), isTrue);
      expect(isUniqueViolation(pg('THREAD_LOCKED')), isFalse);
      expect(isUniqueViolation(Exception('23505')), isFalse);
    });
  });
}
