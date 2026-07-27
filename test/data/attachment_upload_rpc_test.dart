import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// P2-19 첨부 보상 파이프라인: 업로드 → RPC 등록 → (실패 시) 미등록 객체 보상 삭제.
/// Supabase 구체 호출은 QnaAttachmentBackend fake 로 대체한다.
class _FakeBackend implements QnaAttachmentBackend {
  _FakeBackend({
    this.registerError,
    this.removeError,
    this.existingRow,
    Object? registerResult,
  }) : registerResult = registerResult ??
            <String, dynamic>{
              'ok': true,
              'attachment_id': 'att-1',
              'answered_transition': false,
            };

  Object? registerError;
  Object? removeError;
  Map<String, dynamic>? existingRow;
  Object? registerResult;

  /// 경로 인자를 반영해 행을 만들 때 사용(멱등 일치 케이스용).
  /// null 이면 [existingRow] 를 그대로 반환 — 인자 무시 백엔드 시뮬레이션.
  Map<String, dynamic>? Function(String path)? findResult;
  String? lastFindPath;

  final List<String> uploadedPaths = <String>[];
  final List<String> uploadedMimes = <String>[];
  final List<String> removedPaths = <String>[];
  int registerCalls = 0;
  String? lastRegisteredPath;
  String? lastRegisteredMessageId;

  @override
  Future<void> uploadObject({
    required String path,
    required List<int> bytes,
    required String mimeType,
  }) async {
    uploadedPaths.add(path);
    uploadedMimes.add(mimeType);
  }

  @override
  Future<Object?> registerAttachment({
    required String threadId,
    required String storagePath,
    required String fileName,
    required String mimeType,
    String? messageId,
  }) async {
    registerCalls += 1;
    lastRegisteredPath = storagePath;
    lastRegisteredMessageId = messageId;
    final Object? err = registerError;
    if (err != null) throw err;
    return registerResult;
  }

  @override
  Future<void> removeObject(String path) async {
    final Object? err = removeError;
    if (err != null) throw err;
    removedPaths.add(path);
  }

  @override
  Future<Map<String, dynamic>?> findRegisteredByPath(String path) async {
    lastFindPath = path;
    final Map<String, dynamic>? Function(String)? builder = findResult;
    return builder != null ? builder(path) : existingRow;
  }
}

PickedImage _png() => PickedImage(
      bytes: Uint8List.fromList(List<int>.filled(16, 7)),
      fileName: 'photo.png',
      mimeType: 'image/png',
    );

void main() {
  group('SupabaseAttachmentUploader (RPC 등록 + 보상)', () {
    test('성공: 업로드 1회 → 등록 RPC 1회, 보상 삭제 없음, 전이 신호 전달', () async {
      final _FakeBackend backend = _FakeBackend(
        registerResult: <String, dynamic>{
          'ok': true,
          'attachment_id': 'att-9',
          'answered_transition': true,
        },
      );
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);

      final AttachmentUploadResult result = await up.upload(
        roomId: 'room-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        image: _png(),
      );

      expect(backend.uploadedPaths.single, startsWith('room-1/thread-1/'));
      expect(backend.registerCalls, 1);
      expect(backend.lastRegisteredPath, backend.uploadedPaths.single);
      expect(backend.lastRegisteredMessageId, 'msg-1');
      expect(backend.removedPaths, isEmpty, reason: '등록 성공 객체는 삭제 금지');
      expect(result.attachment.id, 'att-9');
      expect(result.attachment.storagePath, backend.uploadedPaths.single);
      expect(result.answeredTransition, isTrue);
    });

    test('등록 실패: 방금 올린 미등록 객체만 보상 DELETE, 원래 실패 문구 유지', () async {
      final _FakeBackend backend = _FakeBackend(
        registerError:
            const PostgrestException(message: 'THREAD_LOCKED', code: 'P0001'),
      );
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: _png()),
        throwsA(isA<AttachmentRegistrationFailure>()
            .having((AttachmentRegistrationFailure f) => f.compensated,
                'compensated', isTrue)
            .having((AttachmentRegistrationFailure f) => f.compensationError,
                'compensationError', isNull)
            .having((AttachmentRegistrationFailure f) => f.userMessage,
                'userMessage', contains('종료'))),
      );
      expect(backend.removedPaths.single, backend.uploadedPaths.single);
    });

    test('등록 실패 + 보상 삭제도 실패: 이중 오류를 별도로 보존한다', () async {
      final Object deleteBoom = Exception('storage down');
      final _FakeBackend backend = _FakeBackend(
        registerError: const PostgrestException(
            message: 'STORAGE_OBJECT_NOT_OWNED', code: 'P0001'),
        removeError: deleteBoom,
      );
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: _png()),
        throwsA(isA<AttachmentRegistrationFailure>()
            .having((AttachmentRegistrationFailure f) => f.compensated,
                'compensated', isFalse)
            .having((AttachmentRegistrationFailure f) => f.compensationError,
                'compensationError', same(deleteBoom))
            .having((AttachmentRegistrationFailure f) => f.registrationError,
                'registrationError', isA<PostgrestException>())),
      );
      expect(backend.removedPaths, isEmpty);
    });

    test('23505 + 의미 완전 일치(경로·thread·message·author) → 멱등 성공, 삭제 0', () async {
      final _FakeBackend backend = _FakeBackend(
        registerError:
            const PostgrestException(message: 'duplicate key', code: '23505'),
      )..findResult = (String path) => <String, dynamic>{
            'id': 'att-dup',
            'thread_id': 't',
            'storage_path': path, // 조회 경로와 정확 일치하는 진짜 duplicate
            'message_id': 'msg-1',
            'author_id': 'me',
            'created_at': '2026-07-01T00:00:00Z',
          };
      final SupabaseAttachmentUploader up = SupabaseAttachmentUploader(
          backend: backend, currentUserIdProvider: () => 'me');

      final AttachmentUploadResult result = await up.upload(
          roomId: 'r', threadId: 't', messageId: 'msg-1', image: _png());

      expect(result.attachment.id, 'att-dup');
      expect(backend.lastFindPath, backend.uploadedPaths.single);
      expect(backend.removedPaths, isEmpty, reason: '등록된 객체는 보상 삭제 금지');
      expect(backend.registerCalls, 1);
    });

    test('23505 + storage_path 불일치(백엔드가 조회 인자를 무시) → 충돌 오류, 삭제 0', () async {
      final _FakeBackend backend = _FakeBackend(
        registerError:
            const PostgrestException(message: 'duplicate key', code: '23505'),
        // 인자를 무시하고 엉뚱한 고정 행을 돌려주는 백엔드 — 코드가 걸러내야 한다.
        existingRow: <String, dynamic>{
          'id': 'att-other',
          'thread_id': 't',
          'storage_path': 'r/t/other.png',
          'created_at': '2026-07-01T00:00:00Z',
        },
      );
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: _png()),
        throwsA(isA<AttachmentRegistrationConflict>()),
      );
      expect(backend.removedPaths, isEmpty, reason: '등록 객체일 수 있음 — 보상 삭제 금지');
    });

    test('23505 + thread 불일치 → 충돌 오류(성공 위장 금지), 삭제 0', () async {
      final _FakeBackend backend = _FakeBackend(
        registerError:
            const PostgrestException(message: 'duplicate key', code: '23505'),
      )..findResult = (String path) => <String, dynamic>{
            'id': 'att-x',
            'thread_id': 'other-thread',
            'storage_path': path,
            'created_at': '2026-07-01T00:00:00Z',
          };
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: _png()),
        throwsA(isA<AttachmentRegistrationConflict>()),
      );
      expect(backend.removedPaths, isEmpty);
    });

    test('23505 + author 불일치(타인 등록행) → 충돌 오류, 삭제 0', () async {
      final _FakeBackend backend = _FakeBackend(
        registerError:
            const PostgrestException(message: 'duplicate key', code: '23505'),
      )..findResult = (String path) => <String, dynamic>{
            'id': 'att-x',
            'thread_id': 't',
            'storage_path': path,
            'author_id': 'someone-else',
            'created_at': '2026-07-01T00:00:00Z',
          };
      final SupabaseAttachmentUploader up = SupabaseAttachmentUploader(
          backend: backend, currentUserIdProvider: () => 'me');

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: _png()),
        throwsA(isA<AttachmentRegistrationConflict>()),
      );
      expect(backend.removedPaths, isEmpty);
    });

    test('23505 + message_id 불일치 → 충돌 오류, 삭제 0', () async {
      final _FakeBackend backend = _FakeBackend(
        registerError:
            const PostgrestException(message: 'duplicate key', code: '23505'),
      )..findResult = (String path) => <String, dynamic>{
            'id': 'att-x',
            'thread_id': 't',
            'storage_path': path,
            'message_id': 'msg-9',
            'created_at': '2026-07-01T00:00:00Z',
          };
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: _png()),
        throwsA(isA<AttachmentRegistrationConflict>()),
      );
      expect(backend.removedPaths, isEmpty);
    });

    test('23505 인데 조회 행 없음 → 기존 실패 흐름(미등록 객체 보상 삭제)', () async {
      final _FakeBackend backend = _FakeBackend(
        registerError:
            const PostgrestException(message: 'duplicate key', code: '23505'),
      );
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: _png()),
        throwsA(isA<AttachmentRegistrationFailure>()),
      );
      expect(backend.removedPaths.single, backend.uploadedPaths.single);
    });

    test('예상 밖 RPC 반환형: 실패로 취급하고 보상 삭제 수행', () async {
      final _FakeBackend backend = _FakeBackend(registerResult: 'not-a-map');
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: _png()),
        throwsA(isA<AttachmentRegistrationFailure>()),
      );
      expect(backend.removedPaths.single, backend.uploadedPaths.single);
    });

    test('검증 실패(5MB 초과)면 업로드 자체를 시작하지 않는다', () async {
      final _FakeBackend backend = _FakeBackend();
      final SupabaseAttachmentUploader up =
          SupabaseAttachmentUploader(backend: backend);
      final PickedImage tooBig = PickedImage(
        bytes: Uint8List(kMaxAttachmentBytes + 1),
        fileName: 'big.png',
        mimeType: 'image/png',
      );

      await expectLater(
        up.upload(roomId: 'r', threadId: 't', image: tooBig),
        throwsA(isA<AppError>()),
      );
      expect(backend.uploadedPaths, isEmpty);
      expect(backend.registerCalls, 0);
    });
  });
}
