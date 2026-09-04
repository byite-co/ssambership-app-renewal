import 'package:flutter/foundation.dart';

import 'app_route_paths.dart';

/// 하단 탭의 canonical URL(딥링크·탭 전환 공용 상수).
///
/// 숫자 인덱스는 역할별 탭 순서가 달라지는 순간 의미가 바뀐다. 앱 내부의
/// 교차 화면 요청은 이 경로만 전달하고, 현재 역할의 표시 인덱스는 HomeShell 이
/// URL에서 계산한다.
class AppTab {
  AppTab._();

  static const String questionRoom = AppRoutePaths.rooms;
  static const String individualQuestion = AppRoutePaths.individualQuestions;
  static const String mentors = AppRoutePaths.mentors;
  static const String settlements = AppRoutePaths.settlements;
  static const String community = AppRoutePaths.community;
  static const String notifications = AppRoutePaths.notifications;

  /// 하단 탭이 아닌 우측 상단 프로필 목적지(push 라우트).
  static const String myPage = AppRoutePaths.myPage;
}

/// 앱 내 탭 전환 요청 채널.
///
/// 알림 딥링크 등에서 [go] 로 canonical 경로를 요청하면 HomeShell 이 수신해
/// URL을 바꾼다. 선택 상태의 정본은 이 채널 값이 아니라 라우터 URL이다.
class TabNavigator {
  TabNavigator._();

  /// null = 대기(요청 없음). HomeShell 이 처리 후 null 로 되돌린다.
  static final ValueNotifier<String?> request = ValueNotifier<String?>(null);

  static void go(String location) => request.value = location;
}
