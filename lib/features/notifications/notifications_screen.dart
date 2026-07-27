import 'package:flutter/material.dart';

import '../../app/app_tabs.dart';
import '../../design/spacing_tokens.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
import '../../design/widgets/chip_scroll.dart';
import '../../design/widgets/count_badge.dart';
import '../../design/widgets/empty_state.dart';
import '../../shared/errors/friendly_error.dart';
import 'data/app_notification.dart';
import 'data/notifications_repository.dart';
import 'ui/widgets/notification_card.dart';

/// 페이지 항목을 기존 목록에 id 중복 없이 이어 붙인다(키셋 경계 중복 방어).
/// 화면과 테스트가 같은 경로를 쓴다. 실제 추가된 개수를 돌려준다.
int appendNotificationsDeduped(
  List<AppNotification> items,
  Set<String> seenIds,
  Iterable<AppNotification> page,
) {
  int added = 0;
  for (final AppNotification n in page) {
    if (seenIds.add(n.id)) {
      items.add(n);
      added++;
    }
  }
  return added;
}

/// 알림 센터(하단 4번째 탭). 받은 알림 조회·읽음 + 탭하면 관련 화면으로 이동(딥링크).
/// HomeShell 이 AppBar/하단탭을 제공하므로 본문만 구성한다(자체 Scaffold 없음).
///
/// ★ 조회·읽음 중심. 알림 '생성'은 서버/푸시 몫. 환불·미지 타입은 노출하고
///   목록 밖 타입은 '기타'로 일반 표시한다. 맞춤의뢰(CR) 2종은 게이트 OFF
///   (2026-07 출시)로 레포 쿼리 단계에서 제외돼 표시·필터·딥링크에 나타나지
///   않는다(서버 계약 17종은 불변 — notification_types 참조).
///   이동은 [notificationDestinationOf] 허용 목적지(탭 수준)만 — stay 타입
///   (unknown 등)은 읽음 처리만 하고 이동하지 않는다.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.repository,
    this.onDeepLinkTab,
  });

  /// 데이터 소스(기본: Supabase). 테스트에서 fake 주입.
  final NotificationsRepository? repository;

  /// 딥링크 탭 이동 훅(기본: TabNavigator.go). 테스트에서 대상 검증용 주입.
  final void Function(int tabIndex)? onDeepLinkTab;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const int _pageSize = 20;

  /// 필터 칩 구성('기타' 는 전용 칩 없이 전체에서만 노출).
  /// 맞춤의뢰 칩은 CR 게이트 OFF 로 미노출(전용 필터·카테고리 금지 — 해당
  /// 이벤트 자체가 레포 쿼리에서 제외되므로 칩이 있어도 빈 필터가 된다).
  static const List<NotificationKind?> _chipKinds = <NotificationKind?>[
    null, // 전체
    NotificationKind.questionRoom,
    NotificationKind.subscription,
    NotificationKind.individualQuestion,
  ];

  late final NotificationsRepository _repo;
  final List<AppNotification> _items = <AppNotification>[];
  final Set<String> _seenIds = <String>{};
  NotificationCursor? _next;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  /// 세대 토큰 — 새로고침 시 +1. 이전 세대의 응답(새로고침·더보기 모두)은 버린다.
  int _generation = 0;

  NotificationKind? _kind; // null = 전체

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? const SupabaseNotificationsRepository();
    _load();
  }

  /// 첫 로드 + 새로고침(첫 페이지부터 다시). 실패해도 기존 목록은 유지한다.
  Future<void> _load() async {
    final int gen = ++_generation;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final NotificationsPage page = await _repo.fetch(pageSize: _pageSize);
      if (!mounted || gen != _generation) return; // 낡은 응답 폐기
      setState(() {
        _items.clear();
        _seenIds.clear();
        appendNotificationsDeduped(_items, _seenIds, page.items);
        _next = page.next;
        _hasNext = page.hasNext;
        _loading = false;
        _loadingMore = false; // 이전 세대의 더보기 진행 표시 해제
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      if (_items.isEmpty) {
        setState(() {
          _error = e;
          _loading = false;
        });
      } else {
        // 기존 목록 유지 + 안내만(P2 요건: 로드 실패가 목록을 지우면 안 된다).
        setState(() => _loading = false);
        _showError('알림을 새로 불러오지 못했어요. ${friendlyError(e)}');
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasNext) return;
    final int gen = _generation;
    final NotificationCursor? cursor = _next;
    setState(() => _loadingMore = true);
    try {
      final NotificationsPage page =
          await _repo.fetch(after: cursor, pageSize: _pageSize);
      if (!mounted || gen != _generation) return; // 낡은 응답 폐기
      setState(() {
        appendNotificationsDeduped(_items, _seenIds, page.items);
        _next = page.next;
        _hasNext = page.hasNext;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() => _loadingMore = false);
      _showError('알림을 더 불러오지 못했어요. ${friendlyError(e)}');
    }
  }

  int get _unreadCount => _items.where((AppNotification n) => !n.isRead).length;

  List<AppNotification> get _filtered => _items.where((AppNotification n) {
        if (_kind != null && n.kind != _kind) return false;
        return true;
      }).toList();

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    try {
      await _repo.markRead(n.id);
    } catch (e) {
      // 실패 시 미읽음 상태 유지(성공 이후에만 UI 반영).
      _showError('읽음 처리에 실패했어요. ${friendlyError(e)}');
      return;
    }
    _applyRead(<String>{n.id});
  }

  Future<void> _markAll() async {
    if (_unreadCount == 0) return;
    try {
      // 서버 RPC 가 본인 미읽음 전체를 갱신 — id 목록을 보내지 않는다.
      await _repo.markAllRead();
    } catch (e) {
      // 실패 시 이전 상태 유지.
      _showError('모두 읽음 처리에 실패했어요. ${friendlyError(e)}');
      return;
    }
    _applyRead(_items.map((AppNotification n) => n.id).toSet());
  }

  void _applyRead(Set<String> ids) {
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _items.length; i++) {
        if (ids.contains(_items[i].id)) {
          _items[i] = _items[i].copyWith(isRead: true);
        }
      }
    });
  }

  void _open(AppNotification n) {
    _markRead(n); // 이동 여부와 무관하게 읽음 처리(이미 읽음이면 no-op).
    final int tab;
    switch (notificationDestinationOf(n.eventType)) {
      case NotificationDestination.questionRoomTab:
        tab = AppTab.questionRoom;
      case NotificationDestination.individualQuestionTab:
        tab = AppTab.individualQuestion;
      case NotificationDestination.myPage:
        tab = AppTab.myPage;
      case NotificationDestination.stay:
        return; // 이동 없음(맞춤의뢰·unknown 등) — 목록에 머문다.
    }
    (widget.onDeepLinkTab ?? TabNavigator.go)(tab);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          // 헤더 ↔ 첫 필터 줄 간격 확보(비좁음 해소): 하단 4→12. 전부 spacing 토큰 경유.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.s12,
            AppSpacing.s8,
            AppSpacing.s12,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                // D1-D: 미읽음 수를 카운트 배지로(스캔성↑). 0이면 배지 숨김.
                child: Row(
                  children: <Widget>[
                    const Text('안 읽음', style: AppType.title),
                    const SizedBox(width: 8),
                    CountBadge(count: _unreadCount),
                  ],
                ),
              ),
              if (_unreadCount > 0)
                TextButton(onPressed: _markAll, child: const Text('모두 읽음')),
            ],
          ),
        ),
        Padding(
          // 유형 필터 줄 ↔ 목록 첫 항목 간격 확보. 좌우 패딩은 다른 화면과 동일(screenH=20).
          padding: const EdgeInsets.only(bottom: AppSpacing.s20),
          child: ChipScroll(
            labels: <String>[
              for (final NotificationKind? k in _chipKinds)
                k == null ? '전체' : notificationKindLabel(k),
            ],
            selectedIndex: _kindChipIndex,
            onSelected: _onKindSelected,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  int get _kindChipIndex {
    final int i = _chipKinds.indexOf(_kind);
    return i < 0 ? 0 : i; // 기타는 전용 칩 없음 → 전체
  }

  void _onKindSelected(int i) {
    setState(() {
      _kind = (i >= 0 && i < _chipKinds.length) ? _chipKinds[i] : null;
    });
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('알림을 불러오지 못했어요.\n${friendlyError(_error!)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ColorTokens.danger)),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const EmptyState(
        icon: Icons.notifications_none_rounded,
        title: '새 알림이 없어요',
        message: '활동이 생기면 여기에 알려드릴게요',
      );
    }
    final List<AppNotification> items = _filtered;
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '조건에 맞는 알림이 없어요',
        message: '필터를 바꿔보세요.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH, 4, AppSpacing.screenH, 16),
        itemCount: items.length + (_hasNext ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          if (i >= items.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: _loadMore,
                        child: const Text('더 보기'),
                      ),
              ),
            );
          }
          final AppNotification n = items[i];
          return NotificationCard(
            notification: n,
            onOpen: () => _open(n),
            onMarkRead: () => _markRead(n),
          );
        },
      ),
    );
  }
}
