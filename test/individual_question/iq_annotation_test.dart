import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/ink/ink_document.dart';
import 'package:ssambership_app/core/ink/ink_storage_paths.dart';
import 'package:ssambership_app/features/individual_question/data/iq_annotation_repository.dart';

/// S18 개별질문 첨삭 — ink.json 저장(upsert)·복원 분기를 fake 주입으로 검증
/// (DB·스토리지 비접촉).
///
/// ★ §4-3 계약: 평탄화 PNG 의 서버 등록은 이 레포 소관이 아니다 — 첨삭본은
///   대기 첨부로 들어가 멘토 메시지 생성 후 그 message_id 로 등록된다
///   (즉시 미연결 등록 금지 — 화면 흐름은 iq_annotate_flow_test 참조).
class _FakeStore implements IqAnnotationStore {
  final Map<String, Uint8List> objects = <String, Uint8List>{};
  String? lastUpsertPath;
  final List<String> downloadedAttachments = <String>[];

  @override
  Future<void> upsertDocument({
    required String path,
    required Uint8List bytes,
  }) async {
    lastUpsertPath = path;
    objects[path] = bytes;
  }

  @override
  Future<Uint8List?> downloadDocumentOrNull({required String path}) async =>
      objects[path];

  @override
  Future<Uint8List> downloadAttachment({required String storagePath}) async {
    downloadedAttachments.add(storagePath);
    return Uint8List.fromList(<int>[1, 2, 3]);
  }
}

InkDocument _doc() => const InkDocument(
      canvasWidth: 40,
      canvasHeight: 20,
      sketch: <String, dynamic>{
        'lines': <Map<String, dynamic>>[
          <String, dynamic>{
            'points': <Map<String, dynamic>>[
              <String, dynamic>{'x': 0.5, 'y': 0.5},
            ],
            'color': 0xFFFF0000,
            'width': 0.01,
          },
        ],
      },
    );

void main() {
  group('InkStoragePaths.iqAnnotationDocument (경로 규약)', () {
    test('첫 세그먼트=질문 uuid + annotations/ 프리픽스 — 기존 버킷 정책 그대로 통과', () {
      expect(
        InkStoragePaths.iqAnnotationDocument('q-uuid-1', 'att-1'),
        'q-uuid-1/annotations/att-1.json',
      );
    });

    test('구분자 포함 세그먼트는 거부(호출부 버그 방어)', () {
      expect(
        () => InkStoragePaths.iqAnnotationDocument('a/b', 'att'),
        throwsArgumentError,
      );
    });
  });

  group('IqAnnotationRepository', () {
    test('saveDocument: ink.json 이 원본 첨부 id 경로에 저장된다(첨부 행 등록 0)',
        () async {
      final _FakeStore store = _FakeStore();
      final IqAnnotationRepository repo = IqAnnotationRepository(store: store);

      await repo.saveDocument(
        questionId: 'q-1',
        sourceAttachmentId: 'src-att-1',
        document: _doc(),
      );

      // 원본 첨부 id 기준 경로(새 첨부 id 가 아님 — 재편집 키).
      expect(store.lastUpsertPath, 'q-1/annotations/src-att-1.json');
      final InkDocument saved = InkDocument.fromJsonString(
          utf8.decode(store.objects[store.lastUpsertPath]!));
      expect(saved.isEmpty, isFalse);
    });

    test('재첨삭: 같은 원본에 다시 저장하면 같은 경로 upsert(문서 1개 유지)', () async {
      final _FakeStore store = _FakeStore();
      final IqAnnotationRepository repo = IqAnnotationRepository(store: store);

      await repo.saveDocument(
          questionId: 'q-1', sourceAttachmentId: 'src', document: _doc());
      await repo.saveDocument(
          questionId: 'q-1', sourceAttachmentId: 'src', document: _doc());

      expect(store.objects.length, 1); // ink.json 은 같은 경로 upsert.
    });

    test('loadAnnotation: 없으면 null(새로 시작), 있으면 문서 복원(이어 그리기)', () async {
      final _FakeStore store = _FakeStore();
      final IqAnnotationRepository repo = IqAnnotationRepository(store: store);

      expect(
        await repo.loadAnnotation(questionId: 'q-1', sourceAttachmentId: 'a'),
        isNull,
      );

      store.objects['q-1/annotations/a.json'] =
          Uint8List.fromList(utf8.encode(_doc().toJsonString()));
      final InkDocument? restored =
          await repo.loadAnnotation(questionId: 'q-1', sourceAttachmentId: 'a');
      expect(restored, isNotNull);
      expect(restored!.canvasWidth, 40);
    });

    test('loadAnnotation: 깨진 파일은 null — 새로 시작으로 안전 폴백', () async {
      final _FakeStore store = _FakeStore();
      store.objects['q-1/annotations/a.json'] =
          Uint8List.fromList(utf8.encode('{"broken": true}'));
      final IqAnnotationRepository repo = IqAnnotationRepository(store: store);

      expect(
        await repo.loadAnnotation(questionId: 'q-1', sourceAttachmentId: 'a'),
        isNull,
      );
    });

    test('downloadAttachment: 배경 원본 바이트를 그대로 돌려준다(원본 불변)', () async {
      final _FakeStore store = _FakeStore();
      final IqAnnotationRepository repo = IqAnnotationRepository(store: store);

      final Uint8List bytes = await repo.downloadAttachment('q-1/1.png');
      expect(bytes, Uint8List.fromList(<int>[1, 2, 3]));
      expect(store.downloadedAttachments, <String>['q-1/1.png']);
    });
  });
}
