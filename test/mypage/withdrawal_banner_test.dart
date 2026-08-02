import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/home_shell.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/auth/deletion_notice_controller.dart';
import 'package:ssambership_app/features/mypage/data/account_deletion_repository.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/mypage_screen.dart';
import 'package:ssambership_app/shared/widgets/withdrawal_pending_banner.dart';

/// §5 — 탈퇴 예약 상시 배너.
///
/// 정본은 서버 self RPC `account_deletion_status_self()` 하나뿐이다.
/// 여기서 고정하는 계약:
/// - 노출·취소버튼은 서버 반환값으로만 판정(로컬 시계 계산·자체 판정 금지).
/// - can_cancel 부재·판정 불가·locked/purging → 취소 버튼 비노출(fail-closed).
/// - 앱 재시작·재로그인 후 배너는 서버 재조회로만 복원(로컬 캐시 의존 0).
/// 실제 삭제 RPC 는 절대 호출하지 않는다(전부 fake port).

/// 호출 시점 상태를 돌려주는 fake — 실제 탈퇴 RPC 미접촉.
class _FakePort implements AccountDeletionPort {
  _FakePort(this.status);

  DeletionStatusResult? status;
  int statusCalls = 0;

  /// 설정 시 다음 fetchStatus 가 이 future 를 돌려준다(늦은 응답·실패 주입).
  Future<DeletionStatusResult>? statusOverride;

  @override
  Future<DeletionStatusResult> fetchStatus() {
    statusCalls++;
    final Future<DeletionStatusResult>? o = statusOverride;
    if (o != null) {
      statusOverride = null;
      return o;
    }
    final DeletionStatusResult? s = status;
    if (s == null) {
      return Future<DeletionStatusResult>.error(
          StateError('status unavailable'));
    }
    return Future<DeletionStatusResult>.value(s);
  }

  @override
  Future<DeletionRequestOutcome> requestDeletion() async =>
      throw StateError('탈퇴 요청은 배너에서 호출하지 않는다');

  @override
  Future<DeletionRequestOutcome> requestDeletionWithForfeitConsent({
    required int acknowledgedBalanceCents,
  }) async =>
      throw StateError('잔액 소멸 동의 RPC 도 배너에서 호출하지 않는다');

  @override
  Future<DeletionCancelResult> cancelDeletion() async =>
      throw StateError('취소 RPC 는 배너가 직접 호출하지 않는다');
}

DeletionStatusResult _pending({
  bool canCancel = true,
  DateTime? cancelableUntil,
  bool writeBlocked = false,
  String state = 'pending',
}) =>
    DeletionStatusResult(
      exists: true,
      state: state,
      cancelableUntil: cancelableUntil,
      writeBlocked: writeBlocked,
      canCancel: canCancel,
    );

Widget _host(DeletionNoticeController c,
        {Future<void> Function(BuildContext)? onOpenCancel}) =>
    MaterialApp(
      home: Scaffold(
        body: WithdrawalPendingBanner(
          controllerOverride: c,
          onOpenCancel: onOpenCancel,
        ),
      ),
    );

const String _title = '탈퇴 요청이 접수된 계정이에요';
final Finder _cancelButton =
    find.byKey(const ValueKey<String>('withdrawal-banner-cancel'));

void main() {
  group('§5-1 상시 배너 노출 — 서버 정본', () {
    testWidgets('pending 이면 배너를 띄운다', (WidgetTester tester) async {
      final DeletionNoticeController c =
          DeletionNoticeController(port: _FakePort(_pending()));
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('탈퇴 잡이 없으면(exists=false) 배너 없음', (WidgetTester tester) async {
      final DeletionNoticeController c = DeletionNoticeController(
        port: _FakePort(const DeletionStatusResult(
            exists: false, writeBlocked: false, canCancel: false)),
      );
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
    });

    testWidgets('조회 실패는 배너를 만들지 않는다(fail-closed — 단정 금지)',
        (WidgetTester tester) async {
      final DeletionNoticeController c =
          DeletionNoticeController(port: _FakePort(null));
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
    });

    testWidgets('canceled/failed/completed 는 배너 없음(없던 일·이용 종료)',
        (WidgetTester tester) async {
      for (final String state in <String>['canceled', 'failed', 'completed']) {
        final DeletionNoticeController c = DeletionNoticeController(
          port: _FakePort(_pending(state: state, canCancel: false)),
        );
        await tester.pumpWidget(_host(c));
        await tester.pumpAndSettle();
        expect(find.text(_title), findsNothing, reason: 'state=$state');
      }
    });
  });

  group('§5-2 취소 가능 시각(cancelable_until) 표시', () {
    testWidgets('서버가 준 cancelable_until 을 로컬 시각으로 표시한다',
        (WidgetTester tester) async {
      final DateTime until = DateTime.utc(2026, 7, 25, 6, 30);
      final DeletionNoticeController c = DeletionNoticeController(
        port: _FakePort(_pending(cancelableUntil: until)),
      );
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();

      final DateTime local = until.toLocal();
      final String mm = local.minute.toString().padLeft(2, '0');
      final String hh = local.hour.toString().padLeft(2, '0');
      expect(
        find.text(
            '${local.year}년 ${local.month}월 ${local.day}일 $hh:$mm까지 취소할 수 있어요'),
        findsOneWidget,
      );
    });

    testWidgets('cancelable_until 이 없으면 마감 문구를 만들지 않는다(로컬 추정 금지)',
        (WidgetTester tester) async {
      final DeletionNoticeController c = DeletionNoticeController(
        port: _FakePort(_pending()),
      );
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(find.textContaining('까지 취소할 수 있어요'), findsNothing);
    });
  });

  group('§5-3 취소 버튼은 서버 can_cancel 로만 판정(fail-closed)', () {
    testWidgets('can_cancel=true → 버튼 노출', (WidgetTester tester) async {
      final DeletionNoticeController c =
          DeletionNoticeController(port: _FakePort(_pending()));
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(_cancelButton, findsOneWidget);
    });

    testWidgets('can_cancel=false → 버튼 비노출(배너는 유지)',
        (WidgetTester tester) async {
      final DeletionNoticeController c = DeletionNoticeController(
        port: _FakePort(_pending(canCancel: false)),
      );
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(_cancelButton, findsNothing);
    });

    testWidgets('취소창 경과(can_cancel=false + 과거 마감) → 버튼 비노출',
        (WidgetTester tester) async {
      final DeletionNoticeController c = DeletionNoticeController(
        port: _FakePort(_pending(
          canCancel: false,
          cancelableUntil: DateTime.utc(2020, 1, 1),
        )),
      );
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(_cancelButton, findsNothing);
    });

    testWidgets('배너는 취소 RPC 를 직접 호출하지 않는다(기존 탈퇴 화면으로 위임)',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(_pending());
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      int opened = 0;
      await tester.pumpWidget(_host(c, onOpenCancel: (BuildContext _) async {
        opened++;
      }));
      await tester.pumpAndSettle();
      await tester.tap(_cancelButton);
      await tester.pumpAndSettle();
      // cancelDeletion 을 직접 불렀다면 _FakePort 가 throw 해 테스트가 깨진다.
      expect(opened, 1);
    });

    testWidgets('취소 화면에서 돌아오면 서버 상태로 재판정한다', (WidgetTester tester) async {
      final _FakePort port = _FakePort(_pending());
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      await tester.pumpWidget(_host(c, onOpenCancel: (BuildContext _) async {
        // 탈퇴 화면에서 취소 성공 → 서버는 더 이상 잡이 없다고 답한다.
        port.status = const DeletionStatusResult(
            exists: false, writeBlocked: false, canCancel: false);
      }));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);

      await tester.tap(_cancelButton);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing, reason: '복귀 후 서버 기준 재판정');
    });
  });

  group('§5-4 locked/purging 은 배너에서도 취소 버튼 제거', () {
    testWidgets('write_blocked=true 면 서버가 can_cancel 을 줘도 버튼을 만들지 않는다',
        (WidgetTester tester) async {
      final DeletionNoticeController c = DeletionNoticeController(
        port: _FakePort(_pending(
          state: 'locked',
          writeBlocked: true,
          canCancel: true, // 방어적 이중 게이트 검증(정상 서버는 false 를 준다)
        )),
      );
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(_cancelButton, findsNothing);
    });

    testWidgets('purging·storage_purged·finalized·auth_soft_deleted 전부 버튼 없음',
        (WidgetTester tester) async {
      for (final String state in <String>[
        'purging',
        'storage_purged',
        'finalized',
        'auth_soft_deleted',
      ]) {
        final DeletionNoticeController c = DeletionNoticeController(
          port: _FakePort(
              _pending(state: state, writeBlocked: true, canCancel: true)),
        );
        await tester.pumpWidget(_host(c));
        await tester.pumpAndSettle();
        expect(find.text(_title), findsOneWidget, reason: 'state=$state');
        expect(_cancelButton, findsNothing, reason: 'state=$state');
      }
    });

    testWidgets('pending 이 아니면 can_cancel 이 참이어도 버튼 없음',
        (WidgetTester tester) async {
      final DeletionNoticeController c = DeletionNoticeController(
        port: _FakePort(
            _pending(state: 'locked', writeBlocked: false, canCancel: true)),
      );
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(_cancelButton, findsNothing);
    });
  });

  group('§5-5 재실행·재로그인 지속(서버 상태 기준 복원)', () {
    testWidgets('새 컨트롤러(앱 재시작 상당)는 서버 재조회로 배너를 복원한다',
        (WidgetTester tester) async {
      // 1회차 실행.
      final DeletionNoticeController first =
          DeletionNoticeController(port: _FakePort(_pending()));
      await tester.pumpWidget(_host(first));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);

      // 앱 종료 상당 — 위젯·컨트롤러 폐기.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // 재시작: 로컬에 남은 것 없이 새 컨트롤러가 서버에서 다시 읽어온다.
      final _FakePort restarted = _FakePort(_pending());
      final DeletionNoticeController second =
          DeletionNoticeController(port: restarted);
      await tester.pumpWidget(_host(second));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(restarted.statusCalls, greaterThan(0), reason: '서버 재조회로 복원');
    });

    testWidgets('재시작 후 서버가 잡 없음이라 하면 배너는 복원되지 않는다(로컬 캐시 의존 0)',
        (WidgetTester tester) async {
      final DeletionNoticeController first =
          DeletionNoticeController(port: _FakePort(_pending()));
      await tester.pumpWidget(_host(first));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // 앱이 꺼져 있는 동안 웹에서 탈퇴를 취소했다 → 서버는 잡 없음.
      final DeletionNoticeController second = DeletionNoticeController(
        port: _FakePort(const DeletionStatusResult(
            exists: false, writeBlocked: false, canCancel: false)),
      );
      await tester.pumpWidget(_host(second));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
    });

    testWidgets('재로그인(clear) 후 늦게 도착한 이전 계정 응답은 배너를 되살리지 않는다(세대 guard)',
        (WidgetTester tester) async {
      final Completer<DeletionStatusResult> slow =
          Completer<DeletionStatusResult>();
      final _FakePort port = _FakePort(_pending());
      port.statusOverride = slow.future;
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      await tester.pumpWidget(_host(c));
      await tester.pump();
      expect(find.text(_title), findsNothing);

      // 로그아웃·계정 전환.
      c.clear();
      await tester.pumpAndSettle();

      // 이전 계정의 pending 응답이 뒤늦게 도착 — 새 계정 화면에 배너가 뜨면 안 된다.
      slow.complete(_pending());
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing, reason: '이전 계정 응답 폐기');
    });

    test('clear 후에는 ensureLoaded 가 다시 서버를 조회한다(계정 전환 누수 0)', () async {
      final _FakePort port = _FakePort(_pending());
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      await c.ensureLoaded();
      expect(c.showsNotice, isTrue);
      expect(port.statusCalls, 1);

      // 로그아웃 — 이전 사용자 상태를 남기지 않는다.
      c.clear();
      expect(c.showsNotice, isFalse);
      expect(c.isLoaded, isFalse);

      // 다음 사용자는 잡이 없다 → 재조회 후에도 배너 없음.
      port.status = const DeletionStatusResult(
          exists: false, writeBlocked: false, canCancel: false);
      await c.ensureLoaded();
      expect(port.statusCalls, 2, reason: 'clear 후 재조회');
      expect(c.showsNotice, isFalse);
    });

    testWidgets('앱 복귀(resumed) → 서버 재조회로 상태를 갱신한다',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(_pending());
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);

      // 앱 밖(웹)에서 탈퇴 취소 → 복귀 시 배너가 사라져야 한다.
      port.status = const DeletionStatusResult(
          exists: false, writeBlocked: false, canCancel: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
    });
  });

  group('공통 상태 소스 — single-flight', () {
    testWidgets('두 표면(홈·마이페이지 상당)이 동시에 떠도 RPC 는 1회',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(_pending());
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              WithdrawalPendingBanner(controllerOverride: c),
              WithdrawalPendingBanner(controllerOverride: c),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNWidgets(2), reason: '공통 상태 소스 공유');
      expect(port.statusCalls, 1, reason: 'single-flight — 중복 RPC 없음');
    });

    testWidgets('이미 로드된 뒤 새 표면 진입은 추가 RPC 를 만들지 않는다',
        (WidgetTester tester) async {
      final _FakePort port = _FakePort(_pending());
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(port.statusCalls, 1);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              WithdrawalPendingBanner(controllerOverride: c),
              WithdrawalPendingBanner(controllerOverride: c),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(port.statusCalls, 1, reason: 'ensureLoaded — 재조회 없음');
    });

    testWidgets('조회 실패 후에도 마지막 정상 스냅샷을 유지한다', (WidgetTester tester) async {
      final _FakePort port = _FakePort(_pending());
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      await tester.pumpWidget(_host(c));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);

      port.status = null; // 다음 조회는 실패
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget, reason: '실패로 배너를 지우지 않는다');
    });

    testWidgets('컨트롤러가 바뀌면 새 컨트롤러 상태를 그린다(이전 상태 잔상 0)',
        (WidgetTester tester) async {
      final DeletionNoticeController first =
          DeletionNoticeController(port: _FakePort(_pending()));
      await tester.pumpWidget(_host(first));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);

      // 같은 위치·같은 타입이라 State 가 재사용된다 — 구독을 옮기지 않으면
      // 이전 컨트롤러 상태가 계속 그려진다.
      final DeletionNoticeController second = DeletionNoticeController(
        port: _FakePort(const DeletionStatusResult(
            exists: false, writeBlocked: false, canCancel: false)),
      );
      await tester.pumpWidget(_host(second));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
    });
  });

  group('§5-1 배선 — 홈 셸·마이페이지 공통 위젯 1개', () {
    testWidgets('홈 셸이 공통 배너를 품는다', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(
          myPageLoaderOverride: () async => const MyPageData(
            role: AppRole.student,
            profile: MyProfile(name: '학생', roleLabel: '학생'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(WithdrawalPendingBanner), findsOneWidget);
      // 서버 확인 전(테스트 환경은 백엔드 없음)에는 아무 것도 그리지 않는다.
      expect(find.text(_title), findsNothing);
    });

    testWidgets('미노출로 시작해도 서버 상태가 늦게 도착하면 배너가 뜬다(스크롤 수거 방지)',
        (WidgetTester tester) async {
      final Completer<DeletionStatusResult> slow =
          Completer<DeletionStatusResult>();
      final _FakePort port = _FakePort(_pending());
      port.statusOverride = slow.future;
      final DeletionNoticeController c = DeletionNoticeController(port: port);
      // 마이페이지처럼 스크롤 뷰와 함께 배치했을 때를 재현한다.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              WithdrawalPendingBanner(controllerOverride: c),
              Expanded(
                child: ListView(
                  children: const <Widget>[Text('마이페이지 본문')],
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
      expect(find.text(_title), findsNothing); // 아직 서버 응답 전 — 미노출

      slow.complete(_pending());
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget, reason: '응답 도착 후 즉시 노출');
    });

    testWidgets('마이페이지가 같은 공통 배너를 품는다', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MyPageScreen(
            loaderOverride: () async => const MyPageData(
              role: AppRole.student,
              profile: MyProfile(name: '학생', roleLabel: '학생'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(WithdrawalPendingBanner), findsOneWidget);
      expect(find.text(_title), findsNothing);
    });
  });
}
