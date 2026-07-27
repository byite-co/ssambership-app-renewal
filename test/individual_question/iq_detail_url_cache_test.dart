import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/features/individual_question/data/iq_attachment_url_resolver.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';

/// P3-6 — 상세 화면의 첨부 서명 URL: 리빌드마다 재발급하던 per-build
/// FutureBuilder 를 상태 메모 + 리졸버 캐시로 교체했는지 화면 단위로 검증.
class _CountingBackend implements IqAttachmentUrlBackend {
  int signCount = 0;

  @override
  String? get currentUserId => 'user-1';

  @override
  Future<String> createSignedUrl(
      String storagePath, int expiresInSeconds) async {
    signCount++;
    // 실제 로드는 flutter_test 의 HttpClient(400)로 실패하지만 errorBuilder
    // 가 삼킨다 — 여기서는 '발급 호출 횟수'만 본다.
    return 'https://cdn.example/$storagePath?v=$signCount';
  }
}

IqDetailData _data() => IqDetailData(
      question: IndividualQuestion(
        id: 'q-1',
        studentId: 's1',
        type: IndividualQuestionType.open,
        status: IndividualQuestionStatus.claimed,
        title: '수열 질문',
        body: '본문',
        priceCents: 500000,
        createdAt: DateTime(2026, 7, 1),
      ),
      messages: const <IqMessage>[],
      attachments: const <IqAttachment>[
        IqAttachment(
          id: 'att-1',
          storagePath: 'q-1/1-000001.png',
          fileName: '문제.png',
          mimeType: 'image/png',
        ),
      ],
    );

void main() {
  testWidgets('첨부 서명 URL 은 리빌드에도 1회만 발급된다(Future 상태 메모)',
      (WidgetTester tester) async {
    final _CountingBackend backend = _CountingBackend();
    final IqAttachmentUrlResolver resolver = IqAttachmentUrlResolver(backend);
    Widget screen() => MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: IqDetailScreen(
            questionId: 'q-1',
            roleOverride: AppRole.student,
            loaderOverride: () async => _data(),
            urlResolverOverride: resolver,
          ),
        );

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(backend.signCount, 1); // 최초 1회 발급.

    // 강제 리빌드(같은 위치·타입 → State 유지) 반복 — 재발급이 없어야 한다.
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(backend.signCount, 1); // per-build 재요청 없음.
  });
}
