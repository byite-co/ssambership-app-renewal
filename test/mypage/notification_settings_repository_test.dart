import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mypage/data/notification_settings_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 알림 설정 레포 — 정본 notification_settings 대상.
/// 핵심 계약: 행 없음 = 전부 ON, 로드 실패는 기본값으로 위장하지 않고 실패로 전파,
/// 저장 성공/실패도 정직하게 전파(성공 위장 금지).

/// 백엔드 페이크 — 행/오류를 시나리오별로 주입.
class FakeBackend implements NotificationSettingsBackend {
  FakeBackend({
    this.uid = 'user-1',
    this.row,
    this.fetchError,
    this.upsertError,
  });

  String? uid;
  Map<String, dynamic>? row;
  Object? fetchError;
  Object? upsertError;

  int fetchCalls = 0;
  final List<Map<String, dynamic>> upserted = <Map<String, dynamic>>[];

  @override
  String? get currentUserId => uid;

  @override
  Future<Map<String, dynamic>?> fetchRow(String userId) async {
    fetchCalls++;
    if (fetchError != null) throw fetchError!;
    return row;
  }

  @override
  Future<void> upsertRow(Map<String, dynamic> row) async {
    if (upsertError != null) throw upsertError!;
    upserted.add(row);
  }
}

void main() {
  group('load()', () {
    test('행 없음 → 기본값(마스터 ON·그룹 키 없음=전부 ON)', () async {
      final FakeBackend backend = FakeBackend(row: null);
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      final NotificationSettings s = await repo.load();

      expect(s.pushEnabled, isTrue);
      expect(s.groups, isEmpty);
      // 키 부재 = ON (서버 coalesce(true) 의미론).
      for (final String key in NotificationGroups.keys) {
        expect(s.groupEnabled(key), isTrue, reason: '$key 는 키 없음=ON');
      }
    });

    test('저장된 행을 그대로 파싱(push_enabled=false·qna만 off)', () async {
      final FakeBackend backend = FakeBackend(row: <String, dynamic>{
        'push_enabled': false,
        'groups': <String, dynamic>{'qna': false},
      });
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      final NotificationSettings s = await repo.load();

      expect(s.pushEnabled, isFalse);
      expect(s.groupEnabled('qna'), isFalse);
      expect(s.groupEnabled('order'), isTrue); // 키 없음 = ON 유지.
    });

    test('알 수 없는 그룹 키·비 bool 값은 버린다(정본 5키만)', () async {
      final FakeBackend backend = FakeBackend(row: <String, dynamic>{
        'push_enabled': true,
        'groups': <String, dynamic>{
          'qna': false,
          'hacked_group': false, // 정본 아님 → 버림.
          'order': 'no', // bool 아님 → 버림(키 없음=ON 취급).
        },
      });
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      final NotificationSettings s = await repo.load();

      expect(s.groups, <String, bool>{'qna': false});
      expect(s.groupEnabled('order'), isTrue);
    });

    test('조회 오류는 기본값으로 위장하지 않고 AppError 로 전파된다', () async {
      final FakeBackend backend =
          FakeBackend(fetchError: Exception('network down'));
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      await expectLater(repo.load(), throwsA(isA<AppError>()));
    });

    test('비로그인(uid 없음)이면 AppError — 기본값 반환 금지', () async {
      final FakeBackend backend = FakeBackend(uid: null);
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      await expectLater(repo.load(), throwsA(isA<AppError>()));
      expect(backend.fetchCalls, 0); // 쿼리 자체를 시도하지 않는다.
    });
  });

  group('save()', () {
    test('성공 시 본인 uid 로 push_enabled·groups 를 upsert 한다', () async {
      final FakeBackend backend = FakeBackend(uid: 'user-7');
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      await repo.save(const NotificationSettings(
        pushEnabled: false,
        groups: <String, bool>{'refund': false, 'qna': true},
      ));

      expect(backend.upserted, hasLength(1));
      final Map<String, dynamic> row = backend.upserted.single;
      expect(row['user_id'], 'user-7');
      expect(row['push_enabled'], false);
      expect(row['groups'], <String, bool>{'refund': false, 'qna': true});
    });

    test('정본 5키가 아닌 그룹 키는 저장에서 제외된다', () async {
      final FakeBackend backend = FakeBackend();
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      await repo.save(const NotificationSettings(
        groups: <String, bool>{'qna': false, 'weird': true},
      ));

      expect(backend.upserted.single['groups'], <String, bool>{'qna': false});
    });

    test('upsert 실패는 성공으로 위장하지 않고 AppError 로 전파된다', () async {
      final FakeBackend backend =
          FakeBackend(upsertError: Exception('rls denied'));
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      await expectLater(
        repo.save(const NotificationSettings()),
        throwsA(isA<AppError>()),
      );
    });

    test('비로그인 상태의 save 는 AppError', () async {
      final FakeBackend backend = FakeBackend(uid: null);
      final NotificationSettingsRepository repo =
          NotificationSettingsRepository(backend: backend);

      await expectLater(
        repo.save(const NotificationSettings()),
        throwsA(isA<AppError>()),
      );
      expect(backend.upserted, isEmpty);
    });
  });

  group('NotificationGroups', () {
    test('정본 5키와 한글 라벨이 모두 존재한다', () {
      expect(NotificationGroups.keys,
          <String>['qna', 'order', 'subscription', 'refund', 'system']);
      for (final String key in NotificationGroups.keys) {
        expect(NotificationGroups.labels.containsKey(key), isTrue);
        expect(NotificationGroups.labelOf(key), isNotEmpty);
      }
    });
  });
}
