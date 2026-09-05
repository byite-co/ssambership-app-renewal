/// 앱 전역 상수. 미확정 값은 '키만' 두고 값은 비운다(하드코딩 금지).
library;

class AppConstants {
  AppConstants._();

  /// 멘토 정산일 — 매월 23일 (확정값).
  static const int mentorPayoutDayOfMonth = 23;

  /// 앱 표시명 (브랜드).
  static const String appDisplayName = '쌤버십';

  /// 확정 앱 로고 에셋(졸업모자 + 말풍선 심볼, a91de81 승인본). 로그인 헤더·
  /// 스플래시 등 인앱 브랜드 마크이자 flutter_launcher_icons 원본 — 로고 교체
  /// 시 `dart run flutter_launcher_icons` 재실행으로 런처 아이콘을 함께 갱신한다.
  static const String brandLogoAsset = 'assets/branding/ssambership_logo_1024.png';

  /// 앱 표시 버전(마이페이지 설정 표기용). pubspec version 과 맞춘다.
  /// TODO: package_info_plus 도입 시 런타임 값으로 대체(현재는 표시 전용 상수).
  static const String appVersion = '1.0.0';

  /// 학생 하단 탭 5개(URL 순서와 동일).
  static const List<String> studentBottomTabLabels = <String>[
    '질문방',
    '개별질문',
    '멘토 찾기',
    '커뮤니티',
    '알림',
  ];

  /// 멘토 하단 탭 5개. 세 번째 표면은 멘토 찾기 대신 답변·정산 요약이다.
  static const List<String> mentorBottomTabLabels = <String>[
    '질문방',
    '개별질문',
    '정산',
    '커뮤니티',
    '알림',
  ];

  /// 마이페이지 화면 타이틀(하단 탭에서 빠져 push 라우트가 됨 — AppBar 표기용).
  static const String myPageTitle = '마이페이지';
}
