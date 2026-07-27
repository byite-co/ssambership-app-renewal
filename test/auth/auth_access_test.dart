import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/account_status.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';

/// P2-22: 진입 분기(computeAccess)·재시도 가능 차단(computeRecoverableBlock) 순수 판정.
/// 조회 실패는 절대 full 통과 금지(fail-closed)이되 '재시도 가능 차단'이어야 한다.
void main() {
  AccessState access({
    AppRole role = AppRole.student,
    bool roleFetchFailed = false,
    AccountState account = AccountState.active,
    bool signedIn = true,
  }) =>
      AuthService.computeAccess(
        bootstrapping: false,
        signedIn: signedIn,
        guest: false,
        role: role,
        roleFetchFailed: roleFetchFailed,
        account: account,
      );

  bool recoverable({
    AppRole role = AppRole.student,
    bool roleFetchFailed = false,
    AccountState account = AccountState.active,
  }) =>
      AuthService.computeRecoverableBlock(
        signedIn: true,
        role: role,
        roleFetchFailed: roleFetchFailed,
        account: account,
      );

  test('active + student/mentor → full', () {
    expect(access(role: AppRole.student), AccessState.full);
    expect(access(role: AppRole.mentor), AccessState.full);
  });

  test('계정 상태 조회 실패(fetchFailed) → full 아님 + 재시도 가능 차단', () {
    final AccessState a = access(account: AccountState.fetchFailed);
    expect(a, AccessState.blocked);
    expect(a, isNot(AccessState.full)); // 실패를 active 로 취급 금지
    expect(recoverable(account: AccountState.fetchFailed), isTrue);
  });

  test('role 조회 실패 → active 취급 금지(차단) + 재시도 가능', () {
    // role read 가 throw 하면 guest 폴백이 아니라 '실패' 표식으로 차단·재시도.
    final AccessState a = access(role: AppRole.guest, roleFetchFailed: true);
    expect(a, AccessState.blocked);
    expect(recoverable(role: AppRole.guest, roleFetchFailed: true), isTrue);
    // 계정 상태가 active 여도 role 실패면 full 로 통과하지 않는다.
    expect(access(role: AppRole.student, roleFetchFailed: true),
        AccessState.blocked);
  });

  test('banned/suspended → 차단(재시도 아님)', () {
    const AccountState banned = AccountState(kind: AccountStatusKind.banned);
    const AccountState suspended =
        AccountState(kind: AccountStatusKind.suspended);
    expect(access(account: banned), AccessState.blocked);
    expect(recoverable(account: banned), isFalse);
    expect(access(account: suspended), AccessState.blocked);
    expect(recoverable(account: suspended), isFalse);
  });

  test('deletionLocked/deleted → 비복구 차단(재시도 버튼·자동 재시도 없음)', () {
    const AccountState locked =
        AccountState(kind: AccountStatusKind.deletionLocked);
    const AccountState deleted = AccountState(kind: AccountStatusKind.deleted);
    expect(access(account: locked), AccessState.blocked);
    expect(recoverable(account: locked), isFalse);
    expect(access(account: deleted), AccessState.blocked);
    expect(recoverable(account: deleted), isFalse);
  });

  test('deletionPending(취소 창) → 이용 허용(full) — 서버도 쓰기를 막지 않음', () {
    const AccountState pending =
        AccountState(kind: AccountStatusKind.deletionPending);
    expect(access(account: pending), AccessState.full);
  });

  test('admin → 차단(계정이 정상이어도) + 재시도 아님', () {
    expect(access(role: AppRole.admin), AccessState.blocked);
    expect(recoverable(role: AppRole.admin), isFalse);
    // admin 은 상태 조회가 실패했어도 재시도 안내 대상이 아니다(어차피 차단).
    expect(recoverable(role: AppRole.admin, account: AccountState.fetchFailed),
        isFalse);
  });

  test('role 불명(행에 역할 없음·실패 아님) → 차단이되 재시도 아님', () {
    expect(access(role: AppRole.guest), AccessState.blocked);
    expect(recoverable(role: AppRole.guest), isFalse);
  });

  test('부팅 중/로그아웃/게스트 분기 유지', () {
    expect(
      AuthService.computeAccess(
        bootstrapping: true,
        signedIn: false,
        guest: false,
        role: AppRole.guest,
        roleFetchFailed: false,
        account: AccountState.fetchFailed,
      ),
      AccessState.loading,
    );
    expect(access(signedIn: false), AccessState.loggedOut);
    expect(
      AuthService.computeAccess(
        bootstrapping: false,
        signedIn: false,
        guest: true,
        role: AppRole.guest,
        roleFetchFailed: false,
        account: AccountState.fetchFailed,
      ),
      AccessState.guest,
    );
  });
}
