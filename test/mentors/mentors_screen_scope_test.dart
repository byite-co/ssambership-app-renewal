import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mentors/data/mentor_directory_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_directory_view.dart';
import 'package:ssambership_app/features/mentors/data/mentor_favorites_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mentors/mentors_screen.dart';
import 'package:ssambership_app/features/mentors/ui/widgets/mentor_card.dart';
import 'package:ssambership_app/features/mentors/ui/widgets/mentor_favorite_button.dart';

MentorListItem _m(String id,
        {String? name, List<String> subjects = const <String>[]}) =>
    MentorListItem(
      id: id,
      nickname: name ?? id,
      createdAt: DateTime(2026, 1, 1),
      profile: MentorProfileInfo(
        userId: id,
        universityName: null,
        departmentName: null,
        teachingSubjects: subjects,
      ),
    );

class _FakeDirectory extends MentorDirectoryRepository {
  _FakeDirectory(this.items);
  final List<MentorListItem> items;

  @override
  Future<List<MentorListItem>> listComplete() async => items;
}

class _FakeFavorites extends MentorFavoritesRepository {
  _FakeFavorites({
    this.loggedIn = true,
    Set<String>? ids,
    this.loadError = false,
    this.failOps = false,
  }) : ids = ids ?? <String>{};

  bool loggedIn;
  Set<String> ids;
  bool loadError;
  bool failOps;
  int loadCalls = 0;
  int addCalls = 0;
  int removeCalls = 0;

  /// 연타 테스트용 — 설정 시 add/remove 가 이 completer 를 기다린다.
  Completer<bool>? opGate;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<MentorFavoritesLoad> loadMyFavoriteMentorIds() async {
    loadCalls++;
    if (!loggedIn) return const MentorFavoritesLoggedOut();
    if (loadError) return const MentorFavoritesLoadError();
    return MentorFavoritesLoaded(Set<String>.of(ids));
  }

  @override
  Future<bool> add(String mentorId) async {
    addCalls++;
    final bool ok = opGate != null ? await opGate!.future : !failOps;
    if (ok) ids.add(mentorId);
    return ok;
  }

  @override
  Future<bool> remove(String mentorId) async {
    removeCalls++;
    final bool ok = opGate != null ? await opGate!.future : !failOps;
    if (ok) ids.remove(mentorId);
    return ok;
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Finder _heartOfCard(String mentorName) => find.descendant(
      of: find.widgetWithText(MentorCard, mentorName),
      matching: find.byType(MentorFavoriteButton),
    );

void main() {
  final List<MentorListItem> mentors = <MentorListItem>[
    _m('m1', name: '김수학', subjects: <String>['math']),
    _m('m2', name: '박영어', subjects: <String>['english']),
    _m('m3', name: '이과학', subjects: <String>['science']),
  ];

  testWidgets('비로그인 → scope 세그먼트 미노출, 전체 목록은 표시', (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(loggedIn: false);
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<MentorListScope>), findsNothing);
    expect(find.text('김수학'), findsOneWidget);
    expect(find.text('박영어'), findsOneWidget);
  });

  testWidgets('로그인 → 세그먼트 노출 + 찜 카운트 라벨 통합', (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(ids: <String>{'m1', 'm2'});
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    expect(find.text('전체'), findsWidgets); // 세그먼트 + 과목칩 '전체'
    expect(find.text('찜한 멘토 2'), findsOneWidget);
    // 전체 scope: 3명 모두 표시.
    expect(find.byType(MentorCard), findsNWidgets(3));
  });

  testWidgets('찜 scope 선택 → 찜한 멘토만 표시', (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(ids: <String>{'m1'});
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('찜한 멘토 1'));
    await tester.pumpAndSettle();

    expect(find.text('김수학'), findsOneWidget);
    expect(find.text('박영어'), findsNothing);
    expect(find.byType(MentorCard), findsNWidgets(1));
  });

  testWidgets('찜 scope + 검색 교집합', (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(ids: <String>{'m1', 'm2'});
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('찜한 멘토 2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '수학');
    await tester.pumpAndSettle();

    // 찜(m1,m2) ∩ 검색 '수학'(m1) = m1 만.
    expect(find.text('김수학'), findsOneWidget);
    expect(find.text('박영어'), findsNothing);
  });

  testWidgets('찜 조회 실패 → 오류+재시도(빈 상태로 위장 금지), 재시도 성공 시 목록',
      (WidgetTester tester) async {
    final _FakeFavorites fav =
        _FakeFavorites(ids: <String>{'m1'}, loadError: true);
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('찜한 멘토'));
    await tester.pumpAndSettle();

    // 오류 상태: '아직 찜한 멘토가 없어요'(empty)가 아니라 오류+재시도가 떠야 한다.
    expect(find.text('찜한 멘토를 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('아직 찜한 멘토가 없어요'), findsNothing);

    // 재시도 → 성공 → 찜 목록 표시.
    fav.loadError = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('김수학'), findsOneWidget);
    expect(find.text('찜한 멘토를 불러오지 못했어요.'), findsNothing);
  });

  testWidgets('찜 0개(성공) → 아직 찜한 멘토가 없어요(오류와 구분)', (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(ids: <String>{});
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('찜한 멘토 0'));
    await tester.pumpAndSettle();

    expect(find.text('아직 찜한 멘토가 없어요'), findsOneWidget);
    expect(find.text('찜한 멘토를 불러오지 못했어요.'), findsNothing);
  });

  testWidgets('찜 scope 에서 하트 해제 → 카드 즉시 제외 + 카운트 갱신',
      (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(ids: <String>{'m1', 'm2'});
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('찜한 멘토 2'));
    await tester.pumpAndSettle();
    expect(find.byType(MentorCard), findsNWidgets(2));

    await tester.tap(_heartOfCard('김수학'));
    await tester.pumpAndSettle();

    expect(find.text('김수학'), findsNothing); // 즉시 제외
    expect(find.byType(MentorCard), findsNWidgets(1));
    expect(find.text('찜한 멘토 1'), findsOneWidget);
    expect(fav.removeCalls, 1);
  });

  testWidgets('서버 실패 → 하트·카드 원복 + 안내', (WidgetTester tester) async {
    final _FakeFavorites fav =
        _FakeFavorites(ids: <String>{'m1'}, failOps: true);
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('찜한 멘토 1'));
    await tester.pumpAndSettle();
    expect(find.byType(MentorCard), findsNWidgets(1));

    await tester.tap(_heartOfCard('김수학'));
    await tester.pumpAndSettle();

    // 실패 → 원복: 카드가 다시 보이고 카운트 유지, 스낵바 안내.
    expect(find.text('김수학'), findsOneWidget);
    expect(find.text('찜한 멘토 1'), findsOneWidget);
    expect(find.text('찜 처리에 실패했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('하트 연타 → 서버 반영 1회, 최종 UI=서버 상태', (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(ids: <String>{});
    fav.opGate = Completer<bool>();
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    // 첫 탭 → add 시작(게이트 대기). 이어지는 연타는 in-flight 가드로 무시.
    await tester.tap(_heartOfCard('김수학'));
    await tester.pump();
    await tester.tap(_heartOfCard('김수학'));
    await tester.pump();
    await tester.tap(_heartOfCard('김수학'));
    await tester.pump();

    fav.opGate!.complete(true);
    await tester.pumpAndSettle();

    expect(fav.addCalls, 1);
    expect(fav.removeCalls, 0);
    expect(fav.ids, <String>{'m1'}); // 서버 최종 상태
    expect(find.text('찜한 멘토 1'), findsOneWidget); // UI 최종 상태 일치
  });

  testWidgets('상세 복귀 → 찜 카운트/목록 재동기화', (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(ids: <String>{});
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();
    expect(find.text('찜한 멘토 0'), findsOneWidget);

    // 카드 열기 → 상세 push. (테스트 환경: 백엔드 미구성 — 상세는 graceful 폴백)
    await tester.tap(find.text('김수학'));
    await tester.pumpAndSettle();
    expect(find.byType(MentorCard), findsNothing); // 상세로 전환됨

    // 상세에서 찜이 추가됐다고 가정(서버 상태 변경) 후 복귀.
    fav.ids.add('m1');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('찜한 멘토 1'), findsOneWidget); // 복귀 재조회 반영
  });

  testWidgets('로그인인데 찜 0 → 찜 scope 진입해도 전체 scope 복귀 없음(빈 상태 유지)',
      (WidgetTester tester) async {
    final _FakeFavorites fav = _FakeFavorites(ids: <String>{});
    await tester.pumpWidget(_wrap(
        MentorsScreen(directory: _FakeDirectory(mentors), favorites: fav)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('찜한 멘토 0'));
    await tester.pumpAndSettle();
    expect(find.text('아직 찜한 멘토가 없어요'), findsOneWidget);
    // 전체 카드가 새어 나오지 않는다.
    expect(find.byType(MentorCard), findsNothing);
  });
}
