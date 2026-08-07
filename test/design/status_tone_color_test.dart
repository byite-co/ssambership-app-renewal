import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/design/theme.dart';
import 'package:ssambership_app/design/tokens/color_tokens.dart';
import 'package:ssambership_app/design/role_accent.dart';
import 'package:ssambership_app/design/widgets/count_badge.dart';
import 'package:ssambership_app/design/widgets/status_pill.dart';

/// [QA-C4] 멘토 화면에서 '진행 중'(info)과 '답변 완료'(success)가 둘 다 초록으로
/// 보여 구분되지 않았다. 상태색은 역할이 아니라 상태를 말해야 한다.
///
/// 액션 CTA 가 이미 역할 무관 파랑으로 수렴한 것과 같은 방향이다
/// (test/design/action_button_color_test.dart). AppAccent 자체는 그대로 둔다.
void main() {
  Future<Map<StatusTone, Color>> tonesFor(WidgetTester tester, AppRole role) async {
    final Map<StatusTone, Color> out = <StatusTone, Color>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(role),
        home: Builder(
          builder: (BuildContext context) {
            for (final StatusTone t in StatusTone.values) {
              out[t] = statusToneColor(context, t);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return out;
  }

  testWidgets('info 와 success 는 어떤 역할에서도 같은 색이 아니다', (WidgetTester tester) async {
    for (final AppRole role in <AppRole>[AppRole.student, AppRole.mentor]) {
      final Map<StatusTone, Color> tones = await tonesFor(tester, role);
      expect(
        tones[StatusTone.info],
        isNot(tones[StatusTone.success]),
        reason: '$role 에서 진행 중과 답변 완료가 같은 색이면 상태를 구분할 수 없다',
      );
    }
  });

  testWidgets('상태색은 역할에 따라 달라지지 않는다', (WidgetTester tester) async {
    final Map<StatusTone, Color> student = await tonesFor(tester, AppRole.student);
    final Map<StatusTone, Color> mentor = await tonesFor(tester, AppRole.mentor);
    expect(student, equals(mentor));
  });

  testWidgets('info 는 고정 파랑 · success 는 웹 상태색 그대로', (WidgetTester tester) async {
    final Map<StatusTone, Color> tones = await tonesFor(tester, AppRole.mentor);
    expect(tones[StatusTone.info], ColorTokens.accent);
    expect(tones[StatusTone.success], ColorTokens.success);
  });

  // [적대적 검증] 상태칩 info 를 역할 무관 파랑으로 고정하면서 개수 배지까지
  // 파래지면 과한 변경이다 — 개수 배지는 상태가 아니라 정체성 장식에 가깝다.
  testWidgets('CountBadge 기본색은 역할 강조색을 유지한다(멘토 초록)',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(AppRole.mentor),
      home: const Scaffold(body: Center(child: CountBadge(count: 3))),
    ));
    final Container box = tester.widget<Container>(find.descendant(
      of: find.byType(CountBadge),
      matching: find.byType(Container),
    ));
    final BoxDecoration d = box.decoration! as BoxDecoration;
    expect(d.color, RoleAccent.mentor.accent);
    expect(d.color, isNot(ColorTokens.accent));
  });

  testWidgets('CountBadge 에 tone 을 주면 그 상태색을 쓴다', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(AppRole.mentor),
      home: const Scaffold(
        body: Center(child: CountBadge(count: 3, tone: StatusTone.success)),
      ),
    ));
    final Container box = tester.widget<Container>(find.descendant(
      of: find.byType(CountBadge),
      matching: find.byType(Container),
    ));
    expect((box.decoration! as BoxDecoration).color, ColorTokens.success);
  });

  testWidgets('상태 5종이 서로 다른 색이다(중복 없음)', (WidgetTester tester) async {
    final Map<StatusTone, Color> tones = await tonesFor(tester, AppRole.mentor);
    final Set<int> values = tones.values.map((Color c) => c.toARGB32()).toSet();
    expect(values.length, StatusTone.values.length);
  });
}
