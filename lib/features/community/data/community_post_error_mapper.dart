import '../../../shared/errors/app_error.dart';

/// 커뮤니티 게시글 쓰기(작성·수정) 공용 서버 오류 코드 → 사용자용 한글 문구.
///
/// `api_app_v1.community_post_create` / `community_post_update` 가 공유하는
/// 실패 봉투 코드를 한곳에서 매핑한다. 작성·수정 전용 코드(멱등/충돌 등)는
/// 각 gateway 가 이 함수보다 먼저 처리하고, 여기 없는 미지의 코드는 null 을
/// 돌려줘 호출부의 fail-closed 공통 문구로 수렴시킨다.
///
/// 계약 코드는 비민감 식별자지만 **화면에는 코드를 싣지 않는다**(한글 문구만).
AppError? communityPostWriteContractError(Object? code) {
  if (code is! String) return null;
  switch (code) {
    case 'AUTH_REQUIRED':
      return const AppError('로그인이 필요해요.');
    // 역할 계약: S3-C 가 student+mentor 로 수렴한다. 수렴 전 서버가 쓰는
    // ROLE_NOT_MENTOR 도 같은 상황이므로 같은 문구로 묶는다.
    case 'ROLE_NOT_ALLOWED':
    case 'ROLE_NOT_MENTOR':
      return const AppError('현재 회원 유형으로는 게시판 글을 쓸 수 없어요.');
    case 'MENTOR_NOT_APPROVED':
      return const AppError('멘토 승인 후에 글을 쓸 수 있어요.');
    case 'ACCOUNT_BANNED':
      return const AppError('이용이 제한된 계정이에요. 고객센터로 문의해 주세요.');
    case 'ACCOUNT_SUSPENDED':
      return const AppError('일시 정지된 계정이에요. 정지 기간이 끝난 뒤 다시 시도해 주세요.');
    case 'ACCOUNT_DELETION_IN_PROGRESS':
      return const AppError('탈퇴 처리 중에는 글을 쓸 수 없어요.');
    case 'ACCOUNT_NOT_ACTIVE':
      return const AppError('현재 계정 상태에서는 이 기능을 사용할 수 없어요.');
    case 'TITLE_REQUIRED':
      return const AppError('제목을 입력해 주세요.');
    case 'CATEGORY_INVALID':
      return const AppError('카테고리를 다시 선택해 주세요.');
    case 'BODY_TOO_SHORT':
      return const AppError('내용을 10자 이상 입력해 주세요.');
    case 'IMAGE_COUNT_EXCEEDED':
      return const AppError('이미지는 최대 5장까지 첨부할 수 있어요.');
    case 'IMAGE_MIME_NOT_ALLOWED':
      return const AppError('JPG·PNG·WEBP·GIF 이미지만 첨부할 수 있어요.');
    case 'IMAGE_SIZE_EXCEEDED':
      return const AppError('이미지는 한 장당 5MB까지 첨부할 수 있어요.');
  }
  // IMAGE_REF_INVALID · IMAGE_NOT_OWNED · IMAGE_OBJECT_NOT_FOUND 등 나머지
  // 첨부 계열은 사용자가 할 수 있는 조치가 같다(다시 첨부).
  if (code.startsWith('IMAGE_')) {
    return const AppError('첨부한 이미지를 확인하지 못했어요. 다시 첨부해 주세요.');
  }
  return null;
}
