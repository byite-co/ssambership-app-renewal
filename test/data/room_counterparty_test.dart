import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/room_counterparty.dart';

/// S3-E §7: 상대 id 는 room participant 데이터에서만 도출한다.
/// (메시지 작성자 추정·화면 문자열 파싱·닉네임 조회·하드코딩 금지)
Room _room({String student = 'student-1', String mentor = 'mentor-1'}) {
  final DateTime now = DateTime(2026, 8, 1);
  return Room(
    id: 'room-1',
    studentId: student,
    mentorId: mentor,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('학생이 열면 상대는 멘토', () {
    final RoomCounterparty? cp = RoomCounterparty.of(
      _room(),
      currentUid: 'student-1',
      displayName: '김선생',
    );
    expect(cp, isNotNull);
    expect(cp!.userId, 'mentor-1');
    expect(cp.displayName, '김선생');
  });

  test('멘토가 열면 상대는 학생', () {
    final RoomCounterparty? cp = RoomCounterparty.of(
      _room(),
      currentUid: 'mentor-1',
      displayName: '박학생',
    );
    expect(cp!.userId, 'student-1');
    expect(cp.displayName, '박학생');
  });

  test('상대는 절대 현재 사용자와 같지 않다(자기 신고·차단 불가)', () {
    for (final String uid in <String>['student-1', 'mentor-1']) {
      final RoomCounterparty? cp =
          RoomCounterparty.of(_room(), currentUid: uid, displayName: '상대');
      expect(cp!.userId, isNot(uid));
    }
  });

  test('학생·멘토가 동일 id 인 퇴화 방이면 null(자기 자신 방어)', () {
    final RoomCounterparty? cp = RoomCounterparty.of(
      _room(student: 'same', mentor: 'same'),
      currentUid: 'same',
      displayName: '나',
    );
    expect(cp, isNull);
  });

  test('방 정보 없음 / 세션 없음 / 당사자 아님 → null(안전 메뉴 비활성화)', () {
    expect(RoomCounterparty.of(null, currentUid: 'student-1', displayName: 'x'),
        isNull);
    expect(
        RoomCounterparty.of(_room(), currentUid: null, displayName: 'x'), isNull);
    expect(RoomCounterparty.of(_room(), currentUid: '', displayName: 'x'),
        isNull);
    expect(
        RoomCounterparty.of(_room(), currentUid: '제3자', displayName: 'x'), isNull);
  });

  test('표시명이 비면 raw id 대신 중립 표기로 폴백(UUID 비노출)', () {
    final RoomCounterparty? cp = RoomCounterparty.of(
      _room(),
      currentUid: 'student-1',
      displayName: '   ',
    );
    expect(cp!.displayName, '상대방');
    expect(cp.displayName.contains('mentor-1'), isFalse);
  });
}
