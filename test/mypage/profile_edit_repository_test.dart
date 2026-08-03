import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ssambership_app/features/mypage/data/profile_edit_repository.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 프로필 수정 RPC 계약(api_app_v1.user_profile_update_self) — 파라미터 의미
/// (생략=유지 / ''=비우기 / 멘토는 미전송)와 봉투 검증·오류 매핑을 fake 백엔드로
/// 고정한다(Supabase 미접촉).
/// "result 미지정" 과 "명시적 null 결과" 를 구분하기 위한 const 센티넬.
/// (`result ?? default` 로는 null 봉투 케이스를 만들 수 없어 strict 검증을 못 뚫는다.)
class _Unset {
  const _Unset();
}

const _Unset _unset = _Unset();

class _FakeBackend implements ProfileEditBackend {
  _FakeBackend({Object? result = _unset, this.error}) : result = result;

  Object? result;
  Object? error;
  final List<(String, Map<String, dynamic>)> calls =
      <(String, Map<String, dynamic>)>[];

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) async {
    calls.add((fn, Map<String, dynamic>.of(params)));
    final Object? e = error;
    if (e != null) throw e;
    if (identical(result, _unset)) {
      return <String, dynamic>{
        'ok': true,
        'contract_version': 1,
        'nickname': '닉',
        'grade_level': null,
        'updated_at': '2026-08-03T00:00:00Z',
      };
    }
    return result; // 명시적으로 넘긴 값(널 포함)을 그대로 반환.
  }
}

void main() {
  ProfileEditRepository repoOf(_FakeBackend b) =>
      ProfileEditRepository(backend: b);

  test('닉네임+학년 → user_profile_update_self 에 두 파라미터', () async {
    final _FakeBackend b = _FakeBackend();
    await repoOf(b).updateProfile(nickname: '새닉', gradeLevel: '고3');

    final (String fn, Map<String, dynamic> params) = b.calls.single;
    expect(fn, 'user_profile_update_self');
    expect(params, <String, dynamic>{
      'p_nickname': '새닉',
      'p_grade_level': '고3',
    });
  });

  test("학년 비우기 = p_grade_level '' 전송(생략과 구분되는 서버 계약)", () async {
    final _FakeBackend b = _FakeBackend();
    await repoOf(b).updateProfile(nickname: '새닉', gradeLevel: '');
    expect(b.calls.single.$2['p_grade_level'], '');
  });

  test('멘토(gradeLevel null) → p_grade_level 파라미터 자체를 생략', () async {
    final _FakeBackend b = _FakeBackend();
    await repoOf(b).updateProfile(nickname: '새닉');
    expect(b.calls.single.$2.containsKey('p_grade_level'), isFalse);
    expect(b.calls.single.$2['p_nickname'], '새닉');
  });

  test('둘 다 null → 호출 자체를 생략(변경 없음)', () async {
    final _FakeBackend b = _FakeBackend();
    await repoOf(b).updateProfile();
    expect(b.calls, isEmpty);
  });

  test('성공 봉투 strict — ok/contract_version 이 어긋나면 AppError', () async {
    for (final Object? bad in <Object?>[
      null,
      'weird',
      <String, dynamic>{'ok': false},
      <String, dynamic>{'ok': true, 'contract_version': 2},
    ]) {
      final _FakeBackend b = _FakeBackend(result: bad);
      await expectLater(
        repoOf(b).updateProfile(nickname: 'n'),
        throwsA(isA<AppError>()),
        reason: '$bad',
      );
    }
  });

  test('서버 코드 → 한글 문구(코드 비노출) — ACCOUNT_NOT_ACTIVE 는 통일 문장', () async {
    const Map<String, String> cases = <String, String>{
      'AUTH_REQUIRED': '로그인이 필요해요.',
      'ROLE_NOT_ALLOWED': '현재 회원 유형으로는 프로필을 수정할 수 없어요.',
      'ACCOUNT_BANNED': '계정 이용이 제한된 상태예요. 자세한 내용은 문의해 주세요.',
      'ACCOUNT_SUSPENDED': '계정 이용이 제한된 상태예요. 자세한 내용은 문의해 주세요.',
      // 커뮤니티/qna 매퍼와 같은 문장(통일 카피).
      'ACCOUNT_NOT_ACTIVE': '현재 계정 상태에서는 이 기능을 사용할 수 없어요.',
      'ACCOUNT_DELETION_IN_PROGRESS': '탈퇴 처리 중에는 프로필을 수정할 수 없어요.',
      'NICKNAME_REQUIRED': '표시명을 입력해 주세요.',
      'NICKNAME_TOO_LONG': '표시명은 30자 이내로 입력해 주세요.',
      'GRADE_LEVEL_NOT_ALLOWED': '멘토 계정은 학년을 설정할 수 없어요.',
      'GRADE_LEVEL_TOO_LONG': '학년은 20자 이내로 입력해 주세요.',
    };
    for (final MapEntry<String, String> c in cases.entries) {
      final _FakeBackend b = _FakeBackend(
        error: PostgrestException(message: c.key),
      );
      await expectLater(
        repoOf(b).updateProfile(nickname: 'n', gradeLevel: '고1'),
        throwsA(isA<AppError>().having(
          (AppError e) => e.userMessage,
          'userMessage',
          c.value,
        )),
        reason: c.key,
      );
    }
  });

  test('미지 예외는 원본 그대로 전파(문구 날조 금지)', () async {
    final _FakeBackend b = _FakeBackend(
      error: const PostgrestException(message: 'weird server text'),
    );
    await expectLater(
      repoOf(b).updateProfile(nickname: 'n'),
      throwsA(isA<PostgrestException>()),
    );
  });
}
