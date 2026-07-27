import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/push/push_ports.dart';
import 'package:ssambership_app/features/mypage/data/notification_settings_repository.dart';
import 'package:ssambership_app/features/mypage/ui/sections/settings_section.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 설정 섹션 — 로그아웃 버튼, 알림 설정(마스터+그룹 토글) 로드/저장/실패 처리,
/// OS 권한 거부 안내(서버 설정과 별개). 페이크 포트 주입으로 검증(백엔드 불필요).

/// 설정 저장소 페이크 — 로드/저장 결과를 시나리오별로 주입.
class FakeSettingsPort implements NotificationSettingsPort {
  FakeSettingsPort({
    NotificationSettings settings = const NotificationSettings(),
    this.loadError,
    this.saveError,
  }) : _settings = settings;

  NotificationSettings _settings;
  Object? loadError;
  Object? saveError;
  int loadCalls = 0;
  final List<NotificationSettings> saved = <NotificationSettings>[];

  @override
  Future<NotificationSettings> load() async {
    loadCalls++;
    if (loadError != null) throw loadError!;
    return _settings;
  }

  @override
  Future<void> save(NotificationSettings settings) async {
    if (saveError != null) throw saveError!;
    saved.add(settings);
    _settings = settings;
  }
}

/// OS 권한 페이크 — 고정 상태 반환(요청은 호출되지 않아야 정상).
class FakePermissionPort implements PushPermissionPort {
  FakePermissionPort(this.status);

  PushPermissionStatus status;
  int requestCalls = 0;

  @override
  Future<PushPermissionStatus> current() async => status;

  @override
  Future<PushPermissionStatus> request() async {
    requestCalls++;
    return status;
  }
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Future<void> _pumpSection(
  WidgetTester tester, {
  required FakeSettingsPort settings,
  FakePermissionPort? permission,
  VoidCallback? onLogout,
  bool showLogout = true,
}) async {
  await tester.pumpWidget(_wrap(SettingsSection(
    onLogout: onLogout ?? () {},
    showLogout: showLogout,
    settingsRepository: settings,
    permissionPort:
        permission ?? FakePermissionPort(PushPermissionStatus.granted),
  )));
  // 비동기 로드(권한 조회 → 설정 로드) 완료까지 펌프.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('로그아웃 버튼이 존재하고 탭하면 onLogout 콜백이 호출된다',
      (WidgetTester tester) async {
    int logouts = 0;
    await _pumpSection(tester,
        settings: FakeSettingsPort(), onLogout: () => logouts++);

    expect(find.text('로그아웃'), findsOneWidget);
    await tester.tap(find.text('로그아웃'));
    await tester.pump();
    expect(logouts, 1);
  });

  testWidgets('showLogout=false(게스트)면 로그아웃 버튼 비표시',
      (WidgetTester tester) async {
    await _pumpSection(tester, settings: FakeSettingsPort(), showLogout: false);
    expect(find.text('로그아웃'), findsNothing);
  });

  testWidgets('약관·개인정보·앱 버전 행이 렌더된다', (WidgetTester tester) async {
    await _pumpSection(tester, settings: FakeSettingsPort());
    expect(find.text('이용약관'), findsOneWidget);
    expect(find.text('개인정보 처리방침'), findsOneWidget);
    expect(find.text('앱 버전'), findsOneWidget);
    expect(find.text('0.1.0'), findsOneWidget); // AppConstants.appVersion
  });

  testWidgets('로드된 값으로 마스터+그룹 5개 토글이 렌더된다(qna만 off)',
      (WidgetTester tester) async {
    final FakeSettingsPort port = FakeSettingsPort(
      settings: const NotificationSettings(
        pushEnabled: true,
        groups: <String, bool>{'qna': false},
      ),
    );
    await _pumpSection(tester, settings: port);

    expect(find.text('알림 받기'), findsOneWidget);
    for (final String key in NotificationGroups.keys) {
      expect(find.text(NotificationGroups.labelOf(key)), findsOneWidget);
    }
    // 스위치 6개: [0]=마스터, [1..5]=그룹(keys 순서).
    expect(find.byType(Switch), findsNWidgets(6));
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse,
        reason: 'qna 는 저장값 false');
    expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, isTrue,
        reason: 'order 는 키 없음=ON');
  });

  testWidgets('마스터가 꺼져 있으면 그룹 토글은 잠긴다(서버가 전부 차단)', (WidgetTester tester) async {
    final FakeSettingsPort port = FakeSettingsPort(
      settings: const NotificationSettings(pushEnabled: false),
    );
    await _pumpSection(tester, settings: port);

    for (int i = 1; i <= 5; i++) {
      expect(tester.widget<Switch>(find.byType(Switch).at(i)).onChanged, isNull,
          reason: '그룹 토글 $i 는 비활성');
    }
    // 마스터는 다시 켤 수 있어야 한다.
    expect(
        tester.widget<Switch>(find.byType(Switch).at(0)).onChanged, isNotNull);
  });

  testWidgets('토글 저장 성공 시 값이 유지되고 저장소로 전달된다', (WidgetTester tester) async {
    final FakeSettingsPort port = FakeSettingsPort();
    await _pumpSection(tester, settings: port);

    await tester.tap(find.byType(Switch).at(1)); // qna 끄기.
    await tester.pump();
    await tester.pump();

    expect(port.saved, hasLength(1));
    expect(port.saved.single.groupEnabled('qna'), isFalse);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
  });

  testWidgets('저장 실패 시 토글이 원복되고 스낵바가 뜬다(재시도 가능)', (WidgetTester tester) async {
    final FakeSettingsPort port = FakeSettingsPort(
      saveError: const AppError('알림 설정을 저장하지 못했어요.'),
    );
    await _pumpSection(tester, settings: port);

    // 마스터 끄기 시도 → 낙관 반영 후 실패 → 원복(ON).
    await tester.tap(find.byType(Switch).at(0));
    await tester.pump();
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue,
        reason: '저장 실패면 성공한 척하지 않고 원복');
    expect(find.textContaining('저장에 실패했어요'), findsOneWidget);
    // 실패 후에도 토글은 다시 조작 가능(재시도).
    expect(
        tester.widget<Switch>(find.byType(Switch).at(0)).onChanged, isNotNull);
    expect(port.saved, isEmpty);
  });

  testWidgets('로드 실패 시 기본값 대신 재시도 안내를 보여주고, 재시도로 복구된다',
      (WidgetTester tester) async {
    final FakeSettingsPort port = FakeSettingsPort(
      loadError: const AppError('알림 설정을 불러오지 못했어요.'),
    );
    await _pumpSection(tester, settings: port);

    // 토글을 기본값(ON)처럼 보여주지 않는다 — 실패 안내 + 다시 시도만.
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    // 백엔드 복구 후 재시도 → 토글 표시.
    port.loadError = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Switch), findsNWidgets(6));
    expect(port.loadCalls, 2);
  });

  testWidgets('OS 권한 거부면 서버 설정 ON 이어도 별도 안내가 뜬다(자동 요청 없음)',
      (WidgetTester tester) async {
    final FakePermissionPort permission =
        FakePermissionPort(PushPermissionStatus.denied);
    await _pumpSection(tester,
        settings: FakeSettingsPort(), permission: permission);

    // 서버 토글은 ON 인 채로, 기기 권한 안내가 '별개'로 표시된다.
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue);
    expect(find.textContaining('기기 알림 권한이 꺼져 있어요'), findsOneWidget);
    expect(permission.requestCalls, 0, reason: '여기서는 권한을 요청하지 않는다');
  });

  testWidgets('OS 권한이 허용/미결정이면 권한 안내가 없다(서버 OFF 와 구분)',
      (WidgetTester tester) async {
    await _pumpSection(
      tester,
      settings: FakeSettingsPort(
          settings: const NotificationSettings(pushEnabled: false)),
      permission: FakePermissionPort(PushPermissionStatus.granted),
    );
    // 서버 마스터 OFF 상태여도 기기 권한 안내는 뜨지 않는다(별개 상태).
    expect(find.textContaining('기기 알림 권한'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isFalse);
  });
}
