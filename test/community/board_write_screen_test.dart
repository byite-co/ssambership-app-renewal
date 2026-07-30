import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/community/data/community_post_actions.dart';
import 'package:ssambership_app/features/community/data/community_post_envelope.dart';
import 'package:ssambership_app/features/community/data/community_post_images.dart';
import 'package:ssambership_app/features/community/ui/board/board_write_screen.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';

import 'fakes.dart';

/// 게시판 글쓰기 스모크 — DB 미접촉(FakeCommunityWrite 주입).
void main() {
  testWidgets('필수값 검증: 제목·내용 비면 제출 차단 + 안내', (WidgetTester tester) async {
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
    expect(fake.lastPostIdempotencyKey, isNotNull); // 시도당 1회 생성(UUID).
    expect(popResult, isTrue);
  });

  testWidgets('멱등키 규약: 응답 불명확 후 재등록은 같은 키, 확정 거부 후엔 새 키(§6.3)',
      (WidgetTester tester) async {
    ContentPolicyGate.agreedThisSession = true;
    final _ScriptedWrite fake = _ScriptedWrite();
    await tester.pumpWidget(MaterialApp(home: BoardWriteScreen(write: fake)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '제목');
    await tester.enterText(find.byType(TextField).at(1), '내용입니다');

    // 1차: 응답 불명확 → 키 유지.
    fake.nextError = const CommunityCreateUnclear();
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    final String? k1 = fake.lastPostIdempotencyKey;
    expect(k1, isNotNull);

    // 2차: 여전히 불명확 — 같은 키 재사용(새 키 금지).
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    expect(fake.lastPostIdempotencyKey, k1);

    // 3차: 확정 거부(도메인 실패) — 이번 시도 종결.
    fake.nextError = CommunityWriteRejected('BODY_TOO_SHORT');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    expect(fake.lastPostIdempotencyKey, k1); // 이 호출 자체는 같은 키였고,

    // 4차: 다음 등록은 '새 작성 시도' — 새 키.
    fake.nextError = null;
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    expect(fake.lastPostIdempotencyKey, isNotNull);
    expect(fake.lastPostIdempotencyKey, isNot(k1));
    expect(fake.postCalls, 4);
  });
}

/// 다음 호출의 결과를 스크립트할 수 있는 쓰기 가짜(멱등키 규약 검증용).
class _ScriptedWrite extends FakeCommunityWrite {
  Object? nextError;

  @override
  Future<CreatedBoardPostV1> createPost({
    required String title,
    required String body,
    required String category,
    required String idempotencyKey,
    List<ValidatedPostImage> images = const <ValidatedPostImage>[],
  }) async {
    final Future<CreatedBoardPostV1> base = super.createPost(
      title: title,
      body: body,
      category: category,
      idempotencyKey: idempotencyKey,
      images: images,
    );
    final Object? e = nextError;
    if (e != null) throw e;
    return base;
  }
}
