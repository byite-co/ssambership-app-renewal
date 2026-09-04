import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/auth/auth_service.dart' show AppRole;
import '../../design/widgets/empty_state.dart';
import 'iq_flags.dart';
import 'ui/mentor_iq_list_screen.dart';
import 'ui/student_iq_list_screen.dart';

/// 하단 탭 '개별질문' — 질문방·커뮤니티 등과 동일 위상의 1급 기능.
///
/// HomeShell 이 AppBar/하단탭을 제공하므로 본문만 그린다(자체 Scaffold 없음).
/// role(student/mentor)에 따라 기존 목록 화면을 embedded 모드로 분기한다
/// — 목록 로직을 재구현하지 않고 그대로 재사용(마이페이지 진입 시절과 동일 화면).
class IndividualQuestionTabScreen extends StatelessWidget {
  const IndividualQuestionTabScreen({super.key, this.isMentorOverride});

  /// 테스트용 role 오버라이드. null 이면 AuthService 의 현재 role 을 쓴다.
  final bool? isMentorOverride;

  @override
  Widget build(BuildContext context) {
    // 기능 스위치가 꺼져 있으면 빈 안내(탭 자체는 유지 — 라벨/인덱스 불변).
    if (!kIndividualQuestionEnabled) {
      return const EmptyState(
        icon: Icons.question_answer_rounded,
        title: '개별질문 준비 중이에요',
        message: '곧 이곳에서 1건씩 질문할 수 있어요.',
      );
    }
    final bool isMentor = isMentorOverride ??
        (AppScope.of(context).auth.currentRole == AppRole.mentor); // A-2
    return isMentor
        ? const MentorIqListScreen(embedded: true)
        : const StudentIqListScreen(embedded: true);
  }
}
