import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/account_status.dart';

/// P2-22: 계정 유효 상태 판정 — 서버 규칙(lower(status)·suspended_until·탈퇴 잡)과 1:1.
/// 네트워크 미접촉: 손코딩 가짜 게이트웨이 주입(mocktail 금지 관례).
class _FakeGateway implements AccountStatusGateway {
  _FakeGateway({
    this.userRow,
    this.jobRows = const <Map<String, dynamic>>[],
    this.writeBlocked = false,
    this.userThrows = false,
    this.jobThrows = false,
    this.writeBlockedThrows = false,
  });

  final Map<String, dynamic>? userRow;
  final List<Map<String, dynamic>> jobRows;
  final bool writeBlocked;
  final bool userThrows;
  final bool jobThrows;
  final bool writeBlockedThrows;

  @override
  Future<Map<String, dynamic>?> fetchUserRow(String userId) async {
    if (userThrows) throw Exception('network down');
    return userRow;
  }

  @override
  Future<bool> fetchWriteBlocked(String userId) async {
    if (writeBlockedThrows) throw Exception('rpc down');
    // 실서버(SECURITY DEFINER RPC)와 동일한 판정을 흉내: 잡 행 기반 또는 강제 플래그.
    if (writeBlocked) return true;
    const Set<String> blocked = <String>{
      'locked',
      'purging',
      'storage_purged',
      'finalized',
      'auth_soft_deleted',
    };
    return jobRows.any((Map<String, dynamic> r) =>
        blocked.contains((r['state'] as String?)?.trim().toLowerCase()));
  }

  @override
  Future<Map<String, dynamic>> fetchDeletionSelfStatus() async {
    if (jobThrows) throw Exception('RPC: permission denied');
    // 서버 status_self 는 본인 잡 1건의 상태를 돌려준다 — 우선순위(write-block >
    // completed > pending > 기타)로 대표 상태를 뽑아 서버 의미를 흉내낸다.
    const Set<String> blocked = <String>{
      'locked',
      'purging',
      'storage_purged',
      'finalized',
      'auth_soft_deleted',
    };
    String? state;
    for (final Map<String, dynamic> r in jobRows) {
      final String s = (r['state'] as String?)?.trim().toLowerCase() ?? '';
      if (blocked.contains(s)) {
        state = s;
        break;
      }
    }
    state ??= jobRows
        .map((Map<String, dynamic> r) =>
            (r['state'] as String?)?.trim().toLowerCase() ?? '')
        .firstWhere((String s) => s == 'completed',
            orElse: () => jobRows
                .map((Map<String, dynamic> r) =>
                    (r['state'] as String?)?.trim().toLowerCase() ?? '')
                .firstWhere((String s) => s == 'pending',
                    orElse: () => jobRows.isEmpty
                        ? ''
                        : (jobRows.first['state'] as String?)
                                ?.trim()
                                .toLowerCase() ??
                            ''));
    return <String, dynamic>{
      'ok': true,
      'exists': jobRows.isNotEmpty,
      'state': state.isEmpty ? null : state,
      'write_blocked': blocked.contains(state),
      'can_cancel': state == 'pending',
    };
  }
}

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21, 12);
  DateTime clock() => now;

  Future<AccountState> resolve(_FakeGateway g) =>
      AccountStatusReader.resolve(g, 'u1', now: clock);

  group('users.status 판정(서버와 동일: lower 비교, 그 외 값은 active)', () {
    test('active → active(이용 가능)', () async {
      final AccountState s = await resolve(
          _FakeGateway(userRow: <String, dynamic>{'status': 'active'}));
      expect(s.kind, AccountStatusKind.active);
      expect(s.allowsAppUse, isTrue);
      expect(s.isBlocked, isFalse);
    });

    test('정본 밖 status 값(free text)은 서버와 동일하게 active 취급', () async {
      final AccountState s = await resolve(
          _FakeGateway(userRow: <String, dynamic>{'status': 'whatever'}));
      expect(s.kind, AccountStatusKind.active);
    });

    test('banned → banned(영구 차단·재시도 아님)', () async {
      final AccountState s = await resolve(
          _FakeGateway(userRow: <String, dynamic>{'status': 'banned'}));
      expect(s.kind, AccountStatusKind.banned);
      expect(s.isBlocked, isTrue);
      expect(s.isRetryable, isFalse);
      expect(s.blockedMessage, contains('제한된 계정'));
    });

    test('대소문자 무시: BANNED 도 banned(서버 lower(status) 비교와 동일)', () async {
      final AccountState s = await resolve(
          _FakeGateway(userRow: <String, dynamic>{'status': ' BANNED '}));
      expect(s.kind, AccountStatusKind.banned);
    });

    test('suspended + suspended_until 미래 → suspended(해제일 안내 포함)', () async {
      final AccountState s =
          await resolve(_FakeGateway(userRow: <String, dynamic>{
        'status': 'suspended',
        'suspended_until': '2026-08-01T00:00:00Z',
      }));
      expect(s.kind, AccountStatusKind.suspended);
      expect(s.suspendedUntil, isNotNull);
      expect(s.isBlocked, isTrue);
      expect(s.blockedMessage, contains('일시 정지'));
      expect(s.blockedMessage, contains('해제 예정'));
    });

    test('suspended + suspended_until 과거 → 서버와 동일하게 active 취급', () async {
      final AccountState s =
          await resolve(_FakeGateway(userRow: <String, dynamic>{
        'status': 'suspended',
        'suspended_until': '2026-01-01T00:00:00Z',
      }));
      expect(s.kind, AccountStatusKind.active);
      expect(s.allowsAppUse, isTrue);
    });

    test('suspended + suspended_until NULL → 무기한 정지(차단)', () async {
      final AccountState s =
          await resolve(_FakeGateway(userRow: <String, dynamic>{
        'status': 'suspended',
        'suspended_until': null,
      }));
      expect(s.kind, AccountStatusKind.suspended);
      expect(s.isBlocked, isTrue);
    });
  });

  group('account_deletion_jobs 판정', () {
    Map<String, dynamic> activeUser() => <String, dynamic>{'status': 'active'};

    test('pending → deletionPending(취소 창: 이용 허용 + 안내 문구)', () async {
      final AccountState s = await resolve(_FakeGateway(
        userRow: activeUser(),
        jobRows: <Map<String, dynamic>>[
          <String, dynamic>{'state': 'pending'},
        ],
      ));
      expect(s.kind, AccountStatusKind.deletionPending);
      expect(s.allowsAppUse, isTrue); // 서버가 쓰기를 막지 않는 구간
      expect(s.isBlocked, isFalse);
      // 안내 문구는 이 모델이 아니라 상시 배너(서버 cancelable_until)가 낸다 —
      // noticeMessage 는 폐기됐다. 차단 문구는 여기서 비어 있어야 한다.
      expect(s.blockedMessage, isEmpty);
    });

    test('locked/purging 등 write-block 상태 → deletionLocked(비복구 차단)', () async {
      for (final String state in <String>[
        'locked',
        'purging',
        'storage_purged',
        'finalized',
        'auth_soft_deleted',
      ]) {
        final AccountState s = await resolve(_FakeGateway(
          userRow: activeUser(),
          jobRows: <Map<String, dynamic>>[
            <String, dynamic>{'state': state},
          ],
        ));
        expect(s.kind, AccountStatusKind.deletionLocked, reason: state);
        expect(s.isBlocked, isTrue, reason: state);
        expect(s.isRetryable, isFalse, reason: state); // 자동/수동 재시도 무의미
        expect(s.blockedMessage, contains('탈퇴 처리가 진행 중'), reason: state);
      }
    });

    test('completed → deleted(재가입 안내·비복구)', () async {
      final AccountState s = await resolve(_FakeGateway(
        userRow: activeUser(),
        jobRows: <Map<String, dynamic>>[
          <String, dynamic>{'state': 'completed'},
        ],
      ));
      expect(s.kind, AccountStatusKind.deleted);
      expect(s.isRetryable, isFalse);
      expect(s.blockedMessage, contains('새로 가입'));
    });

    test('canceled/failed 잡은 없던 일로(active)', () async {
      final AccountState s = await resolve(_FakeGateway(
        userRow: activeUser(),
        jobRows: <Map<String, dynamic>>[
          <String, dynamic>{'state': 'canceled'},
          <String, dynamic>{'state': 'failed'},
        ],
      ));
      expect(s.kind, AccountStatusKind.active);
    });

    test('잡이 여러 개면 write-block > completed > pending 우선', () async {
      final AccountState s = await resolve(_FakeGateway(
        userRow: activeUser(),
        jobRows: <Map<String, dynamic>>[
          <String, dynamic>{'state': 'canceled'},
          <String, dynamic>{'state': 'pending'},
          <String, dynamic>{'state': 'locked'},
        ],
      ));
      expect(s.kind, AccountStatusKind.deletionLocked);
    });

    test('★fail-closed: 잡 행 select throw → fetchFailed(빈 목록 흡수 금지)', () async {
      final AccountState s = await resolve(_FakeGateway(
        userRow: activeUser(),
        jobThrows: true,
      ));
      expect(s.kind, AccountStatusKind.fetchFailed);
      expect(s.allowsAppUse, isFalse); // purging 일 수 있음 — 통과 금지
      expect(s.isRetryable, isTrue); // 재시도 가능한 차단으로 표시
    });

    test('★fail-closed: write-block RPC throw → fetchFailed(active 통과 금지)',
        () async {
      final AccountState s = await resolve(_FakeGateway(
        userRow: activeUser(),
        writeBlockedThrows: true,
      ));
      expect(s.kind, AccountStatusKind.fetchFailed);
      expect(s.allowsAppUse, isFalse);
      expect(s.isRetryable, isTrue);
    });

    test('write-block RPC true(직접 select 은 RLS 로 0행이어도) → deletionLocked',
        () async {
      // 스테이징 실측: account_deletion_jobs 는 정책 0개라 행 조회가 항상 비어 있다.
      // 그래도 RPC 가 true 면 차단해야 한다(정본은 RPC).
      final AccountState s = await resolve(_FakeGateway(
        userRow: activeUser(),
        writeBlocked: true,
        jobRows: const <Map<String, dynamic>>[], // RLS 로 가려진 상황
      ));
      expect(s.kind, AccountStatusKind.deletionLocked);
    });

    test('잡 0행 + write-block false → 정상 active(유일한 통과 경로)', () async {
      final AccountState s = await resolve(_FakeGateway(userRow: activeUser()));
      expect(s.kind, AccountStatusKind.active);
    });

    test('banned + pending 잡 → banned 이 우선(차단 유지)', () async {
      final AccountState s = await resolve(_FakeGateway(
        userRow: <String, dynamic>{'status': 'banned'},
        jobRows: <Map<String, dynamic>>[
          <String, dynamic>{'state': 'pending'},
        ],
      ));
      expect(s.kind, AccountStatusKind.banned);
    });
  });

  group('조회 실패 → fetchFailed(재시도 가능 차단 — active 도 banned 도 아님)', () {
    test('users read throw → fetchFailed', () async {
      final AccountState s = await resolve(_FakeGateway(userThrows: true));
      expect(s.kind, AccountStatusKind.fetchFailed);
      expect(s.allowsAppUse, isFalse); // 통과 금지(fail-closed)
      expect(s.isRetryable, isTrue); // 그러나 재시도 가능(영구 차단 문구 금지)
      expect(s.blockedMessage, contains('다시 시도'));
      expect(s.blockedMessage, isNot(contains('제한된 계정')));
    });

    test('users 행 없음 → fetchFailed(통과 금지·재시도 가능)', () async {
      final AccountState s = await resolve(_FakeGateway(userRow: null));
      expect(s.kind, AccountStatusKind.fetchFailed);
      expect(s.isRetryable, isTrue);
    });
  });

  group('C1: PrefetchedUserRowGateway(선조회 행 재사용)', () {
    test('선조회 행을 users 재조회 없이 그대로 반환하고 RPC 는 내부에 위임한다',
        () async {
      final AccountState s = await AccountStatusReader.resolve(
        PrefetchedUserRowGateway(
          inner: _FakeGateway(userRow: null), // inner 행은 쓰이면 안 됨
          userRow: <String, dynamic>{'status': 'active'},
          userRowFetchFailed: false,
        ),
        'u-1',
      );
      expect(s.kind, AccountStatusKind.active);
    });

    test('통합 조회 실패 플래그 → 기존 fetchUserRow throw 와 동일하게 fetchFailed',
        () async {
      final AccountState s = await AccountStatusReader.resolve(
        PrefetchedUserRowGateway(
          inner: _FakeGateway(userRow: <String, dynamic>{'status': 'active'}),
          userRow: null,
          userRowFetchFailed: true,
        ),
        'u-1',
      );
      expect(s.kind, AccountStatusKind.fetchFailed);
      expect(s.isRetryable, isTrue);
    });

    test('RPC 실패는 내부 게이트웨이 경유로 fail-closed 유지', () async {
      final AccountState s = await AccountStatusReader.resolve(
        PrefetchedUserRowGateway(
          inner: _FakeGateway(
            userRow: <String, dynamic>{'status': 'active'},
            writeBlockedThrows: true,
          ),
          userRow: <String, dynamic>{'status': 'active'},
          userRowFetchFailed: false,
        ),
        'u-1',
      );
      expect(s.kind, AccountStatusKind.fetchFailed);
    });
  });
}
