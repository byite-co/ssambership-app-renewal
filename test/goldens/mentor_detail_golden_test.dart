import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mentors/ui/mentor_detail_screen.dart';

import 'golden_app_fakes.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';
import 'tab_entry_golden_fakes.dart';

/// 멘토 상세(design-v3 §5-3) — 구독 중 학생 시점: 헤더·과목·소개·활동 + '질문방으로'.
/// (비구독 '구독하기'는 A-4b 네이티브 버튼 전까지 웹 브릿지 안내 — 골든 대상 아님.)
void main() {
  testWidgets('golden: mentor_detail', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      MentorDetailScreen(
        item: goldenMentorDirectoryItems().first,
        initialFavorited: true,
        createCtaOverride: true,
        extrasLoaderOverride: () async => const MentorDetailExtras(
          avgResponseHours: 2,
          avgRating: 4.9,
          reviewCount: 28,
          alreadySubscribed: true,
        ),
      ),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.student, userId: kStudentId),
      ),
    );
    expect(find.text('질문방으로'), findsOneWidget);
    await expectScreenGolden(tester, 'mentor_detail');
  });
}
