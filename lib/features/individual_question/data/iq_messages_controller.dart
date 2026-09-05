import 'package:flutter/foundation.dart';

import 'models/individual_question_models.dart';

/// IQ 대화 메시지 상태 컨트롤러 — 서버 재조회분과 실시간 수신분을 함께 모은다.
///
/// 질문방 ThreadMessagesController 의 dedup-by-id 패턴을 IQ 도메인 타입으로
/// 옮긴 것(도메인 결합 금지 — question_room 타입을 import 하지 않는다).
/// ★ 중복 id 는 무시(같은 메시지가 재조회 + 실시간으로 두 번 와도 1개만).
///   순서는 created_at 오름차순(시각 미상 행은 도착 순서 유지). append 전용.
class IqMessagesController extends ChangeNotifier {
  IqMessagesController([List<IqMessage> initial = const <IqMessage>[]]) {
    resetTo(initial, notify: false);
  }

  final List<IqMessage> _items = <IqMessage>[];
  final Set<String> _ids = <String>{};

  /// 안정 정렬용 도착 순번(id → seq). List.sort 는 불안정하므로 created_at
  /// 동률·미상 행이 뒤섞이지 않게 타이브레이커로 쓴다.
  final Map<String, int> _arrival = <String, int>{};
  int _nextArrival = 0;

  List<IqMessage> get items => List<IqMessage>.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  /// 서버 정본 행 반영(Realtime insert / 재조회 단건).
  /// 같은 id 가 이미 있으면 **서버 행으로 교체**(중복 행 0), 새 id 면 추가.
  bool upsertFromServer(IqMessage m) {
    final int i = _items.indexWhere((IqMessage e) => e.id == m.id);
    if (i < 0) {
      _ids.add(m.id);
      _arrival[m.id] = _nextArrival++;
      _items.add(m);
    } else {
      _items[i] = m;
    }
    _sort();
    notifyListeners();
    return true;
  }

  /// 전체 교체(재조회 결과 반영 — 서버 목록이 정본). [notify] false 면 알림 생략.
  void resetTo(List<IqMessage> list, {bool notify = true}) {
    _items.clear();
    _ids.clear();
    _arrival.clear();
    _nextArrival = 0;
    for (final IqMessage m in list) {
      if (_ids.add(m.id)) {
        _arrival[m.id] = _nextArrival++;
        _items.add(m);
      }
    }
    _sort();
    if (notify) notifyListeners();
  }

  /// 시각 미상(created_at null) 행의 비교 기준값 — epoch 0 으로 앞에 둔다.
  /// (실서버 행은 created_at 이 항상 있다 — null 은 방어적 경계.)
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  void _sort() {
    // ★ 비교기는 전순서(total order)여야 한다 — null 시각을 조건부로 건너뛰면
    //   비순환 조건이 깨져 정렬 결과가 비결정적이 된다.
    _items.sort((IqMessage a, IqMessage b) {
      final int c = (a.createdAt ?? _epoch).compareTo(b.createdAt ?? _epoch);
      if (c != 0) return c;
      // 시각 동률·미상 → 도착 순서 유지(안정화).
      return (_arrival[a.id] ?? 0).compareTo(_arrival[b.id] ?? 0);
    });
  }
}
