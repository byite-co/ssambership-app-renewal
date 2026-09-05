import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentors/data/free_question_entry.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mentors/ui/mentor_detail_screen.dart';

import '../subscription/fake_subscription_commerce.dart';
import 'golden_app_fakes.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';
import 'tab_entry_golden_fakes.dart';

class _GoldenFreeQuestion implements FreeQuestionEntryPort {
  const _GoldenFreeQuestion();
  @override
  Future<FreeQuestionEntrySnapshot> fetch(String mentorId) async =>
      const FreeQuestionEntrySnapshot(roomId: null, totalUsed: 0, perMentorUsed: 0);
  @override
  Future<String> ensureRoom(String mentorId) async => kRoomId;
  @override
  Future<CreatedFreeQuestion> createFreeThread({
    required String roomId,
    required String title,
    String? subject,
    String? firstMessageBody,
  }) =>
      throw UnsupportedError('golden');
}

/// A-4b ① — 멘토 상세(비구독 학생) 위에 요금제 결제 시트(design-v3 §5-3).
/// 스탠다드 기본 선택 · 실제 단가 · 잔액 45,700원 → 39,200원 부족(위험색) · 버튼 비활성.
void main() {
  testWidgets('golden: a4b_subscribe_sheet', (WidgetTester tester) async {
    final MentorListItem mentor = goldenMentorDirectoryItems().first.copyWith(
      plans: const <MentorPlan>[
        MentorPlan(planTier: 'limited', amountCents: 2990000),
        MentorPlan(planTier: 'standard', amountCents: 8490000),
        MentorPlan(planTier: 'premium', amountCents: 17490000),
      ],
    );
    final AppDependencies base =
        goldenDependencies(auth: FakeAppAuth(role: AppRole.student, userId: kStudentId));
    await pumpGoldenScreen(
      tester,
      MentorDetailScreen(
        item: mentor,
        createCtaOverride: true,
        extrasLoaderOverride: () async => const MentorDetailExtras(
          avgResponseHours: 2,
          avgRating: 4.9,
          reviewCount: 28,
          alreadySubscribed: false,
        ),
        subscriptionCommerceOverride: FakeSubscriptionCommerce(balanceCents: 4570000),
        identityGateOverride: false,
      ),
      role: AppRole.student,
      dependencies: AppDependencies(
        auth: base.auth,
        supabaseClient: () => null,
        mentorLookup: base.mentorLookup,
        studentLookup: base.studentLookup,
        subscriptions: base.subscriptions,
        freeQuestionEntry: const _GoldenFreeQuestion(),
        notificationBadge: base.notificationBadge,
        deletionNotice: base.deletionNotice,
      ),
    );
    expect(find.text('구독하기'), findsOneWidget);
    await tester.tap(find.text('구독하기'));
    await tester.pumpAndSettle();
    expect(find.text('요금제를 골라주세요'), findsOneWidget);
    expect(find.text('잔액이 39,200원 부족해요'), findsOneWidget);
    expect(find.textContaining('충전'), findsNothing);
    await expectScreenGolden(tester, 'a4b_subscribe_sheet');
  });
}
