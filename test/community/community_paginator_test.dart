import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_paginator.dart';

/// P2-21 페이징 정합 — 차단 필터가 페이지 '안'에서 행을 줄여도
/// nextOffset(필터 전 rawCount 기준)으로 전진하므로 누락·중복이 없다.
/// 세대 토큰 — refresh 가 끼어들면 이전 세대의 늦은 응답은 폐기된다.
void main() {
  /// 실제 repo 의 페이지 조립을 흉내내는 fetch: DB 행 [db] 에서
  /// offset/limit 로 자른 뒤 [blocked] 를 필터해 CommunityPage 로 반환.
  Future<CommunityPage<String>> Function(int, int) dbFetch(
    List<String> db,
    Set<String> blocked,
  ) {
    return (int offset, int limit) async {
      final int start = offset.clamp(0, db.length);
      final int end = (offset + limit).clamp(0, db.length);
      final List<String> raw = db.sublist(start, end);
      final List<String> items =
          raw.where((String r) => !blocked.contains(r)).toList();
      return CommunityPage<String>(
        items: items,
        rawCount: raw.length,
        nextOffset: offset + raw.length,
        hasMore: raw.length == limit,
      );
    };
  }

  group('페이징 정합(차단 행 혼재)', () {
    test('DB 3페이지(limit 20)에 차단 행이 섞여도 누락·중복 없이 모두 수집된다', () async {
      // DB 60행, 매 7번째 행이 차단 작성자(페이지 경계 곳곳에 걸침).
      final List<String> db = List<String>.generate(60, (int i) => 'row$i');
      final Set<String> blocked = <String>{
        for (int i = 0; i < 60; i += 7) 'row$i',
      };
      final CommunityPaginator<String> pager = CommunityPaginator<String>(
        fetch: dbFetch(db, blocked),
        pageSize: 20,
      );

      await pager.refresh(); // 1페이지
      expect(pager.hasMore, isTrue);
      await pager.loadMore(); // 2페이지
      await pager.loadMore(); // 3페이지
      expect(pager.hasMore, isTrue); // 3페이지가 꽉 찼으므로 더 있을 수 있음
      await pager.loadMore(); // 4페이지(빈 페이지) → 끝
      expect(pager.hasMore, isFalse);

      final List<String> expected =
          db.where((String r) => !blocked.contains(r)).toList();
      expect(pager.items, expected); // 순서 보존 + 누락 없음
      expect(pager.items.toSet().length, pager.items.length); // 중복 없음
    });

    test('필터로 페이지 항목이 줄어도(items.length < limit) hasMore 는 rawCount 기준',
        () async {
      // 20행 중 5행 차단 → items 15개지만 rawCount=20 → hasMore=true.
      final List<String> db = List<String>.generate(25, (int i) => 'row$i');
      final Set<String> blocked = <String>{
        'row1',
        'row3',
        'row5',
        'row7',
        'row9',
      };
      final CommunityPaginator<String> pager = CommunityPaginator<String>(
        fetch: dbFetch(db, blocked),
        pageSize: 20,
      );

      await pager.refresh();
      expect(pager.items.length, 15);
      expect(pager.hasMore, isTrue); // ★ 15 < 20 이어도 계속(과거 버그: 여기서 멈춤)

      await pager.loadMore(); // offset 20(★ 15 아님) → row20~24
      expect(pager.items.length, 20); // 15 + 5 (row20~24, 누락 없음)
      expect(pager.items.contains('row15'), isTrue); // 과거 버그: 중복되던 구간
      expect(pager.items.toSet().length, pager.items.length);
      expect(pager.hasMore, isFalse); // rawCount 5 < 20
    });
  });

  group('세대 토큰(스테일 응답 폐기)', () {
    test('refresh 중 다시 refresh(카테고리 전환) → 먼저 요청한 응답은 무시된다', () async {
      final List<Completer<CommunityPage<String>>> pending =
          <Completer<CommunityPage<String>>>[];
      final CommunityPaginator<String> pager = CommunityPaginator<String>(
        fetch: (int offset, int limit) {
          final Completer<CommunityPage<String>> c =
              Completer<CommunityPage<String>>();
          pending.add(c);
          return c.future;
        },
        pageSize: 20,
      );

      final Future<void> first = pager.refresh(); // 세대 1(예: '전체')
      final Future<void> second = pager.refresh(); // 세대 2(예: '학습법')

      CommunityPage<String> page(List<String> items) => CommunityPage<String>(
            items: items,
            rawCount: items.length,
            nextOffset: items.length,
            hasMore: false,
          );

      // 새 세대(두 번째) 응답이 먼저 도착.
      pending[1].complete(page(<String>['new1', 'new2']));
      await second;
      expect(pager.items, <String>['new1', 'new2']);

      // 이전 세대(첫 번째) 응답이 늦게 도착 → 폐기(목록 오염 없음).
      pending[0].complete(page(<String>['stale1']));
      await first;
      expect(pager.items, <String>['new1', 'new2']);
      expect(pager.initialLoading, isFalse);
    });

    test('loadMore 진행 중 refresh → 늦게 온 loadMore 응답은 폐기된다', () async {
      final List<Completer<CommunityPage<String>>> pending =
          <Completer<CommunityPage<String>>>[];
      final CommunityPaginator<String> pager = CommunityPaginator<String>(
        fetch: (int offset, int limit) {
          final Completer<CommunityPage<String>> c =
              Completer<CommunityPage<String>>();
          pending.add(c);
          return c.future;
        },
        pageSize: 2,
      );

      CommunityPage<String> page(List<String> items,
              {required int nextOffset, required bool hasMore}) =>
          CommunityPage<String>(
            items: items,
            rawCount: items.length,
            nextOffset: nextOffset,
            hasMore: hasMore,
          );

      final Future<void> first = pager.refresh();
      pending[0]
          .complete(page(<String>['a', 'b'], nextOffset: 2, hasMore: true));
      await first;

      final Future<void> more = pager.loadMore(); // 진행 중…
      final Future<void> second = pager.refresh(); // 세대 교체
      pending[2]
          .complete(page(<String>['fresh'], nextOffset: 1, hasMore: false));
      await second;

      // 이전 세대의 loadMore 응답이 늦게 도착 → 폐기.
      pending[1]
          .complete(page(<String>['c', 'd'], nextOffset: 4, hasMore: true));
      await more;

      expect(pager.items, <String>['fresh']);
      expect(pager.hasMore, isFalse);
      expect(pager.loadingMore, isFalse);
    });
  });

  test('loadMore 실패는 조용히 — 기존 목록 유지, loadingMore 해제', () async {
    int calls = 0;
    final CommunityPaginator<String> pager = CommunityPaginator<String>(
      fetch: (int offset, int limit) async {
        calls++;
        if (calls == 1) {
          return const CommunityPage<String>(
            items: <String>['a', 'b'],
            rawCount: 2,
            nextOffset: 2,
            hasMore: true,
          );
        }
        throw Exception('network');
      },
      pageSize: 2,
    );
    await pager.refresh();
    await pager.loadMore();
    expect(pager.items, <String>['a', 'b']);
    expect(pager.error, isNull); // 이어받기 실패는 error 로 승격하지 않음
    expect(pager.loadingMore, isFalse);
  });
}
