import 'package:flutter/foundation.dart';

import 'community_models.dart';

/// 커뮤니티 목록 페이저 — 첫 로드/이어받기 상태와 세대 토큰을 한곳에서 관리한다
/// (thread_messages_controller 와 같은 '작은 ChangeNotifier 컨트롤러' 규약).
///
/// ★ P2-21 페이징 정합: 오프셋은 [CommunityPage.nextOffset](필터 전 rawCount
///   기준)으로만 전진 — 차단 필터로 items 가 줄어도 행 누락·중복이 없다.
/// ★ 세대 토큰: [refresh](새로고침·카테고리 전환) 시 증가. 이전 세대의 늦게
///   도착한 응답은 폐기해 빠른 전환 시 목록이 섞이지 않는다.
class CommunityPaginator<T> extends ChangeNotifier {
  CommunityPaginator({required this.fetch, this.pageSize = 20});

  /// 페이지 로더 — repository 호출을 감싼 클로저(offset, limit → 페이지).
  final Future<CommunityPage<T>> Function(int offset, int limit) fetch;

  /// 페이지당 요청 행 수.
  final int pageSize;

  final List<T> _items = <T>[];
  int _generation = 0; // refresh 마다 +1 — 스테일 응답 판별
  int _nextOffset = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  List<T> get items => List<T>.unmodifiable(_items);
  bool get initialLoading => _initialLoading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  Object? get error => _error;

  /// 첫 페이지부터 다시 로드(초기 진입·글 작성 후 새로고침·카테고리 전환).
  /// 진행 중이던 요청(이전 세대)의 응답은 도착해도 무시된다.
  Future<void> refresh() async {
    final int gen = ++_generation; // 이전 세대 무효화
    _items.clear();
    _nextOffset = 0;
    _initialLoading = true;
    _loadingMore = false;
    _hasMore = true;
    _error = null;
    notifyListeners();
    try {
      final CommunityPage<T> page = await fetch(0, pageSize);
      if (gen != _generation) return; // 스테일 응답 폐기
      _items.addAll(page.items);
      _nextOffset = page.nextOffset;
      _hasMore = page.hasMore;
      _initialLoading = false;
      notifyListeners();
    } catch (e) {
      if (gen != _generation) return;
      _error = e;
      _initialLoading = false;
      notifyListeners();
    }
  }

  /// 다음 페이지 이어받기(스크롤 하단 도달). 실패는 조용히(기존 목록 유지).
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _initialLoading || _error != null) return;
    final int gen = _generation;
    _loadingMore = true;
    notifyListeners();
    try {
      final CommunityPage<T> page = await fetch(_nextOffset, pageSize);
      if (gen != _generation) return; // refresh 가 끼어들었으면 폐기
      _items.addAll(page.items);
      _nextOffset = page.nextOffset;
      _hasMore = page.hasMore;
      _loadingMore = false;
      notifyListeners();
    } catch (_) {
      if (gen != _generation) return;
      _loadingMore = false;
      notifyListeners();
    }
  }
}
