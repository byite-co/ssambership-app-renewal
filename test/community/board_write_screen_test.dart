import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/scan/picked_image.dart';
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/ui/board/board_write_screen.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_upload.dart'
    show ImagePickerPort;

import 'fakes.dart';

/// 게시판 글쓰기·수정 스모크 — DB·Storage 미접촉(FakeCommunityWrite 주입).

const String _uid = 'auth-uid-0001';
const String _updatedAtRaw = '2026-08-01T11:22:33.123456+00:00';

PickedImage _img(String name) => PickedImage(
      bytes: Uint8List(16),
      fileName: name,
      mimeType: 'image/png',
    );

/// 큐에 담긴 이미지를 차례로 돌려주는 가짜 픽커(빈 큐 = 선택 취소).
class FakeImagePicker implements ImagePickerPort {
  FakeImagePicker([List<PickedImage>? queue])
      : queue = List<PickedImage>.of(queue ?? const <PickedImage>[]);

  final List<PickedImage> queue;
  int calls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<PickedImage?> pickImage() async {
    calls++;
    return queue.isEmpty ? null : queue.removeAt(0);
  }
}

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 화면을 base route 위에 push 해서 연다 — 성공 pop(true) 이후에도 navigator
/// history 가 비지 않아, 한 테스트 안에서 재-pump 해도 안전하다.
Future<void> _pumpPushed(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(ctx).push<bool>(
              MaterialPageRoute<bool>(builder: (_) => screen),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

BoardPost _editable({
  List<String> imageRefs = const <String>[],
  String authorRole = 'student',
  String? updatedAtRaw = _updatedAtRaw,
}) =>
    sampleBoard(
      id: 'post-1',
      authorRole: authorRole,
      authorId: _uid,
      updatedAtRaw: updatedAtRaw,
      imageRefs: imageRefs,
    );

void main() {
  testWidgets('필수값 검증: 제목·내용 비면 제출 차단 + 안내', (WidgetTester tester) async {
    _bigSurface(tester);
    final FakeCommunityWrite fake = FakeCommunityWrite();
    await tester.pumpWidget(MaterialApp(home: BoardWriteScreen(write: fake)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('등록'));
    await tester.pump();

    expect(find.text('제목과 내용을 입력해 주세요.'), findsOneWidget);
    expect(fake.postCalls, 0);
  });

  testWidgets('제출 성공: 정책 동의 게이트 통과 → createPost 호출 + pop(true)',
      (WidgetTester tester) async {
    _bigSurface(tester);
    // P0-3(UGC): 첫 게시 전 커뮤니티 이용 규정 동의 다이얼로그가 뜬다.
    // 게이트 자체의 상세 동작은 content_policy_gate_test 에서 검증.
    ContentPolicyGate.agreedThisSession = false;
    final FakeCommunityWrite fake = FakeCommunityWrite();
    bool? popResult;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                popResult = await Navigator.of(ctx).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => BoardWriteScreen(write: fake),
                  ),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // TextField 는 제목·내용 순(카테고리는 드롭다운).
    await tester.enterText(find.byType(TextField).at(0), '오답노트 공유');
    await tester.enterText(find.byType(TextField).at(1), '이렇게 정리했어요.');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    // 게시 전 정책 동의 게이트(최초 1회) → 동의하고 계속.
    expect(find.text('커뮤니티 이용 규정'), findsOneWidget);
    expect(fake.postCalls, 0); // 동의 전엔 게시되지 않는다.
    await tester.tap(find.text('동의하고 계속'));
    await tester.pumpAndSettle();

    expect(fake.postCalls, 1);
    expect(fake.lastPostTitle, '오답노트 공유');
    expect(fake.lastPostBody, '이렇게 정리했어요.');
    expect(fake.lastPostCategory, 'study'); // 기본 선택 = 첫 옵션(학습법)
    expect(fake.lastPostImageRefs, isEmpty); // 이미지 없는 작성
    expect(popResult, isTrue);
  });

  group('작성 — 이미지 첨부(학생·멘토 동일 화면·동일 경로)', () {
    setUp(() => ContentPolicyGate.agreedThisSession = true);

    Future<void> pumpCreate(
      WidgetTester tester, {
      required FakeCommunityWrite fake,
      required FakeImagePicker picker,
    }) async {
      _bigSurface(tester);
      await _pumpPushed(
          tester, BoardWriteScreen(write: fake, imagePicker: picker));
      await tester.enterText(find.byType(TextField).at(0), '제목');
      await tester.enterText(find.byType(TextField).at(1), '충분히 긴 본문입니다.');
    }

    testWidgets('이미지 1장 작성: 선택 → 칩 표시 → 업로드 ref 가 createPost 로',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite();
      final FakeImagePicker picker = FakeImagePicker(<PickedImage>[
        _img('a.png'),
      ]);
      await pumpCreate(tester, fake: fake, picker: picker);

      await tester.tap(find.text('이미지 추가'));
      await tester.pumpAndSettle();
      expect(find.text('a.png'), findsOneWidget);
      expect(find.text('이미지 (1/5)'), findsOneWidget);

      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();

      expect(fake.uploadImageCalls, 1);
      expect(fake.postCalls, 1);
      expect(fake.lastPostImageRefs,
          <String>['community-post-images/fake-uid/1_a.png']);
    });

    testWidgets('여러 이미지 작성: 순서대로 업로드·순서대로 전달',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite();
      final FakeImagePicker picker = FakeImagePicker(<PickedImage>[
        _img('a.png'),
        _img('b.png'),
        _img('c.png'),
      ]);
      await pumpCreate(tester, fake: fake, picker: picker);

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.text('이미지 추가'));
        await tester.pumpAndSettle();
      }
      expect(find.text('이미지 (3/5)'), findsOneWidget);

      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();

      expect(fake.uploadImageCalls, 3);
      expect(fake.lastPostImageRefs, <String>[
        'community-post-images/fake-uid/1_a.png',
        'community-post-images/fake-uid/2_b.png',
        'community-post-images/fake-uid/3_c.png',
      ]);
    });

    testWidgets('업로드 실패 → 글 등록 RPC 미호출(fail-closed)',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite()..failUpload = true;
      final FakeImagePicker picker = FakeImagePicker(<PickedImage>[
        _img('a.png'),
      ]);
      await pumpCreate(tester, fake: fake, picker: picker);

      await tester.tap(find.text('이미지 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();

      expect(fake.uploadImageCalls, 1);
      expect(fake.postCalls, 0);
      expect(find.textContaining('글 등록에 실패했어요.'), findsOneWidget);
    });
  });

  group('수정 — 자기 글 수정 모드(학생·멘토 동등, 역할 분기 없음)', () {
    setUp(() => ContentPolicyGate.agreedThisSession = true);

    Future<void> pumpEdit(
      WidgetTester tester, {
      required FakeCommunityWrite fake,
      required BoardPost post,
      FakeImagePicker? picker,
    }) async {
      _bigSurface(tester);
      await _pumpPushed(
          tester,
          BoardWriteScreen(
            write: fake,
            editing: post,
            imagePicker: picker ?? FakeImagePicker(),
          ));
    }

    testWidgets('학생·멘토 자기 글 수정: 같은 화면·같은 updatePost 경로',
        (WidgetTester tester) async {
      for (final String role in <String>['student', 'mentor']) {
        final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid);
        await pumpEdit(tester, fake: fake, post: _editable(authorRole: role));

        // 프리필 확인(수정 모드 진입).
        expect(find.text('글 수정'), findsOneWidget, reason: role);
        expect(find.text('게시판 제목'), findsOneWidget, reason: role);

        await tester.enterText(find.byType(TextField).at(0), '고친 제목');
        await tester.tap(find.text('수정'));
        await tester.pumpAndSettle();

        expect(fake.updateCalls, 1, reason: role);
        expect(fake.postCalls, 0, reason: role); // 수정은 create 경로가 아니다
        expect(fake.lastUpdatePostId, 'post-1', reason: role);
        expect(fake.lastUpdateTitle, '고친 제목', reason: role);
        // 행 원문 updated_at 이 재직렬화 없이 그대로 전달된다(충돌 검사 기준).
        expect(fake.lastUpdateExpectedUpdatedAt, _updatedAtRaw, reason: role);
      }
    });

    testWidgets('미승인 멘토도 앱은 막지 않는다(판정은 서버) — 승인 상태 입력 자체가 없다',
        (WidgetTester tester) async {
      // 앱 화면·레포 어디에도 승인 여부 입력이 없다 — 미승인 멘토의 자기 글
      // 수정도 같은 updatePost 호출로 나가고, 거부는 서버 코드로만 온다.
      final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid);
      await pumpEdit(tester, fake: fake, post: _editable(authorRole: 'mentor'));
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(fake.updateCalls, 1);
    });

    testWidgets('이미지 없는 수정: imageRefs 빈 목록 그대로',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid);
      await pumpEdit(tester, fake: fake, post: _editable());
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(fake.lastUpdateImageRefs, isEmpty);
      expect(fake.uploadImageCalls, 0);
    });

    testWidgets('기존 이미지 유지: 칩은 중립 라벨(원문 경로·UUID 비노출), ref 는 그대로',
        (WidgetTester tester) async {
      const List<String> existing = <String>[
        'community-post-images/$_uid/1_a.png',
        'community-post-images/$_uid/2_b.jpg',
      ];
      final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid);
      await pumpEdit(tester, fake: fake, post: _editable(imageRefs: existing));

      expect(find.text('이미지 (2/5)'), findsOneWidget);
      expect(find.text('기존 이미지 1'), findsOneWidget);
      expect(find.text('기존 이미지 2'), findsOneWidget);
      // Storage 원문 경로·소유자 UUID 를 화면에 싣지 않는다.
      expect(find.textContaining('community-post-images'), findsNothing);
      expect(find.textContaining(_uid), findsNothing);

      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(fake.lastUpdateImageRefs, existing);
      expect(fake.uploadImageCalls, 0); // 유지만 — 재업로드 없음
    });

    testWidgets('이미지 제거 수정: 뺀 ref 는 전달 목록에서 빠진다(직접 삭제는 안 한다)',
        (WidgetTester tester) async {
      const List<String> existing = <String>[
        'community-post-images/$_uid/1_a.png',
        'community-post-images/$_uid/2_b.jpg',
      ];
      final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid);
      await pumpEdit(tester, fake: fake, post: _editable(imageRefs: existing));

      // 첫 번째 기존 이미지 칩의 X 로 제거.
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.text('이미지 (1/5)'), findsOneWidget);

      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      // 남길 집합만 서버로 — 실제 Storage 삭제는 서버 removed_image_refs 기준,
      // update RPC 성공 후에만(오케스트레이터 테스트에서 고정).
      expect(fake.lastUpdateImageRefs,
          <String>['community-post-images/$_uid/2_b.jpg']);
    });

    testWidgets('이미지 추가 수정: 새 이미지만 업로드, 기존+새 순서로 전달',
        (WidgetTester tester) async {
      const List<String> existing = <String>[
        'community-post-images/$_uid/1_a.png',
      ];
      final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid);
      final FakeImagePicker picker =
          FakeImagePicker(<PickedImage>[_img('new.png')]);
      await pumpEdit(tester,
          fake: fake, post: _editable(imageRefs: existing), picker: picker);

      await tester.tap(find.text('이미지 추가'));
      await tester.pumpAndSettle();
      expect(find.text('이미지 (2/5)'), findsOneWidget);

      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(fake.uploadImageCalls, 1);
      expect(fake.lastUpdateImageRefs, <String>[
        'community-post-images/$_uid/1_a.png',
        'community-post-images/fake-uid/1_new.png',
      ]);
    });

    testWidgets('수정 실패 후 재시도: 새 이미지를 다시 올리지 않는다(중복 업로드 방지)',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid)
        ..failUpdate = true;
      final FakeImagePicker picker =
          FakeImagePicker(<PickedImage>[_img('new.png')]);
      await pumpEdit(tester, fake: fake, post: _editable(), picker: picker);

      await tester.tap(find.text('이미지 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(fake.updateCalls, 1);
      expect(fake.uploadImageCalls, 1);
      expect(find.textContaining('글 수정에 실패했어요.'), findsOneWidget);

      fake.failUpdate = false;
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(fake.updateCalls, 2);
      expect(fake.uploadImageCalls, 1); // 이미 올라간 ref 재사용
    });

    testWidgets('최대 5장: 가득 차면 픽커를 열지 않고 안내한다',
        (WidgetTester tester) async {
      final List<String> five = <String>[
        for (int i = 1; i <= 5; i++) 'community-post-images/$_uid/${i}_i.png',
      ];
      final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid);
      final FakeImagePicker picker = FakeImagePicker(<PickedImage>[
        _img('overflow.png'),
      ]);
      await pumpEdit(tester,
          fake: fake, post: _editable(imageRefs: five), picker: picker);

      expect(find.text('이미지 (5/5)'), findsOneWidget);
      await tester.tap(find.text('이미지 추가'));
      await tester.pumpAndSettle();

      expect(picker.calls, 0); // 픽커 자체를 열지 않는다
      expect(find.text('이미지는 최대 5장까지 첨부할 수 있어요.'), findsOneWidget);
    });

    testWidgets('updated_at 원문이 없으면 RPC 를 보내지 않는다(충돌 검사 미성립)',
        (WidgetTester tester) async {
      final FakeCommunityWrite fake = FakeCommunityWrite(uid: _uid);
      await pumpEdit(tester,
          fake: fake, post: _editable(updatedAtRaw: null));
      await tester.tap(find.text('수정'));
      await tester.pumpAndSettle();
      expect(fake.updateCalls, 0);
      expect(find.textContaining('글 정보를 확인하지 못했어요.'), findsOneWidget);
    });
  });
}
