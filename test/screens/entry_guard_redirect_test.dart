import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/entry_guard.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';

/// EntryGuard.redirect — AccessState × 위치별 진입 분기(순수 함수) 전수.
/// 라우터 없이 분기표만 검증한다(커버리지 공백 보강).
void main() {
  String? go(AccessState access, String location) =>
      EntryGuard.redirect(access: access, location: location);

  test('loading → 스플래시 고정', () {
    expect(go(AccessState.loading, '/home'), EntryGuard.splash);
    expect(go(AccessState.loading, EntryGuard.splash), isNull);
  });

  test('loggedOut → 로그인 고정(보호 경로 직접 접근 차단)', () {
    expect(go(AccessState.loggedOut, '/home'), EntryGuard.login);
    expect(go(AccessState.loggedOut, '/blocked'), EntryGuard.login);
    expect(go(AccessState.loggedOut, EntryGuard.login), isNull);
  });

  test('guest → 홈·로그인·공개 멘토 URL만 허용, 그 외는 홈으로', () {
    expect(go(AccessState.guest, EntryGuard.home), isNull);
    expect(go(AccessState.guest, EntryGuard.login), isNull);
    expect(go(AccessState.guest, '/mentors'), isNull);
    expect(go(AccessState.guest, '/mentors/mentor-1'), isNull);
    expect(go(AccessState.guest, '/mentors-copy/mentor-1'), EntryGuard.home);
    expect(go(AccessState.guest, '/community'), EntryGuard.home);
    expect(go(AccessState.guest, '/blocked'), EntryGuard.home);
    expect(go(AccessState.guest, EntryGuard.splash), EntryGuard.home);
  });

  test('full → 홈 고정(로그인·차단 화면 재진입 방지)', () {
    expect(go(AccessState.full, EntryGuard.home), isNull);
    expect(go(AccessState.full, EntryGuard.login), EntryGuard.home);
    expect(go(AccessState.full, '/blocked'), EntryGuard.home);
  });

  test('blocked → 차단 화면 고정(admin·banned·상태불명 공통)', () {
    expect(go(AccessState.blocked, EntryGuard.blocked), isNull);
    expect(go(AccessState.blocked, EntryGuard.home), EntryGuard.blocked);
    expect(go(AccessState.blocked, EntryGuard.login), EntryGuard.blocked);
  });

  test('dev 라우트는 가드 제외(개발 빌드 한정 등록 전제)', () {
    expect(go(AccessState.loggedOut, '/dev/gallery'), isNull);
    expect(go(AccessState.blocked, '/dev/s3'), isNull);
  });

  test('게스트 허용 탭은 커뮤니티(1)·멘토찾기(2)뿐', () {
    expect(EntryGuard.isTabAllowedForGuest(0), isFalse); // 질문방
    expect(EntryGuard.isTabAllowedForGuest(1), isTrue); // 커뮤니티
    expect(EntryGuard.isTabAllowedForGuest(2), isTrue); // 멘토찾기
    expect(EntryGuard.isTabAllowedForGuest(3), isFalse); // 알림
    expect(EntryGuard.isTabAllowedForGuest(4), isFalse); // 개별질문
    expect(EntryGuard.isTabAllowedForGuest(100), isFalse); // 마이페이지(가상)
  });
}
