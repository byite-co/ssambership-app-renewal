import 'package:flutter/foundation.dart';

import 'account_status.dart';
import 'auth_service.dart' show AppRole;

/// 화면이 인증·역할 상태에 대해 **실제로 읽고 부르는 것만** 모은 최소 인터페이스.
///
/// 구현: 운영은 [AuthService](싱글턴 — 앱 시작 시 `AppScope` 에 실어 내려보낸다),
/// 테스트·골든은 손코딩 fake. 화면은 `AppScope.of(context).auth` 로만 접근하고
/// `AuthService.instance` 를 직접 부르지 않는다(A-2 의존성 주입 전환).
///
/// ★ 필요보다 넓히지 않는다 — 화면이 새 멤버를 쓰게 되면 그때 추가한다.
///   (displayName·roleLabel·bootstrap 등은 화면이 쓰지 않아 제외.)
abstract interface class AppAuth implements Listenable {
  /// 현재 역할(student/mentor/admin/guest). 화면 분기의 단일 소스.
  AppRole get currentRole;

  /// 게스트(둘러보기) 모드인지.
  bool get isGuest;

  /// 실제 세션이 있는지.
  bool get isSignedIn;

  /// 로그인 사용자 id. 세션이 없으면 null.
  /// (종전 화면들이 `SupabaseInit.clientOrNull?.auth.currentUser?.id` 로 직접 읽던 값.)
  String? get currentUserId;

  /// 계정 상태 스냅샷(차단·탈퇴 접수 등).
  AccountState get accountState;

  /// 차단 화면 문구.
  String get blockedMessage;

  /// 차단이 '재시도로 풀릴 수 있는 일시 조회 실패'인지(차단 화면 재시도 버튼).
  bool get isRecoverableBlock;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  void enterAsGuest();

  Future<void> signOut();

  /// 프로필(role·계정상태) 재조회 — 차단 화면 '다시 시도'.
  Future<void> reloadProfile();
}
