import '../../../shared/errors/app_error.dart';
import 'qna_error_mapper.dart';

/// 지시서 2-6: DB `UNIQUE(room, author_id)` 가 아직 살아 있어 두 번째 노트 INSERT 가
/// 23505 로 실패한다. 그 경우 이 문구를 그대로 보여준다(제약은 DB 배치에서 푼다 —
/// 풀리면 이 오류는 더 나오지 않는다).
const String kNoteAlreadyExistsMessage = '이미 남긴 노트가 있어요. 곧 여러 개를 남길 수 있게 돼요';

class NoteAlreadyExistsError extends AppError {
  const NoteAlreadyExistsError({Object? cause})
      : super(kNoteAlreadyExistsMessage, cause: cause);
}

/// 노트 INSERT 예외 → 사용자용 오류. 23505(unique_violation)만 특별 취급하고
/// 나머지는 질문방 공통 매핑(원문 비노출)을 따른다.
Object mapNoteInsertError(Object e) {
  if (e is NoteAlreadyExistsError) return e;
  if (isUniqueViolation(e)) return NoteAlreadyExistsError(cause: e);
  return mapQnaError(e);
}
