import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/core/commerce/commerce_policy.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/mypage_screen.dart';
import '../support/app_scope_test_harness.dart';

/// 멘토 마이페이지 — role=mentor 분기로 멘토 전용 내용이 뜨고 학생 섹션은 안 뜬다.
MyPageData _mentorData() => const MyPageData(
      role: AppRole.mentor,
      profile: MyProfile(name: '가격설정멘토', roleLabel: '멘토'),
      mentor: MentorDashboard(
        studentCount: 3,
        pendingAnswers: 2,
        latestSettlementCents: 480000, // 4,800원
      ),
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('role=mentor → 답변·정산 요약(조회) 렌더, 학생 섹션은 비표시',
      (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpScopedWidget(
        _wrap(MyPageScreen(loaderOverride: () async => _mentorData())));
    await tester.pump();

    // 멘토 전용
    expect(find.text('가격설정멘토'), findsOneWidget);
    expect(find.text('답변 · 정산 요약'), findsOneWidget);
    expect(find.text('구독 학생'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // CountBadge(구독 학생)
    expect(find.text('답변 대기'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // CountBadge(답변 대기)
    expect(find.text('최근 정산'), findsOneWidget);
    expect(find.text('4,800원'), findsOneWidget); // 정산 조회 표기
    // P0-3 잔존 처리: 정산 관리 링크는 kPayoutManageLinkEnabled 를 따르고,
    // off(스토어 빌드 기본)면 안내 카드로 대체된다(죽은 버튼·빈 공백 금지).
    // on 상태는 `--dart-define=PAYOUT_MANAGE_LINK_ENABLED=true` 로 같은 테스트 검증.
    if (kPayoutManageLinkEnabled) {
      expect(find.text('정산 관리 (웹)'), findsOneWidget);
      expect(find.text(kPayoutManageNoticeText), findsNothing);
    } else {
      expect(find.text('정산 관리 (웹)'), findsNothing);
      expect(find.text(kPayoutManageNoticeText), findsOneWidget);
    }

    // 학생 전용 섹션은 없어야 한다.
    expect(find.text('구독 현황'), findsNothing);
    expect(find.text('보유 캐시'), findsNothing);

    // 설정은 공통.
    expect(find.text('설정'), findsOneWidget);
  });

  testWidgets('정산 데이터 없으면 숫자 날조 없이 "-" 표기', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpScopedWidget(_wrap(MyPageScreen(
      loaderOverride: () async => const MyPageData(
        role: AppRole.mentor,
        profile: MyProfile(name: '멘토', roleLabel: '멘토'),
        mentor: MentorDashboard(studentCount: 0, pendingAnswers: 0),
      ),
    )));
    await tester.pump();
    expect(find.text('최근 정산'), findsOneWidget);
    expect(find.text('-'), findsOneWidget); // 금액 미확인 → '-'
  });
}
