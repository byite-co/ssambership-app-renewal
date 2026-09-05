import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';

/// A-4a 정산 화면 픽스처 — RPC 응답과 같은 형태(cents 원문). 재계산 0.
SettlementSummary sampleSettlementSummary({bool registered = true}) =>
    SettlementSummary(
      month: '2026-09',
      runDate: '2026-09-10',
      payoutAccountRegistered: registered,
      confirmedNetCents: 43120000, // 431,200원
      confirmedCount: 5,
      accruingNetCents: 12000000, // 120,000원
      accruingCount: 2,
      heldMentorAmountCents: 3500000, // 35,000원
      heldCount: 1,
      paidTotalNetCents: 210000000, // 2,100,000원
      paidTotalCount: 18,
      bySource: const <String, SettlementSourceAmount>{
        'subscription':
            SettlementSourceAmount(mentorAmountCents: 38000000, count: 4),
        'individual_question':
            SettlementSourceAmount(mentorAmountCents: 6000000, count: 3),
        'custom_request':
            SettlementSourceAmount(mentorAmountCents: 0, count: 0),
      },
    );

/// 최신순(9월 → 8월) 5건: 적립중·지급 예정·보류(분쟁)·지급 완료·취소.
List<SettlementLine> sampleSettlementLines() => <SettlementLine>[
      SettlementLine(
        sourceType: 'subscription',
        sourceId: 's-1',
        occurredAt: DateTime(2026, 9, 3),
        periodStart: DateTime(2026, 8, 3),
        periodEnd: DateTime(2026, 9, 2),
        grossCents: 8490000,
        platformFeeCents: 1698000,
        mentorAmountCents: 6792000,
        withholdingCents: 0,
        netCents: 6792000,
        status: SettlementLineStatus.accruing,
        expectedRunDate: '2026-10-10',
      ),
      SettlementLine(
        sourceType: 'individual_question',
        sourceId: 'iq-9',
        occurredAt: DateTime(2026, 9, 1),
        grossCents: 300000,
        platformFeeCents: 60000,
        mentorAmountCents: 240000,
        withholdingCents: 7900,
        netCents: 232100,
        status: SettlementLineStatus.pending,
        expectedRunDate: '2026-09-10',
      ),
      SettlementLine(
        sourceType: 'individual_question',
        sourceId: 'iq-7',
        occurredAt: DateTime(2026, 8, 28),
        grossCents: 500000,
        platformFeeCents: 100000,
        mentorAmountCents: 400000,
        withholdingCents: 0,
        netCents: 400000,
        status: SettlementLineStatus.hold,
        holdReason: 'active_dispute',
      ),
      SettlementLine(
        sourceType: 'subscription',
        sourceId: 's-0',
        occurredAt: DateTime(2026, 8, 3),
        periodStart: DateTime(2026, 7, 3),
        periodEnd: DateTime(2026, 8, 2),
        grossCents: 8490000,
        platformFeeCents: 1698000,
        mentorAmountCents: 6792000,
        withholdingCents: 224100,
        netCents: 6567900,
        status: SettlementLineStatus.paid,
        expectedRunDate: '2026-09-10',
        paidRunDate: '2026-09-10',
        paidAt: DateTime(2026, 9, 10, 9),
      ),
      SettlementLine(
        sourceType: 'custom_request',
        sourceId: 'cr-2',
        occurredAt: DateTime(2026, 8, 1),
        grossCents: 1000000,
        platformFeeCents: 200000,
        mentorAmountCents: 800000,
        withholdingCents: 0,
        netCents: 0,
        status: SettlementLineStatus.canceled,
      ),
    ];
