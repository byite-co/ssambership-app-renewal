import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_post_envelope.dart';

/// envelope 해석(앱 계약 §3.3)·오류코드 문구(§6.4·§6.5) 단위 고정.
void main() {
  group('CommunityWriteEnvelope.tryParse', () {
    test('성공 envelope + 멱등 재생 표시', () {
      final CommunityWriteEnvelope? env =
          CommunityWriteEnvelope.tryParse(<String, dynamic>{
        'ok': true,
        'contract_version': 1,
        'post_id': 'p',
        'idempotent_replay': true,
      });
      expect(env, isNotNull);
      expect(env!.ok, isTrue);
      expect(env.idempotentReplay, isTrue);
      expect(env.fields['post_id'], 'p');
    });

    test('ok:false 는 code 필수 — code 없으면 비정상(null)', () {
      expect(
          CommunityWriteEnvelope.tryParse(
              <String, dynamic>{'ok': false, 'contract_version': 1}),
          isNull);
      final CommunityWriteEnvelope? env = CommunityWriteEnvelope.tryParse(
          <String, dynamic>{'ok': false, 'code': 'TITLE_REQUIRED'});
      expect(env!.ok, isFalse);
      expect(env.code, 'TITLE_REQUIRED');
    });

    test("`ok` 없는 응답·비Map 응답은 envelope 가 아니다(성공 간주 금지 — §3.3)", () {
      expect(CommunityWriteEnvelope.tryParse(<String, dynamic>{'post_id': 'p'}),
          isNull);
      expect(CommunityWriteEnvelope.tryParse('ok'), isNull);
      expect(CommunityWriteEnvelope.tryParse(null), isNull);
      expect(
          CommunityWriteEnvelope.tryParse(<String, dynamic>{'ok': 'true'}),
          isNull); // 문자열 'true' 도 성공 아님.
    });
  });

  group('communityWriteErrorMessage (§6.4·§6.5)', () {
    test('ROLE_NOT_MENTOR 와 MENTOR_NOT_APPROVED 는 구분 문구다', () {
      final String? notMentor = communityWriteErrorMessage('ROLE_NOT_MENTOR');
      final String? notApproved =
          communityWriteErrorMessage('MENTOR_NOT_APPROVED');
      expect(notMentor, isNotNull);
      expect(notApproved, isNotNull);
      expect(notMentor, isNot(notApproved));
    });

    test('안정 코드 전건 한글 문구 존재(코드 원문 비노출)', () {
      const List<String> codes = <String>[
        'AUTH_REQUIRED', 'ROLE_NOT_MENTOR', 'MENTOR_NOT_APPROVED',
        'ACCOUNT_BANNED', 'ACCOUNT_SUSPENDED', 'ACCOUNT_DELETION_IN_PROGRESS',
        'TITLE_REQUIRED', 'BODY_TOO_SHORT', 'CATEGORY_INVALID',
        'IMAGE_COUNT_EXCEEDED', 'IMAGE_REF_INVALID', 'IMAGE_NOT_OWNED',
        'IMAGE_OBJECT_NOT_FOUND', 'IMAGE_MIME_NOT_ALLOWED',
        'IMAGE_SIZE_EXCEEDED', 'POST_NOT_FOUND_OR_NOT_OWNED',
        'UPDATE_CONFLICT',
      ];
      for (final String code in codes) {
        final String? msg = communityWriteErrorMessage(code);
        expect(msg, isNotNull, reason: code);
        expect(msg, isNot(contains(code)), reason: '코드 원문 비노출: $code');
      }
    });

    test('미지 코드는 null → 일반 문구 폴백(성공 위장 금지)', () {
      expect(communityWriteErrorMessage('POLICY_RESTRICTED'), isNull);
      final CommunityWriteRejected e =
          CommunityWriteRejected('SOME_FUTURE_CODE');
      expect(e.code, 'SOME_FUTURE_CODE');
      expect(e.userMessage, isNotEmpty);
      expect(e.userMessage, isNot(contains('SOME_FUTURE_CODE')));
    });
  });
}
