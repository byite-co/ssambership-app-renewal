import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 아웃바운드 API 매니페스트(계약 수렴 잠금) — lib/ 소스를 직접 스캔해
/// 앱이 호출하는 RPC/테이블/뷰/스키마/Storage 버킷의 **전체 집합**을 고정한다.
///
/// - 새 서버 표면을 추가/제거하면 이 매니페스트를 함께 갱신해야 한다(의도된
///   변경만 통과). REVOKE 된 레거시 표면은 word-boundary 로 0건을 강제한다.
/// - 주석은 스캔에서 제외한다(레거시 이름을 '설명'하는 주석은 위반이 아니다).
///   문자열 URL 보호를 위해 `://` 는 주석 시작으로 보지 않는다.
/// - 식별자 경유 호출(.rpc(fn)/.from(_table) 등)은 별도 allowlist 로 고정하고,
///   상수 정의값까지 대조한다(이름 뒤에 숨는 호출 차단).

const Set<String> kExpectedRpcNames = <String>{
  // 계정·상태
  'account_deletion_cancel_self',
  'account_deletion_request_self_v2',
  'account_deletion_request_self_consented_v2',
  'account_deletion_status_self',
  'account_deletion_write_blocked',
  // 프로필
  'user_profile_update_self',
  // 질문방(qna_*)
  'ensure_free_question_room', // api_app_v1 — 무료질문 첫 진입 시 방 보장(N1)
  'qna_append_message',
  'qna_confirm_thread',
  'qna_create_free_question_thread',
  'qna_create_question_thread',
  'qna_register_attachment',
  'weekly_question_usage_self',
  'weekly_question_usage_self_batch',
  'get_mentor_student_nicknames',
  // 멘토 찾기
  'get_mentor_avg_response_hours',
  // A-4a 멘토 콘솔(판정표 docs/renewal/a4a-triage-2026-09-05.md)
  'mentor_payout_account_update_self', // api_web_v1 F13 — 정산 계좌
  'mentor_plan_prices_set_self', // api_web_v1 F8 — 요금제(밴드 DB 강제)
  'mentor_profile_update_self', // api_web_v1 F7 — 프로필 9필드·구독 열림
  'set_individual_question_price', // 개별질문 답변 단가
  'mentor_settlement_summary', // 정산 월 요약
  'mentor_settlement_lines', // 정산 건별 내역
  // A-4b 구독 결제·해지 예약·환불(api_app_v1 — DB-4 199·200)
  'subscribe_with_cash',
  'subscription_cancel_at_period_end',
  'subscription_cancel_undo',
  'refund_estimate',
  'refund_request_create',
  'mentor_activity_set', // A-4b ④ 활동 상태(DB-4 201)
  'mentor_student_id_document_set_self', // A-4b ⑦ 학생증 사후 제출(DB-4 203)
  // 개별질문
  'add_individual_question_attachment',
  'claim_individual_question_as_mentor',
  'create_individual_question_as_student',
  'iq_append_message',
  'list_open_individual_questions_for_mentor',
  'refund_individual_question',
  'release_individual_question',
  // 커뮤니티
  // [QA-C7] 차단 목록 표시명 — users SELECT 정책이 본인+admin 뿐이라 타인 닉네임을
  // 앱이 직접 읽을 수 없다. 정의자 RPC 가 본인 차단분의 닉네임만 돌려준다
  // (웹 migration 20260807020000).
  'my_blocked_users',
  'community_comment_soft_delete_self',
  'community_post_soft_delete',
  'community_post_view_record_v2',
  'shortform_view_record_v2',
  // 알림
  'mark_all_notifications_read',
  'mark_notification_read',
  'notification_unread_count_self',
  // 버전 게이트
  'get_mobile_app_version_policy',
};

/// 식별자 경유 rpc 호출 — fn(백엔드 seam 2곳: 프로필·계정탈퇴)과 게시판
/// 작성/수정 함수 상수. 상수 값은 아래 별도 테스트에서 대조한다.
const Set<String> kExpectedRpcIdentifiers = <String>{
  'fn',
  'kBoardPostCreateFunction',
  'kBoardPostUpdateFunction',
};

const Set<String> kExpectedSchemas = <String>{'api_app_v1', 'api_web_v1'};

const Set<String> kExpectedSchemaIdentifiers = <String>{
  'kBoardPostCreateSchema',
  'schema', // comments_gateway seam 파라미터(N5 — api_web_v1 뷰 읽기)
};

/// DB 테이블/뷰(문자열 리터럴 from) — 읽기/쓰기 표면 전체.
const Set<String> kExpectedTables = <String>{
  // 코어(세션·구독·계정)
  'users', // ★ SELECT 전용 — update 체인 금지는 아래 별도 테스트.
  'subscriptions',
  'subscription_settlement_items',
  // N5: 지갑·캐시내역 읽기는 본인 한정 invoker 뷰(api_web_v1)로 이행.
  'my_wallet_v1',
  'my_cash_ledger_v1',
  'notifications',
  // 질문방
  'mentor_student_rooms',
  'question_threads',
  'question_messages',
  'question_attachments',
  'connection_notes',
  'mentor_profiles',
  // A-4a 멘토 콘솔 — 본인 pending 행 직접 INSERT(RLS msv/macc_insert_own_pending)
  'mentor_school_verifications',
  'mentor_academic_record_change_requests',
  // 멘토 찾기(계약 수렴: 디렉터리는 뷰)
  'mentor_directory_v1',
  'mentor_plans',
  'free_question_usage',
  // 개별질문
  'individual_questions',
  'individual_question_messages',
  'individual_question_attachments',
  'mentor_individual_question_pricing',
  // 커뮤니티(계약 수렴: 게시판 읽기는 뷰)
  'community_posts_v1',
  // ★ community_comments_v1(N5 게시판 댓글 읽기 뷰)은 comments_gateway 의
  //   table seam 파라미터로 넘어가므로 from-리터럴 집합엔 나타나지 않는다.
  'shortform_posts',
  'post_reactions',
  'shortform_reactions',
  'content_reports',
};

/// 식별자 경유 from — 상수 테이블명(정의값은 별도 테스트에서 대조).
const Set<String> kExpectedTableIdentifiers = <String>{
  '_table', // user_blocks(차단) · favorites(찜)
  '_reportsTable', // content_reports(질문방 신고)
  'table', // comments_gateway(comments/community_comments) 등 seam 파라미터
};

/// Storage 버킷 — 전부 상수 경유(리터럴 from 은 0건).
const Set<String> kExpectedBucketIdentifiers = <String>{
  'bucket',
  'IndividualQuestionRepository.attachmentBucket',
  'SupabaseAttachmentUploader.bucket',
  'InkStoragePaths.annotationBucket',
  'ShortformMediaUrlResolver.videoBucket',
  'kCommunityPostImagesBucket',
  // A-4a 멘토 콘솔
  'kStudentIdImagesBucket', // 학력 인증·학적 변경 서류(비공개)
  'kProfileAvatarsBucket', // 멘토 아바타(public)
};

/// 버킷 상수 정의값(이름 뒤에 숨는 버킷 차단).
const Set<String> kExpectedBucketNames = <String>{
  'individual-question-attachments',
  'question-room-attachments',
  'connection-note-ink',
  'scan-annotations',
  'shortform-videos',
  'community-post-images',
  'student-id-images',
  'profile-avatars',
};

/// REVOKE/금지 표면 — 주석 제외 코드에서 0건(word boundary — v2 는 무관).
const List<String> kForbiddenWords = <String>[
  'mentor_directory_list_v2',
  'mentor_profiles_for_directory_v2',
  'mentor_user_public_v2',
  'increment_shortform_post_view',
  'account_deletion_request_self',
  'account_deletion_request_self_consented',
  'record_cash_topup',
  'subscription_checkout_confirm',
];

/// 주석 제거(라인 주석 — `://` 는 URL 로 보고 유지).
String stripComments(String src) {
  final RegExp lineComment = RegExp(r'(?<!:)//.*$');
  return src
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((String line) => line.replaceFirst(lineComment, ''))
      .join('\n');
}

/// lib/ 전체 dart 소스(주석 제거) — 파일별.
Map<String, String> libSources() {
  final Map<String, String> out = <String, String>{};
  final List<File> files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList();
  expect(files, isNotEmpty, reason: 'lib 스캔 실패 — cwd 가 패키지 루트가 아니다');
  for (final File f in files) {
    out[f.path] = stripComments(f.readAsStringSync());
  }
  return out;
}

/// [pattern] 직전 lookback 이 [tail] 로 끝나는지(멀티라인 체인 허용).
bool _lookbackEndsWith(String src, int start, RegExp tail) {
  final int from = start - 40 < 0 ? 0 : start - 40;
  return tail.hasMatch(src.substring(from, start));
}

final RegExp _storageTail = RegExp(r'storage\s*$');
final RegExp _clientTail = RegExp(r'(_client|client|\bc)\s*$');

void main() {
  late final Map<String, String> sources = libSources();

  test('RPC 리터럴 집합 = 매니페스트(추가·삭제는 의도된 변경만)', () {
    final Set<String> found = <String>{};
    final RegExp rpcLit =
        RegExp(r"\.rpc(?:<[^>(]*>)?\(\s*'([A-Za-z0-9_]+)'");
    for (final String src in sources.values) {
      for (final RegExpMatch m in rpcLit.allMatches(src)) {
        found.add(m.group(1)!);
      }
    }
    expect(found, kExpectedRpcNames);
  });

  test('RPC 식별자 호출 = allowlist + 상수 정의값 대조', () {
    final Set<String> found = <String>{};
    final RegExp rpcId =
        RegExp(r'\.rpc(?:<[^>(]*>)?\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,)]');
    for (final String src in sources.values) {
      for (final RegExpMatch m in rpcId.allMatches(src)) {
        found.add(m.group(1)!);
      }
    }
    expect(found, kExpectedRpcIdentifiers);

    final String all = sources.values.join('\n').replaceAll(RegExp(r'\s+'), '');
    expect(all.contains("kBoardPostCreateFunction='community_post_create'"),
        isTrue);
    expect(all.contains("kBoardPostUpdateFunction='community_post_update'"),
        isTrue);
  });

  test('schema 집합 = {api_app_v1, api_web_v1} (+상수 1개)', () {
    final Set<String> lits = <String>{};
    final Set<String> ids = <String>{};
    final RegExp schemaLit = RegExp(r"\.schema\(\s*'([A-Za-z0-9_]+)'\s*\)");
    final RegExp schemaId =
        RegExp(r'\.schema\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)');
    for (final String src in sources.values) {
      for (final RegExpMatch m in schemaLit.allMatches(src)) {
        lits.add(m.group(1)!);
      }
      for (final RegExpMatch m in schemaId.allMatches(src)) {
        ids.add(m.group(1)!);
      }
    }
    expect(lits, kExpectedSchemas);
    expect(ids, kExpectedSchemaIdentifiers);
    final String all = sources.values.join('\n').replaceAll(RegExp(r'\s+'), '');
    expect(all.contains("kBoardPostCreateSchema='api_app_v1'"), isTrue);
  });

  test('테이블/뷰 리터럴 집합 = 매니페스트 · Storage 버킷 리터럴 0건', () {
    final Set<String> tables = <String>{};
    final Set<String> bucketLiterals = <String>{};
    final RegExp fromLit = RegExp(r"\.from\(\s*'([A-Za-z0-9_-]+)'\s*\)");
    for (final String src in sources.values) {
      for (final RegExpMatch m in fromLit.allMatches(src)) {
        if (_lookbackEndsWith(src, m.start, _storageTail)) {
          bucketLiterals.add(m.group(1)!);
        } else {
          tables.add(m.group(1)!);
        }
      }
    }
    expect(tables, kExpectedTables);
    expect(bucketLiterals, isEmpty,
        reason: '버킷은 상수 경유만 — 리터럴이 생기면 매니페스트를 확장할 것');
  });

  test('식별자 from — DB 는 {_table,_reportsTable,table}, 버킷은 상수 9종', () {
    final Set<String> tableIds = <String>{};
    final Set<String> bucketIds = <String>{};
    final RegExp fromId =
        RegExp(r'\.from\(\s*([A-Za-z_][A-Za-z0-9_.]*)\s*[,)]');
    for (final String src in sources.values) {
      for (final RegExpMatch m in fromId.allMatches(src)) {
        if (_lookbackEndsWith(src, m.start, _storageTail)) {
          bucketIds.add(m.group(1)!);
        } else if (_lookbackEndsWith(src, m.start, _clientTail)) {
          tableIds.add(m.group(1)!);
        }
        // 그 외(Map.from/ThreadStatusCounts.from 등 생성자)는 API 호출이 아니다.
      }
    }
    expect(tableIds, kExpectedTableIdentifiers);
    expect(bucketIds, kExpectedBucketIdentifiers);
  });

  test('버킷 상수 정의값 = 매니페스트(이름 뒤에 숨는 버킷 차단)', () {
    final String all = sources.values.join('\n').replaceAll(RegExp(r'\s+'), '');
    for (final String name in kExpectedBucketNames) {
      expect(all.contains("='$name'"), isTrue, reason: '$name 상수 정의가 없다');
    }
    // 상수 이름 → 값 스팟 체크(핵심 4종).
    expect(all.contains("attachmentBucket='individual-question-attachments'"),
        isTrue);
    expect(all.contains("bucket='question-room-attachments'"), isTrue);
    expect(all.contains("annotationBucket='scan-annotations'"), isTrue);
    expect(
        all.contains("kCommunityPostImagesBucket='community-post-images'"),
        isTrue);
  });

  test('금지 표면 0건(word boundary — *_v2 는 별개 단어)', () {
    for (final MapEntry<String, String> e in sources.entries) {
      for (final String name in kForbiddenWords) {
        expect(RegExp('\\b$name\\b').hasMatch(e.value), isFalse,
            reason: '${e.key} 에 금지 표면 $name');
      }
    }
  });

  test("from('users') 는 SELECT 전용 — 같은 문장 체인에 .update( 금지", () {
    final RegExp usersFrom = RegExp(r"\.from\(\s*'users'\s*\)");
    for (final MapEntry<String, String> e in sources.entries) {
      for (final RegExpMatch m in usersFrom.allMatches(e.value)) {
        final int semi = e.value.indexOf(';', m.end);
        final String chain = e.value
            .substring(m.end, semi == -1 ? e.value.length : semi);
        expect(chain.contains('.update('), isFalse,
            reason: '${e.key} 가 users 를 직접 UPDATE 한다 — RPC 단일 경로 위반');
        expect(chain.contains('.insert('), isFalse,
            reason: '${e.key} 가 users 를 직접 INSERT 한다');
      }
    }
  });

  test("community_posts 베이스 테이블 직접 접근 0건(뷰/RPC 단일 경로)", () {
    final RegExp base = RegExp(r"\.from\(\s*'community_posts'\s*\)");
    for (final MapEntry<String, String> e in sources.entries) {
      expect(base.hasMatch(e.value), isFalse,
          reason: '${e.key} 가 community_posts 베이스 테이블을 직접 조회/변경한다');
    }
  });

  test("'firebase' 문자열 0건(App-F0 유지)", () {
    for (final MapEntry<String, String> e in sources.entries) {
      expect(e.value.toLowerCase().contains('firebase'), isFalse,
          reason: '${e.key} 에 firebase 문자열');
    }
  });

  group('가드 자기-검증 — 탐지 로직이 실제 위반에 반응한다', () {
    test('rpc/from/schema 추출 정규식', () {
      const String planted = """
        await _client.rpc('bad_rpc_name');
        await _client
            .schema('bad_schema')
            .from('bad_table')
            .select();
        await _client.storage
            .from('bad-bucket')
            .download('x');
      """;
      expect(
        RegExp(r"\.rpc(?:<[^>(]*>)?\(\s*'([A-Za-z0-9_]+)'")
            .firstMatch(planted)!
            .group(1),
        'bad_rpc_name',
      );
      final RegExp fromLit = RegExp(r"\.from\(\s*'([A-Za-z0-9_-]+)'\s*\)");
      final List<RegExpMatch> froms = fromLit.allMatches(planted).toList();
      expect(froms.length, 2);
      expect(_lookbackEndsWith(planted, froms[0].start, _storageTail), isFalse);
      expect(_lookbackEndsWith(planted, froms[1].start, _storageTail), isTrue);
    });

    test('금지어 word boundary — v2 접미는 잡지 않고 원형만 잡는다', () {
      final RegExp re = RegExp(r'\baccount_deletion_request_self\b');
      expect(re.hasMatch("rpc('account_deletion_request_self')"), isTrue);
      expect(re.hasMatch("rpc('account_deletion_request_self_v2')"), isFalse);
      expect(
        re.hasMatch("rpc('account_deletion_request_self_consented_v2')"),
        isFalse,
      );
    });

    test('주석 제거 — 레거시 설명 주석은 위반이 아니고 URL 은 살아남는다', () {
      expect(
        stripComments('// mentor_user_public_v2 는 폐기\nfinal a = 1;')
            .contains('mentor_user_public_v2'),
        isFalse,
      );
      expect(
        stripComments("final u = 'https://x.example/path';")
            .contains('https://x.example/path'),
        isTrue,
      );
    });

    test('주석 제거 — CRLF 소스에서도 설명 주석의 금지어를 제거한다', () {
      const String crlfFixture = '// increment_shortform_post_view 는 폐기\r\n'
          '// Firebase-free crash reporting\r\n'
          "final u = 'https://x.example/path';\r\n";
      final String stripped = stripComments(crlfFixture);

      expect(stripped.contains('increment_shortform_post_view'), isFalse);
      expect(stripped.toLowerCase().contains('firebase'), isFalse);
      expect(stripped.contains('https://x.example/path'), isTrue);
      expect(stripped.contains('\r'), isFalse);
    });
  });
}
