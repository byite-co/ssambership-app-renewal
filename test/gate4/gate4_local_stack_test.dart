import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_post_actions.dart';
import 'package:ssambership_app/features/community/data/community_post_images.dart';
import 'package:ssambership_app/features/community/data/community_post_envelope.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/data/community_write_repository.dart';
import 'package:ssambership_app/features/mentors/data/free_question_entry.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 앱 Gate 4 — 격리 로컬 스택(§11 D-API-A 로컬 게이트) 통합 검증.
///
/// 실행 조건: `GATE4_STACK_URL`(+`GATE4_ANON_KEY`) 환경변수가 설정된 경우에만
/// 실행된다(미설정 시 전건 skip — CI/일반 `flutter test` 는 DB 미접촉 유지).
/// 스택 요건: 웹 clean-install 187/187 + gotrue·PostgREST(api_app_v1·api_web_v1
/// 노출, core_private 미노출)·Storage + Gate4 fixture 계정 6명.
///
/// ★ 이 테스트는 실제 앱 리포지토리 클래스(앱 호출 경로)로 스택을 호출한다 —
///   community_posts 직접 INSERT/UPDATE/DELETE 는 앱 코드에 존재하지 않으며,
///   '기존 학생 글'·spoof payload 시드는 구버전 클라이언트 모사(하네스)다.

final String? _stackUrl = Platform.environment['GATE4_STACK_URL'];
final String? _anonKey = Platform.environment['GATE4_ANON_KEY'];
final bool _enabled = _stackUrl != null && _anonKey != null;

const String _password = 'Passw0rd!234';
const String _mentorApprovedEmail = 'mentor.approved@gate4.local';
const String _mentorPendingEmail = 'mentor.pending@gate4.local';
const String _student1Email = 'student1@gate4.local';
const String _student3Email = 'student3@gate4.local';
const String _admin1Email = 'admin1@gate4.local';

Future<SupabaseClient> _signIn(String email) async {
  final SupabaseClient c = SupabaseClient(_stackUrl!, _anonKey!);
  await c.auth.signInWithPassword(email: email, password: _password);
  return c;
}

Uint8List _pngBytes(int seed) {
  // 유효 PNG magic + 패딩(서버 MIME 판정은 storage metadata 기준).
  final Uint8List b = Uint8List(64);
  b.setRange(0, 8, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  b[8] = seed;
  return b;
}

ValidatedPostImage _image(int seed) => validateCommunityPostImage(
    bytes: _pngBytes(seed), fileName: 'gate4-$seed.png');

/// Storage 호출을 기록하는 프록시 — 재호출 전 DELETE 0회(T-CONC-10)를 실측.
class _RecordingBackend implements CommunityPostImageBackend {
  _RecordingBackend(this.inner);

  final CommunityPostImageBackend inner;
  final List<List<String>> removeCalls = <List<String>>[];

  @override
  Future<String> createSignedUrl(String objectPath, int ttlSeconds) =>
      inner.createSignedUrl(objectPath, ttlSeconds);

  @override
  Future<void> removeObjects(List<String> objectPaths) {
    removeCalls.add(List<String>.of(objectPaths));
    return inner.removeObjects(objectPaths);
  }

  @override
  Future<void> uploadObject({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
  }) =>
      inner.uploadObject(
          objectPath: objectPath, bytes: bytes, contentType: contentType);
}

void main() {
  if (!_enabled) {
    test('Gate 4 로컬 스택 검증(전건 skip — GATE4_STACK_URL 미설정)', () {},
        skip: 'GATE4_STACK_URL/GATE4_ANON_KEY 미설정 — 격리 로컬 스택 전용 검증');
    return;
  }

  late SupabaseClient mentor; // 승인 멘토
  late SupabaseClient mentorPending; // 미승인 멘토
  late SupabaseClient student1; // 학생(기존 글 소유자 시나리오)
  late SupabaseClient student3; // 방 없는 학생(F2)
  late SupabaseClient admin1; // 일반 관리자

  late String mentorUid;
  late String student1Uid;

  final List<String> cleanupPostIds = <String>[];
  final List<String> cleanupObjectPaths = <String>[];

  setUpAll(() async {
    mentor = await _signIn(_mentorApprovedEmail);
    mentorPending = await _signIn(_mentorPendingEmail);
    student1 = await _signIn(_student1Email);
    student3 = await _signIn(_student3Email);
    admin1 = await _signIn(_admin1Email);
    mentorUid = mentor.auth.currentUser!.id;
    student1Uid = student1.auth.currentUser!.id;
  });

  tearDownAll(() async {
    // fixture 잔여 0 규약 — 이 세션이 만든 게시글은 soft-delete, 객체는 제거.
    final CommunityWriteRepository w = CommunityWriteRepository(client: mentor);
    for (final String id in cleanupPostIds) {
      try {
        await w.softDeletePost(id);
      } catch (_) {}
    }
    if (cleanupObjectPaths.isNotEmpty) {
      try {
        await mentor.storage
            .from(kCommunityPostImageBucket)
            .remove(cleanupObjectPaths);
      } catch (_) {}
    }
    await mentor.dispose();
    await mentorPending.dispose();
    await student1.dispose();
    await student3.dispose();
    await admin1.dispose();
  });

  group('질문방 (F2·F3)', () {
    test('방 없는 학생 F2 성공 → 동일 pair 재호출 created:false·방 1개', () async {
      final SupabaseFreeQuestionEntryRepository repo =
          SupabaseFreeQuestionEntryRepository(client: student3);
      final EnsuredQuestionRoom first = await repo.ensureRoom(mentorUid);
      expect(first.roomId, isNotEmpty);
      expect(first.entitlement, anyOf('free', 'subscription'));

      final EnsuredQuestionRoom again = await repo.ensureRoom(mentorUid);
      expect(again.roomId, first.roomId);
      expect(again.created, isFalse); // 기존 방 재사용.

      // 방은 정확히 1개(RLS 로 본인 방만 보임 — pair 필터).
      final List<dynamic> rooms = await student3
          .from('mentor_student_rooms')
          .select('id')
          .eq('mentor_id', mentorUid);
      expect(rooms, hasLength(1));
    });

    test('동일 pair 동시 F2 5회 → 방 1개(원자 확보 — T-CONC-01 상당)', () async {
      final SupabaseFreeQuestionEntryRepository repo =
          SupabaseFreeQuestionEntryRepository(client: student1);
      final List<EnsuredQuestionRoom> results = await Future.wait(
          List<Future<EnsuredQuestionRoom>>.generate(
              5, (_) => repo.ensureRoom(mentorUid)));
      final Set<String> ids =
          results.map((EnsuredQuestionRoom r) => r.roomId).toSet();
      expect(ids, hasLength(1));
      final List<dynamic> rooms = await student1
          .from('mentor_student_rooms')
          .select('id')
          .eq('mentor_id', mentorUid);
      expect(rooms, hasLength(1));
    });

    test('F3 스레드 생성(앱 wrapper — envelope) + 무료 경로 표시', () async {
      final SupabaseFreeQuestionEntryRepository entry =
          SupabaseFreeQuestionEntryRepository(client: student1);
      final EnsuredQuestionRoom room = await entry.ensureRoom(mentorUid);
      final CreatedFreeQuestion created = await entry.createFreeThread(
        roomId: room.roomId,
        title: 'Gate4 무료 질문',
        firstMessageBody: '무료 질문 본문입니다.',
      );
      expect(created.threadId, isNotEmpty);
      expect(created.path, anyOf('free', 'subscription'));
    });

    test('F3 오류코드: 존재하지 않는 방 → 한글 안내(ROOM_NOT_FOUND 매핑)', () async {
      final QuestionRoomWriteRepository w =
          QuestionRoomWriteRepository(client: student1);
      await expectLater(
        w.createThread(
            roomId: '00000000-0000-0000-0000-000000000000',
            title: 't',
            firstMessageBody: 'b'),
        throwsA(isA<AppError>()),
      );
    });

    test('F2 는 학생 전용 — 멘토 세션 거부(ROLE_NOT_STUDENT 매핑)', () async {
      final SupabaseFreeQuestionEntryRepository repo =
          SupabaseFreeQuestionEntryRepository(client: mentor);
      await expectLater(repo.ensureRoom(student1Uid),
          throwsA(isA<AppError>()));
    });
  });

  group('게시글 (F4·F5·F6) — 앱 호출 경로', () {
    test('승인 멘토 0장 작성 성공(F4)', () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: mentor);
      final CreatedBoardPostV1 res = await w.createPost(
        title: 'Gate4 텍스트 글',
        body: '본문은 열 자 이상입니다. Gate4.',
        category: 'free',
        idempotencyKey: generateUuidV4(),
      );
      cleanupPostIds.add(res.postId);
      expect(res.idempotentReplay, isFalse);
    });

    test('승인 멘토 1장·5장 작성 → View image_refs·signed URL 표시(§5)', () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: mentor);
      for (final int count in <int>[1, 5]) {
        final CreatedBoardPostV1 res = await w.createPost(
          title: 'Gate4 이미지 $count장',
          body: '이미지 글 본문입니다($count장).',
          category: 'study',
          idempotencyKey: generateUuidV4(),
          images: List<ValidatedPostImage>.generate(
              count, (int i) => _image(count * 10 + i)),
        );
        cleanupPostIds.add(res.postId);

        // 앱 읽기 경로(M17 View)로 재조회 — image_refs 계약 필드 확인.
        final CommunityReadRepository read =
            CommunityReadRepository(client: mentor);
        final MyActivity mine = await read.myActivity();
        final BoardPost post =
            mine.myPosts.firstWhere((BoardPost p) => p.id == res.postId);
        expect(post.imageRefs, hasLength(count));
        for (final String ref in post.imageRefs) {
          expect(ref, startsWith('community-post-images/$mentorUid/'));
          final String? path = parseCommunityPostImageRef(ref);
          cleanupObjectPaths.add(path!);
          // 표시 시점 signed URL(TTL 3600) 발급 가능 = 객체 실존.
          final String url = await mentor.storage
              .from(kCommunityPostImageBucket)
              .createSignedUrl(path, kCommunityPostImageSignedUrlTtlSeconds);
          expect(url, contains('token='));
        }
      }
    });

    test('학생 작성 거부(ROLE_NOT_MENTOR) — §6.5', () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: student1);
      await expectLater(
        w.createPost(
            title: '학생 글',
            body: '학생은 더 이상 쓸 수 없어요.',
            category: 'free',
            idempotencyKey: generateUuidV4()),
        throwsA(isA<CommunityWriteRejected>().having(
            (CommunityWriteRejected e) => e.code, 'code', 'ROLE_NOT_MENTOR')),
      );
    });

    test('미승인 멘토 작성 거부(MENTOR_NOT_APPROVED) — §6.5', () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: mentorPending);
      await expectLater(
        w.createPost(
            title: '미승인 글',
            body: '미승인 멘토는 쓸 수 없어요.',
            category: 'free',
            idempotencyKey: generateUuidV4()),
        throwsA(isA<CommunityWriteRejected>().having(
            (CommunityWriteRejected e) => e.code, 'code',
            'MENTOR_NOT_APPROVED')),
      );
    });

    test('일반 관리자 작성 거부 — §6.5(관리자 공지 경로는 별도)', () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: admin1);
      await expectLater(
        w.createPost(
            title: '관리자 글',
            body: '관리자도 일반 작성은 불가.',
            category: 'free',
            idempotencyKey: generateUuidV4()),
        throwsA(isA<CommunityWriteRejected>().having(
            (CommunityWriteRejected e) => e.code, 'code', 'ROLE_NOT_MENTOR')),
      );
    });

    test('타인 ref 공격 거부(IMAGE_NOT_OWNED) + 확정 실패 시 보상 삭제 0(기존 객체)',
        () async {
      // 학생 소유 객체를 멘토 글에 참조 — B-4 공용 검증기가 거부해야 한다.
      final String foreignPath = '$student1Uid/${generateUuidV4()}-x.png';
      await student1.storage.from(kCommunityPostImageBucket).uploadBinary(
          foreignPath, _pngBytes(99),
          fileOptions: const FileOptions(
              contentType: 'image/png', upsert: false));
      cleanupObjectPaths.add(foreignPath);

      final Object? data =
          await mentor.schema('api_app_v1').rpc<dynamic>(
        'community_post_create',
        params: <String, dynamic>{
          'p_title': '타인 ref',
          'p_body': '타인 객체 참조 공격입니다.',
          'p_category': 'free',
          'p_idempotency_key': generateUuidV4(),
          'p_image_refs': <String>['$kCommunityPostImageBucket/$foreignPath'],
        },
      );
      final CommunityWriteEnvelope? env = CommunityWriteEnvelope.tryParse(data);
      expect(env!.ok, isFalse);
      expect(env.code, 'IMAGE_NOT_OWNED');
      // 타인(기존) 객체는 보상 삭제 대상이 아니다 — 실존 유지.
      final String url = await student1.storage
          .from(kCommunityPostImageBucket)
          .createSignedUrl(foreignPath, 60);
      expect(url, contains('token='));
    });

    test('존재하지 않는 ref 거부(IMAGE_OBJECT_NOT_FOUND)', () async {
      final Object? data = await mentor.schema('api_app_v1').rpc<dynamic>(
        'community_post_create',
        params: <String, dynamic>{
          'p_title': '유령 ref',
          'p_body': '존재하지 않는 객체 참조.',
          'p_category': 'free',
          'p_idempotency_key': generateUuidV4(),
          'p_image_refs': <String>[
            '$kCommunityPostImageBucket/$mentorUid/ghost.png'
          ],
        },
      );
      final CommunityWriteEnvelope? env = CommunityWriteEnvelope.tryParse(data);
      expect(env!.ok, isFalse);
      expect(env.code, 'IMAGE_OBJECT_NOT_FOUND');
    });

    test('Storage 2차 방어: 허용 외 MIME·5MiB 초과 업로드는 bucket 이 거부(§6.1)',
        () async {
      final SupabaseCommunityPostImageBackend backend =
          SupabaseCommunityPostImageBackend(mentor);
      await expectLater(
        backend.uploadObject(
            objectPath: '$mentorUid/${generateUuidV4()}-evil.pdf',
            bytes: _pngBytes(1),
            contentType: 'application/pdf'),
        throwsA(anything),
      );
      final Uint8List oversized = Uint8List(kCommunityPostImageMaxBytes + 1);
      oversized.setRange(0, 8, _pngBytes(1));
      await expectLater(
        backend.uploadObject(
            objectPath: '$mentorUid/${generateUuidV4()}-big.png',
            bytes: oversized,
            contentType: 'image/png'),
        throwsA(anything),
      );
    });

    test('F5 정상 수정 → updated_at 전진·수정 반영, 이후 stale 키로 UPDATE_CONFLICT',
        () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: mentor);
      final CreatedBoardPostV1 created = await w.createPost(
        title: '수정 전 제목',
        body: '수정 전 본문입니다.',
        category: 'career',
        idempotencyKey: generateUuidV4(),
      );
      cleanupPostIds.add(created.postId);

      final CommunityReadRepository read =
          CommunityReadRepository(client: mentor);
      BoardPost post = (await read.myActivity())
          .myPosts
          .firstWhere((BoardPost p) => p.id == created.postId);
      // 실제 조회값(생성 직후 NULL 가능) — NULL 도 그대로 전달이 계약(§7.3).
      final String? staleUpdatedAt = post.updatedAtRaw;

      final UpdatedBoardPostV1 updated = await w.updatePost(
        postId: created.postId,
        title: '수정 후 제목',
        body: '수정 후 본문입니다.',
        category: 'career',
        expectedUpdatedAt: staleUpdatedAt,
        imageRefs: post.imageRefs,
      );
      expect(updated.postId, created.postId);

      // stale expected_updated_at 로 재수정 → UPDATE_CONFLICT(자동 덮어쓰기 금지).
      await expectLater(
        w.updatePost(
          postId: created.postId,
          title: '충돌 시도',
          body: '충돌 시도 본문입니다.',
          category: 'career',
          expectedUpdatedAt: staleUpdatedAt,
          imageRefs: post.imageRefs,
        ),
        throwsA(isA<CommunityWriteRejected>().having(
            (CommunityWriteRejected e) => e.code, 'code', 'UPDATE_CONFLICT')),
      );

      // 수정 반영 확인(앱 읽기 경로).
      post = (await read.myActivity())
          .myPosts
          .firstWhere((BoardPost p) => p.id == created.postId);
      expect(post.title, '수정 후 제목');
    });

    test('F6 soft-delete → View 에서 제외 + 재호출 already_deleted:true', () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: mentor);
      final CreatedBoardPostV1 created = await w.createPost(
        title: '삭제될 글',
        body: '삭제될 본문입니다.',
        category: 'free',
        idempotencyKey: generateUuidV4(),
      );

      final SoftDeletedBoardPostV1 first =
          await w.softDeletePost(created.postId);
      expect(first.alreadyDeleted, isFalse);

      final SoftDeletedBoardPostV1 again =
          await w.softDeletePost(created.postId);
      expect(again.alreadyDeleted, isTrue); // 정상 성공(§7.4).

      final CommunityReadRepository read =
          CommunityReadRepository(client: mentor);
      final MyActivity mine = await read.myActivity();
      expect(mine.myPosts.where((BoardPost p) => p.id == created.postId),
          isEmpty); // deleted_at IS NULL 필터(View).
    });

    test('기존 학생 글: F5 수정 거부·본인 F6 soft-delete 허용(§6.5)', () async {
      // 구버전 클라이언트 모사(하네스 시드) — 학생 직접 INSERT(M16 이전 표면).
      final Map<String, dynamic> legacy = await student1
          .from('community_posts')
          .insert(<String, dynamic>{
            'title': '기존 학생 글',
            'content': '학생이 과거에 쓴 글입니다.',
            'body': '학생이 과거에 쓴 글입니다.',
            'category': 'free',
            'author_id': student1Uid,
            'author_role': 'student',
            'status': 'published',
          })
          .select()
          .single();
      final String legacyId = legacy['id'] as String;

      final CommunityWriteRepository sw =
          CommunityWriteRepository(client: student1);
      await expectLater(
        sw.updatePost(
          postId: legacyId,
          title: '학생 수정 시도',
          body: '학생 수정 시도 본문입니다.',
          category: 'free',
          expectedUpdatedAt:
              (legacy['updated_at'] ?? legacy['created_at']) as String,
          imageRefs: const <String>[],
        ),
        throwsA(isA<CommunityWriteRejected>().having(
            (CommunityWriteRejected e) => e.code, 'code', 'ROLE_NOT_MENTOR')),
      );

      final SoftDeletedBoardPostV1 deleted = await sw.softDeletePost(legacyId);
      expect(deleted.postId, legacyId); // 본인 F6 허용 — hard delete 아님.
    });

    test('웹 이미지 글이 앱 목록·상세(View)에 동일 형상으로 표시(§5 동등성)', () async {
      // 웹 F4(api_web_v1 동명 wrapper — 같은 B-1 구현부)로 작성.
      final String path = '$mentorUid/${generateUuidV4()}-web.png';
      await mentor.storage.from(kCommunityPostImageBucket).uploadBinary(
          path, _pngBytes(7),
          fileOptions:
              const FileOptions(contentType: 'image/png', upsert: false));
      cleanupObjectPaths.add(path);
      final Object? data = await mentor.schema('api_web_v1').rpc<dynamic>(
        'community_post_create',
        params: <String, dynamic>{
          'p_title': '웹에서 쓴 이미지 글',
          'p_body': '웹 작성 글 본문입니다.',
          'p_category': 'school',
          'p_idempotency_key': generateUuidV4(),
          'p_image_refs': <String>['$kCommunityPostImageBucket/$path'],
        },
      );
      final CommunityWriteEnvelope env =
          CommunityWriteEnvelope.tryParse(data)!;
      expect(env.ok, isTrue);
      final String webPostId = env.fields['post_id'] as String;
      cleanupPostIds.add(webPostId);

      // 앱 목록 경로(boards)·학생 세션에서도 동일 형상으로 보인다.
      final CommunityReadRepository read =
          CommunityReadRepository(client: student1);
      final BoardPost shown = (await read.boards())
          .items
          .firstWhere((BoardPost p) => p.id == webPostId);
      expect(shown.title, '웹에서 쓴 이미지 글');
      expect(shown.imageRefs, <String>['$kCommunityPostImageBucket/$path']);
      // 학생 세션에서도 signed URL 발급(읽기 동등).
      final String url = await student1.storage
          .from(kCommunityPostImageBucket)
          .createSignedUrl(path, kCommunityPostImageSignedUrlTtlSeconds);
      expect(url, contains('token='));
    });
  });

  group('T-CONC-10 — F4 응답 유실 replay-first(앱 표면 재검증)', () {
    test('업로드 → commit 후 응답 유실 모사 → 재호출 전 DELETE 0회 → 동일 키 재호출',
        () async {
      final _RecordingBackend storage =
          _RecordingBackend(SupabaseCommunityPostImageBackend(mentor));
      final String key = generateUuidV4();
      int calls = 0;
      String? firstPostId;

      final CreatedBoardPostV1 res = await createBoardPostV1(
        uid: mentorUid,
        title: 'T-CONC-10 재검증',
        body: '응답 유실 복구 시나리오 본문입니다.',
        category: 'study',
        idempotencyKey: key,
        images: <ValidatedPostImage>[_image(210)],
        storage: storage,
        callCreate: (Map<String, dynamic> params) async {
          calls++;
          expect(params['p_idempotency_key'], key); // 항상 같은 멱등키.
          final Object? data = await mentor
              .schema('api_app_v1')
              .rpc<dynamic>('community_post_create', params: params);
          if (calls == 1) {
            // 서버 커밋은 완료 — 앱이 응답을 받지 못한 상황을 모사.
            firstPostId =
                (data as Map<dynamic, dynamic>)['post_id'] as String?;
            throw Exception('simulated response loss');
          }
          return data;
        },
      );

      expect(calls, 2); // 같은 키로 정확히 1회 재호출.
      expect(storage.removeCalls, isEmpty); // 재호출 전·후 Storage DELETE 0회.
      expect(res.idempotentReplay, isTrue); // 멱등 재생 = 정상 성공.
      expect(res.postId, firstPostId); // 동일 post_id.
      cleanupPostIds.add(res.postId);

      // 게시글 정확히 1건 + image_refs 불변 + 참조 객체 전부 실존.
      final CommunityReadRepository read =
          CommunityReadRepository(client: mentor);
      final List<BoardPost> matches = (await read.myActivity())
          .myPosts
          .where((BoardPost p) => p.id == res.postId)
          .toList();
      expect(matches, hasLength(1));
      expect(matches.single.imageRefs, hasLength(1));
      final String path =
          parseCommunityPostImageRef(matches.single.imageRefs.single)!;
      cleanupObjectPaths.add(path);
      final String url = await mentor.storage
          .from(kCommunityPostImageBucket)
          .createSignedUrl(path, 60);
      expect(url, contains('token=')); // 서명 URL 발급 가능 = 객체 존재.
    });
  });

  group('M13 대표 재검증 — board 댓글 서버 라벨(앱 호출 경로, §3.5)', () {
    late String boardPostId;

    setUpAll(() async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: mentor);
      final CreatedBoardPostV1 res = await w.createPost(
        title: 'M13 댓글 검증 글',
        body: 'M13 대표 시나리오용 글입니다.',
        category: 'free',
        idempotencyKey: generateUuidV4(),
      );
      boardPostId = res.postId;
      cleanupPostIds.add(boardPostId);
    });

    test('① 앱 board 댓글은 라벨을 권위값으로 보내지 않고 서버가 도출한다', () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: student1);
      final CommunityComment c = await w.addComment(
        postType: CommunityPostType.board,
        postId: boardPostId,
        body: '앱 경로 댓글입니다.',
      );
      // 서버 트리거가 users.nickname 으로 라벨 도출(학생하나 — fixture).
      final Map<String, dynamic> row = await student1
          .from('comments')
          .select('author_label, author_role')
          .eq('id', c.id)
          .single();
      expect(row['author_label'], '학생하나');
      expect(row['author_role'], 'student');
    });

    test('② spoof 값이 남은 구 payload 도 서버 트리거가 덮어쓴다', () async {
      // 구버전 클라이언트 모사 — 라벨을 payload 에 포함(하네스).
      final Map<String, dynamic> row = await student1
          .from('comments')
          .insert(<String, dynamic>{
            'post_id': boardPostId,
            'author_id': student1Uid,
            'content': 'spoof payload 댓글',
            'author_label': '해커라벨',
            'author_role': 'mentor',
          })
          .select('id, author_label, author_role')
          .single();
      expect(row['author_label'], '학생하나'); // 서버 기준 덮어쓰기.
      expect(row['author_role'], 'student');
    });

    test('③ canonical/legacy board 표시 라벨 동일(163/164 브리지)', () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: student1);
      final CommunityComment c = await w.addComment(
        postType: CommunityPostType.board,
        postId: boardPostId,
        body: '브리지 라벨 검증 댓글입니다.',
      );
      final Map<String, dynamic> canonical = await student1
          .from('comments')
          .select('author_label, legacy_comment_id')
          .eq('id', c.id)
          .single();
      final Object? legacyId = canonical['legacy_comment_id'];
      if (legacyId is String) {
        final Map<String, dynamic> legacy = await student1
            .from('community_comments')
            .select('author_label')
            .eq('id', legacyId)
            .single();
        expect(legacy['author_label'], canonical['author_label']);
      } else {
        // 브리지 미러 행이 비동기 부재인 스키마 구성이면 canonical 라벨만 검증.
        expect(canonical['author_label'], '학생하나');
      }
    });

    test('④ shortform 댓글 무변경(M13 트리거 미발화)', () async {
      // 숏폼 글 시드(하네스 — 멘토 직접 INSERT, 기존 표면 유지).
      final Map<String, dynamic> sf = await mentor
          .from('shortform_posts')
          .insert(<String, dynamic>{
            'title': 'M13 숏폼',
            'author_id': mentorUid,
            'status': 'published',
          })
          .select('id')
          .single();
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: student1);
      final CommunityComment c = await w.addComment(
        postType: CommunityPostType.shortform,
        postId: sf['id'] as String,
        body: '숏폼 댓글입니다.',
      );
      final Map<String, dynamic> row = await student1
          .from('community_comments')
          .select('author_label')
          .eq('id', c.id)
          .single();
      // 트리거 WHEN(post_type='board') 미발화 — 컬럼 default 유지(닉네임 아님).
      expect(row['author_label'], isNot('학생하나'));
    });

    test('⑤⑥ author_label/author_role spoof UPDATE 명시 실패(성공 no-op 위장 금지)',
        () async {
      final CommunityWriteRepository w =
          CommunityWriteRepository(client: student1);
      final CommunityComment c = await w.addComment(
        postType: CommunityPostType.board,
        postId: boardPostId,
        body: 'spoof UPDATE 대상 댓글입니다.',
      );
      Object? error;
      try {
        await student1
            .from('comments')
            .update(<String, dynamic>{'author_label': '위조라벨'}).eq('id', c.id);
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull, reason: 'spoof UPDATE 는 명시적으로 실패해야 한다');
      expect(error.toString(), contains('COMMENT_PROTECTED_FIELDS_IMMUTABLE'));
      // 라벨 불변 확인(성공 no-op 위장 없음 — 값도 그대로).
      final Map<String, dynamic> after = await student1
          .from('comments')
          .select('author_label')
          .eq('id', c.id)
          .single();
      expect(after['author_label'], '학생하나');
    });
  });
}
