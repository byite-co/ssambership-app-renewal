import '../../../design/widgets/app_blocks.dart';
import '../data/mentor_console_models.dart';

/// 검토형 제출 상태(학력 인증·학적 변경) 표시 라벨 — 코드값 노출 금지.
String reviewStatusLabel(ReviewStatus s) {
  switch (s) {
    case ReviewStatus.pending:
      return '검토 중';
    case ReviewStatus.approved:
      return '승인';
    case ReviewStatus.rejected:
      return '반려';
    case ReviewStatus.resubmitRequired:
      return '재제출 필요';
    case ReviewStatus.superseded:
      return '이전 기록';
    case ReviewStatus.unknown:
      return '상태 확인 필요';
  }
}

AppCalloutTone reviewStatusTone(ReviewStatus s) {
  switch (s) {
    case ReviewStatus.approved:
      return AppCalloutTone.success;
    case ReviewStatus.rejected:
      return AppCalloutTone.danger;
    case ReviewStatus.pending:
    case ReviewStatus.resubmitRequired:
    case ReviewStatus.unknown:
      return AppCalloutTone.warning;
    case ReviewStatus.superseded:
      return AppCalloutTone.neutral;
  }
}
