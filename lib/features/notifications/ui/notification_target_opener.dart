import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../app/app_scope.dart';
import '../../../core/auth/auth_service.dart' show AppRole;
import '../../../core/deeplink/notification_deep_link_controller.dart';
import '../../community/data/community_models.dart';
import '../../community/data/community_read_repository.dart';
import '../../community/data/community_write_repository.dart';
import '../../community/ui/board/board_detail_screen.dart';
import '../../community/ui/shortform/shortform_detail_screen.dart';
import '../../individual_question/data/individual_question_repository.dart';
import '../../individual_question/data/models/individual_question_models.dart';
import '../../individual_question/ui/iq_detail_screen.dart';
import '../../mentors/data/mentor_directory_repository.dart';
import '../../mentors/data/mentor_models.dart';
import '../../mentors/ui/mentor_detail_screen.dart';
import '../../question_room/data/models/question_thread.dart';
import '../../question_room/data/models/room.dart';
import '../../question_room/data/question_room_read_repository.dart';
import '../../question_room/data/student_lookup_repository.dart';
import '../../question_room/ui/chat_screen.dart';
import '../../question_room/ui/mentor/mentor_answer_screen.dart';
import '../../question_room/ui/mentor/student_room_home_screen.dart';
import '../../question_room/ui/mentor_room_home_screen.dart';

/// 알림 상세 목적지 열기 — 검증된 route([NotificationDeepLinkRoute])만 받아
/// 기존 상세 화면 push 로 연다(새 라우팅 체계 없음 — 다른 화면과 같은
/// Navigator.push 경로).
///
/// 반환 false = 대상 소실/권한 밖/역할 불일치 — 호출부(알림 화면)가 중립
/// 폴백(스낵바 + 목록 유지)으로 안내한다. 조회 실패도 false(성공 위장 금지).
/// ★ 자유 link/url 필드는 route 모델에 존재하지 않는다 — 실행 경로 없음.
class NotificationTargetOpener {
  const NotificationTargetOpener();

  Future<bool> open(
      BuildContext context, NotificationDeepLinkRoute route) async {
    try {
      switch (route) {
        case NotificationTabRoute():
          return false; // 탭 이동은 호출부(TabNavigator) 담당 — 여기 오지 않는다.
        case NotificationRoomRoute():
          return _openRoom(context, route);
        case NotificationIqRoute(:final String questionId):
          return _openIq(context, questionId);
        case NotificationBoardPostRoute(:final String postId):
          return _openBoardPost(context, postId);
        case NotificationShortformRoute(:final String shortformId):
          return _openShortform(context, shortformId);
        case NotificationMentorRoute(:final String mentorId):
          return _openMentor(context, mentorId);
      }
    } catch (_) {
      return false; // 조회 실패 — 중립 폴백(원문 비노출).
    }
  }

  /// 질문방 — 역할별 화면으로 연다(학생=기존 계약, 멘토=답변 화면/학생방 홈).
  /// roomId 가 없으면 threadId 로 방을 역추적한다. 그 외 역할(관리자·게스트)은
  /// 폴백. 과거엔 멘토를 무조건 폴백시켜 질문방 계열 알림 탭이 막혔다 —
  /// 웹 딥링크(role=mentor → /mentor/question-room/…)와 동일하게 교정.
  Future<bool> _openRoom(
      BuildContext context, NotificationRoomRoute route) async {
    // A-2: 역할·질문방 읽기 레포는 AppScope 에서(싱글턴·직접 생성 0).
    final AppDependencies deps = AppScope.of(context);
    final AppRole role = deps.auth.currentRole;
    if (role != AppRole.student && role != AppRole.mentor) return false;
    final QuestionRoomReadRepository rooms = deps.questionRoomRead;

    QuestionThread? thread;
    String? roomId = route.roomId;
    if (route.threadId != null) {
      thread = await rooms.threadById(route.threadId!);
      roomId ??= thread?.roomId;
      // 스레드가 다른 방을 가리키면 자기모순 payload — 열지 않는다.
      if (thread != null && roomId != null && thread.roomId != roomId) {
        return false;
      }
    }
    if (roomId == null) return false;

    // N16: 대상 방 1건만 조회(RLS: 당사자만 통과 — 권한 밖이면 null).
    // 종전에는 내 방 전량(myRooms)을 받아 클라이언트에서 찾았다.
    final Room? room = await rooms.roomById(roomId);
    if (room == null) return false;

    // 클로저 캡처용 지역 확정값(널 승격을 클로저 안까지 보장).
    final Room targetRoom = room;
    final QuestionThread? targetThread = thread;

    if (role == AppRole.mentor) {
      // 멘토 — 상대(학생) 이름 조회 후 해당 질문 답변 화면/학생방 홈으로.
      String studentName = '학생';
      try {
        final Map<String, StudentPublic> students =
            await deps.studentLookup.fetchMany(<String>[targetRoom.studentId]);
        studentName = students[targetRoom.studentId]?.displayName ?? '학생';
      } catch (_) {
        // 이름 조회 실패는 중립 표시로 계속 진행.
      }
      if (!context.mounted) return false;
      final String sName = studentName;
      if (targetThread != null) {
        await AppNavigation.push<void>(
          context,
          AppRoutePaths.roomThread(targetRoom.id, targetThread.id),
          fallbackBuilder: (_) => MentorAnswerScreen(
            thread: targetThread,
            studentName: sName,
            room: targetRoom,
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                StudentRoomHomeScreen(room: targetRoom, studentName: sName),
          ),
        );
      }
      return true;
    }

    String mentorName = '멘토';
    try {
      mentorName =
          (await deps.mentorLookup.fetch(room.mentorId))?.displayName ?? '멘토';
    } catch (_) {
      // 이름 조회 실패는 중립 표시로 계속 진행.
    }

    if (!context.mounted) return false;
    final String name = mentorName;
    if (targetThread != null) {
      await AppNavigation.push<void>(
        context,
        AppRoutePaths.roomThread(targetRoom.id, targetThread.id),
        fallbackBuilder: (_) => ChatScreen(
          thread: targetThread,
          mentorName: name,
          room: targetRoom,
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MentorRoomHomeScreen(room: targetRoom, mentorName: name),
        ),
      );
    }
    return true;
  }

  Future<bool> _openIq(BuildContext context, String questionId) async {
    // 사전 조회(당사자 RLS) — 없거나 권한 밖이면 중립 폴백.
    final IndividualQuestion? q =
        await const IndividualQuestionRepository().fetch(questionId);
    if (q == null || !context.mounted) return false;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => IqDetailScreen(questionId: questionId),
      ),
    );
    return true;
  }

  Future<bool> _openBoardPost(BuildContext context, String postId) async {
    const CommunityReadRepository read = CommunityReadRepository();
    final BoardPost? post = await read.boardPostById(postId);
    if (post == null || !context.mounted) return false;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BoardDetailScreen(
          post: post,
          read: read,
          write: const CommunityWriteRepository(),
        ),
      ),
    );
    return true;
  }

  Future<bool> _openShortform(BuildContext context, String shortformId) async {
    const CommunityReadRepository read = CommunityReadRepository();
    final ShortformPost? post = await read.shortformById(shortformId);
    if (post == null || !context.mounted) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ShortformDetailScreen(
          post: post,
          read: read,
          write: const CommunityWriteRepository(),
        ),
      ),
    );
    return true;
  }

  Future<bool> _openMentor(BuildContext context, String mentorId) async {
    final MentorListItem? item =
        await const MentorDirectoryRepository().fetchListItemById(mentorId);
    if (item == null || !context.mounted) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MentorDetailScreen(item: item),
      ),
    );
    return true;
  }
}
