import 'models/room.dart';

/// 질문방 상대(counterparty) — 신고·차단 대상의 **정본**.
///
/// ★ 상대 id 는 오직 room participant 데이터(`mentor_student_rooms.student_id` /
///   `mentor_id`)에서만 도출한다. 메시지 첫 작성자 추정·화면 문자열 파싱·
///   닉네임 조회·UUID 하드코딩은 금지(S3-E §7).
/// ★ 도출에 실패하면 null — 호출부는 안전 메뉴를 **비활성화**한다.
/// ★ [userId] 는 화면에 표시하지 않는다(raw UUID 비노출). 표시는 [displayName] 만.
class RoomCounterparty {
  const RoomCounterparty({required this.userId, required this.displayName});

  /// 상대 사용자 id(내부 전용 — 신고 target_id / 차단 blocked_id).
  final String userId;

  /// 화면 표기용 이름(멘토명/학생명). id 를 노출하지 않기 위한 대체 표기.
  final String displayName;

  /// 방 참여자 데이터에서 상대를 도출한다.
  ///
  /// - 내가 학생이면 상대는 멘토, 내가 멘토면 상대는 학생.
  /// - 방 정보가 없거나, 내가 이 방의 당사자가 아니거나, 도출된 상대가
  ///   현재 사용자와 같으면(자기 자신) null 을 돌려준다.
  static RoomCounterparty? of(
    Room? room, {
    required String? currentUid,
    required String displayName,
  }) {
    if (room == null) return null;
    final String? uid = currentUid;
    if (uid == null || uid.isEmpty) return null;

    final String? other;
    if (uid == room.studentId) {
      other = room.mentorId;
    } else if (uid == room.mentorId) {
      other = room.studentId;
    } else {
      other = null; // 이 방의 당사자가 아님 — 안전 메뉴 비활성화.
    }
    if (other == null || other.isEmpty) return null;
    if (other == uid) return null; // 자기 자신 신고·차단 금지(방어).

    final String name = displayName.trim();
    return RoomCounterparty(
      userId: other,
      displayName: name.isNotEmpty ? name : '상대방',
    );
  }
}
