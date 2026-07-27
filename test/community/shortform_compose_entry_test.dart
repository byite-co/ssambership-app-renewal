import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/web_bridge/shortform_compose_bridge.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/ui/shortform/shortform_compose_screen.dart';
import 'package:ssambership_app/features/community/ui/shortform/shortform_feed_view.dart';

import 'fakes.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

ShortformFeedView _feed({
  required AppRole role,
  List<ShortformPost> posts = const <ShortformPost>[],
}) {
  return ShortformFeedView(
    read: FakeCommunityRead(shortformsList: posts),
    write: FakeCommunityWrite(),
    roleOf: () => role,
  );
}

void main() {
  testWidgets('학생 → 숏폼 작성 CTA 미노출(목록·빈 화면 모두)', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(_feed(
        role: AppRole.student, posts: <ShortformPost>[sampleShortform()])));
    await tester.pumpAndSettle();
    expect(find.text('숏폼 작성'), findsNothing);

    // State 재사용 방지(같은 위치 재-pump 는 initState 재조회를 하지 않는다).
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(_wrap(_feed(role: AppRole.student)));
    await tester.pumpAndSettle();
    expect(find.text('숏폼 작성'), findsNothing);
    expect(find.text('멘토들의 숏폼이 올라오면 여기에 표시돼요.'), findsOneWidget);
  });

  testWidgets('게스트 → CTA 미노출(열람만)', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
        _feed(role: AppRole.guest, posts: <ShortformPost>[sampleShortform()])));
    await tester.pumpAndSettle();
    expect(find.text('숏폼 작성'), findsNothing);
  });

  testWidgets('멘토 → 목록 상단 CTA 노출', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(_feed(
        role: AppRole.mentor, posts: <ShortformPost>[sampleShortform()])));
    await tester.pumpAndSettle();
    expect(find.text('숏폼 작성'), findsOneWidget);
  });

  testWidgets('멘토 + 빈 피드 → 작성 유도 빈 화면(문구·CTA)', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(_feed(role: AppRole.mentor)));
    await tester.pumpAndSettle();
    expect(find.text('아직 숏폼이 없어요'), findsOneWidget);
    expect(find.text('앱 안에서 영상을 선택해 작성할 수 있어요.'), findsOneWidget);
    expect(find.text('숏폼 작성'), findsOneWidget);
  });

  testWidgets('CTA 탭 → 작성 화면 push, 세션 없음 → 로그인 유도(크래시 0)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(_feed(role: AppRole.mentor)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('숏폼 작성'));
    await tester.pumpAndSettle();

    // 테스트 환경(백엔드 미구성 = currentSession 없음): WebView 를 만들지 않고
    // 로그인 유도 안내를 그린다.
    expect(find.byType(ShortformComposeScreen), findsOneWidget);
    expect(find.text('로그인이 필요해요'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 취소(닫기) → 피드 복귀, 스낵바 없음, 크래시 없음.
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(ShortformComposeScreen), findsNothing);
    expect(find.text('임시저장됐어요'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작성 draft 완료 복귀 → 피드 서버 재조회 + 임시저장 안내',
      (WidgetTester tester) async {
    final _CountingRead read = _CountingRead();
    await tester.pumpWidget(_wrap(ShortformFeedView(
      read: read,
      write: FakeCommunityWrite(),
      roleOf: () => AppRole.mentor,
    )));
    await tester.pumpAndSettle();
    final int fetchesBefore = read.shortformCalls;

    await tester.tap(find.text('숏폼 작성'));
    await tester.pumpAndSettle();

    // 완료 브릿지 intercept 와 동일한 종료 신호: 결과와 함께 pop.
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pop(ShortformComposeResult.draft);
    await tester.pumpAndSettle();

    expect(read.shortformCalls, greaterThan(fetchesBefore)); // 서버 재조회
    expect(find.text('임시저장됐어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작성 published 완료 복귀 → 재조회로 새 카드 표시(로컬 가짜 카드 아님)',
      (WidgetTester tester) async {
    final _CountingRead read = _CountingRead();
    await tester.pumpWidget(_wrap(ShortformFeedView(
      read: read,
      write: FakeCommunityWrite(),
      roleOf: () => AppRole.mentor,
    )));
    await tester.pumpAndSettle();
    expect(find.text('새 숏폼'), findsNothing);

    await tester.tap(find.text('숏폼 작성'));
    await tester.pumpAndSettle();

    // '서버'에 새 글이 생겼다고 가정 → 복귀 후 재조회가 이 데이터를 가져와야 한다.
    read.posts = <ShortformPost>[sampleShortform(title: '새 숏폼')];
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pop(ShortformComposeResult.published);
    await tester.pumpAndSettle();

    expect(find.text('새 숏폼'), findsOneWidget);
    expect(find.text('임시저장됐어요'), findsNothing); // published 는 스낵바 없음
  });
}

/// 재조회 횟수를 세고, 호출 시점의 [posts] 를 돌려주는 read 페이크.
class _CountingRead extends FakeCommunityRead {
  _CountingRead();

  List<ShortformPost> posts = <ShortformPost>[];
  int shortformCalls = 0;

  @override
  Future<CommunityPage<ShortformPost>> shortforms(
      {int? limit, int offset = 0}) async {
    shortformCalls++;
    final int start = offset.clamp(0, posts.length);
    final int end =
        limit == null ? posts.length : (offset + limit).clamp(0, posts.length);
    return CommunityPage<ShortformPost>(
      items: posts.sublist(start, end),
      rawCount: end - start,
      nextOffset: end,
      hasMore: limit != null && (end - start) == limit,
    );
  }
}
