import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/features/mentor_console/data/api_web_v1_envelope.dart';
import 'package:ssambership_app/features/mentor_console/data/document_validation.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_repository.dart';
import 'package:ssambership_app/features/mentor_console/data/payout_bank_allowlist.dart';

/// A-4a 데이터 계층 순수 로직 — 봉투 파서·마스킹·밴드·서류 검증·정산 파싱.
void main() {
  group('ApiEnvelope', () {
    test('성공 봉투는 ok · 보조 필드를 읽는다', () {
      final ApiEnvelope env = ApiEnvelope.parse(<String, dynamic>{
        'ok': true,
        'contract_version': 1,
        'account_masked': '******1234',
      });
      expect(env.ok, isTrue);
      expect(env.code, isNull);
      expect(env.stringField('account_masked'), '******1234');
    });

    test('실패 봉투는 code 를 보존하고 requireOk 가 사용자 문구로 던진다', () {
      final ApiEnvelope env = ApiEnvelope.parse(<String, dynamic>{
        'ok': false,
        'contract_version': 1,
        'code': 'PAYOUT_BANK_NAME_INVALID',
      });
      expect(env.ok, isFalse);
      expect(env.code, 'PAYOUT_BANK_NAME_INVALID');
      expect(
        () => env.requireOk(payoutAccountMessageForCode),
        throwsA(isA<ApiEnvelopeFailure>().having(
          (ApiEnvelopeFailure f) => f.userMessage,
          'message',
          contains('은행'),
        )),
      );
    });

    test('봉투 형태가 아니면(맵 아님·계약 버전 불일치) 계약 오류', () {
      expect(() => ApiEnvelope.parse(null), throwsA(isA<ApiEnvelopeError>()));
      expect(() => ApiEnvelope.parse(<String, dynamic>{'ok': true}),
          throwsA(isA<ApiEnvelopeError>()));
      expect(
        () => ApiEnvelope.parse(
            <String, dynamic>{'ok': 'yes', 'contract_version': 1}),
        throwsA(isA<ApiEnvelopeError>()),
      );
    });

    test('F8 밴드 초과 문구는 서버 보조 필드(min/max)를 그대로 쓴다', () {
      final String msg = planPricesMessageForCode('PLAN_PRICE_OUT_OF_BAND',
          <String, dynamic>{
            'tier': 'premium',
            'min_cash_krw': 174900,
            'max_cash_krw': 329900,
          });
      expect(msg, '프리미엄 요금은 174,900원~329,900원 사이로 적어 주세요.');
    });

    test('공통 계정 코드는 한 곳(apiWebV1CommonMessage)에서 문구화된다', () {
      expect(apiWebV1CommonMessage('MENTOR_NOT_APPROVED'), isNotNull);
      expect(mentorProfileMessageForCode('ROLE_NOT_MENTOR', <String, dynamic>{}),
          apiWebV1CommonMessage('ROLE_NOT_MENTOR'));
      expect(apiWebV1CommonMessage('SOMETHING_ELSE'), isNull);
    });
  });

  group('정산 계좌', () {
    test('마스킹은 끝 4자리만 남긴다 · 원문은 모델에 남지 않는다', () {
      expect(maskPayoutAccount('123456789012'), '********9012');
      expect(maskPayoutAccount('1234'), '1234');
      final PayoutAccountInfo info = PayoutAccountInfo.fromRow(<String, dynamic>{
        'payout_bank_name': '카카오뱅크',
        'payout_account_number': '3333012345678',
      });
      expect(info.registered, isTrue);
      expect(info.accountMasked, '*********5678');
      expect(PayoutAccountInfo.fromRow(null).registered, isFalse);
    });

    test('은행 allowlist 는 F13 정본 17종 · 계좌 형식은 8~24 숫자', () {
      expect(kPayoutBankAllowlist.length, 17);
      expect(kPayoutBankAllowlist.first, 'KB국민은행');
      expect(kPayoutBankAllowlist.last, 'iM뱅크');
      expect(kPayoutAccountNumberPattern.hasMatch('12345678'), isTrue);
      expect(kPayoutAccountNumberPattern.hasMatch('1234567'), isFalse);
      expect(kPayoutAccountNumberPattern.hasMatch('1' * 25), isFalse);
      expect(payoutAccountDigits('3333-01-2345678 '), '3333012345678');
    });
  });

  group('요금제', () {
    test('밴드는 F8 정본(29,900~69,900 · 84,900~149,900 · 174,900~329,900)', () {
      expect(PlanPriceBand.limited.contains(29900), isTrue);
      expect(PlanPriceBand.limited.contains(69901), isFalse);
      expect(PlanPriceBand.standard.contains(84899), isFalse);
      expect(PlanPriceBand.standard.contains(149900), isTrue);
      expect(PlanPriceBand.premium.contains(340000), isFalse);
      expect(PlanPriceBand.of(MentorPlanTier.premium).minWon, 174900);
    });

    test('mentor_plans 행 → 등급별 원 단위', () {
      final MentorPlanPrices p = MentorPlanPrices.fromRows(<Map<String, dynamic>>[
        <String, dynamic>{'plan_tier': 'limited', 'amount_cents': 2990000},
        <String, dynamic>{'plan_tier': 'premium', 'amount_cents': 17490000},
      ]);
      expect(p.limitedWon, 29900);
      expect(p.standardWon, isNull);
      expect(p.won(MentorPlanTier.premium), 174900);
    });
  });

  group('정산 조회', () {
    test('summary jsonb 파싱 — 금액 cents 원문 보존·소스별 집계', () {
      final SettlementSummary s = SettlementSummary.fromJson(<String, dynamic>{
        'month': '2026-09',
        'run_date': '2026-10-23',
        'payout_account_registered': false,
        'confirmed': <String, dynamic>{'count': 3, 'net_cents': 15291500},
        'accruing': <String, dynamic>{'count': 1, 'net_cents': 4250000},
        'held': <String, dynamic>{'count': 0, 'mentor_amount_cents': 0},
        'paid_total': <String, dynamic>{'count': 5, 'net_cents': 40000000},
        'by_source_this_month': <String, dynamic>{
          'subscription': <String, dynamic>{
            'mentor_amount_cents': 14866500,
            'count': 3
          },
          'individual_question': <String, dynamic>{
            'mentor_amount_cents': 425000,
            'count': 2
          },
        },
      });
      expect(s.thisMonthNetCents, 15291500);
      expect(s.payoutAccountRegistered, isFalse);
      expect(s.source('subscription').count, 3);
      expect(s.source('custom_request').mentorAmountCents, 0);
      expect(s.paidTotalCount, 5);
    });

    test('lines 행 파싱 — 상태 5종 외는 unknown(무음 매핑 금지)', () {
      final SettlementLine line = SettlementLine.fromMap(<String, dynamic>{
        'source_type': 'subscription',
        'source_id': 'abc',
        'occurred_at': '2026-09-01T00:00:00Z',
        'gross_cents': 8490000,
        'platform_fee_cents': 1273500,
        'mentor_amount_cents': 7216500,
        'withholding_cents': 238100,
        'net_cents': 6978400,
        'status': 'pending',
        'expected_run_date': '2026-10-23',
      });
      expect(line.status, SettlementLineStatus.pending);
      expect(line.payDate, '2026-10-23');
      expect(settlementLineStatusFromCode('weird'), SettlementLineStatus.unknown);
      expect(settlementLineStatusLabel(SettlementLineStatus.unknown),
          '상태 확인 필요');
      expect(settlementSourceLabel('individual_question'), '개별질문');
    });
  });

  group('검토형 제출', () {
    test('학력 인증 행 — 서류 없는 잠정 행 구분', () {
      final SchoolVerificationRecord auto =
          SchoolVerificationRecord.fromMap(<String, dynamic>{
        'id': 'v1',
        'status': 'pending',
        'created_at': '2026-09-01T00:00:00Z',
      });
      expect(auto.hasDocument, isFalse);
      expect(auto.status, ReviewStatus.pending);
      expect(reviewStatusFromCode('resubmit_required'),
          ReviewStatus.resubmitRequired);
      expect(reviewStatusFromCode('superseded'), ReviewStatus.superseded);
    });

    test('서류 검증 — 매직바이트·20MB', () {
      PickedImage pick(List<int> head, {int size = 64}) => PickedImage(
            bytes: Uint8List.fromList(
                <int>[...head, ...List<int>.filled(size - head.length, 0)]),
            fileName: 'doc.bin',
            mimeType: 'application/octet-stream',
          );
      expect(mentorDocumentProblem(pick(<int>[0xFF, 0xD8, 0xFF])), isNull);
      expect(
          verifyMentorDocument(pick(<int>[0x25, 0x50, 0x44, 0x46, 0x2D]))!.kind,
          MentorDocumentKind.pdf);
      expect(
          verifyMentorDocument(
                  pick(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))!
              .mimeType,
          'image/png');
      expect(mentorDocumentProblem(pick(<int>[0x00, 0x11])), contains('JPG'));
      final PickedImage big = PickedImage(
        bytes: Uint8List(kMentorDocumentMaxBytes + 1),
        fileName: 'big.jpg',
        mimeType: 'image/jpeg',
      );
      expect(mentorDocumentProblem(big), contains('20MB'));
    });
  });

  group('본인 프로필', () {
    test('행 파싱 · F7 인자 9개', () {
      final MentorOwnProfile p = MentorOwnProfile.fromMap(<String, dynamic>{
        'user_id': 'm1',
        'university_name': '서울대학교',
        'department_name': '수학교육과',
        'teaching_subjects': <String>['math', 'math_calculus'],
        'is_open_for_subscriptions': false,
        'verification_status': 'approved',
      });
      expect(p.isApproved, isTrue);
      expect(p.isOpenForSubscriptions, isFalse);
      final Map<String, dynamic> params = MentorProfileUpdate(
        universityName: p.universityName!,
        departmentName: p.departmentName!,
        teachingSubjects: p.teachingSubjects,
        isOpenForSubscriptions: true,
      ).toParams();
      expect(params.length, 9);
      expect(params['p_is_open_for_subscriptions'], isTrue);
      expect(params['p_teaching_subjects'], <String>['math', 'math_calculus']);
    });
  });
}
