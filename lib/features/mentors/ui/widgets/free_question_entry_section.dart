import 'package:flutter/material.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/secondary_button.dart';
import '../../../../shared/errors/friendly_error.dart';
import '../../data/free_question_entry.dart';
import '../free_question_compose_screen.dart';

/// 멘토 상세의 무료 질문 진입 섹션(세션1 §3 · S2-2 M17 전환).
///
/// - 학생에게만 노출(멘토·게스트·관리자 hidden), 구독자는 기존 질문방 진입 유지.
/// - 자격 '조회' 성공 시 CTA 활성 — 수량·기간 판정은 서버(F2/F3)가 하고,
///   오류 코드는 한글로 안내한다.
/// - 조회 실패: 재시도 제공, 재시도 성공 전 생성 RPC 0회.
/// - 방 확보: 질문 시작 시 F2(`api_app_v1.ensure_free_question_room`)가 원자
///   확보(기존 방 재사용 포함) — 무료질문권은 소비하지 않는다(F3 소관).
/// - 캐시 차감형 개별질문 CTA(개별질문 하기)와 handler·RPC·상태 공유 금지.
class FreeQuestionEntrySection extends StatefulWidget {
  const FreeQuestionEntrySection({
    super.key,
    required this.mentorId,
    required this.mentorName,
    required this.alreadySubscribed,
    this.port = const SupabaseFreeQuestionEntryRepository(),
    this.isStudentOverride,
    this.onCreated,
  });

  final String mentorId;
  final String mentorName;

  /// 멘토 상세 extras 의 구독 여부(null=미확정 — 활성 CTA 0).
  final bool? alreadySubscribed;

  final FreeQuestionEntryPort port;

  /// 테스트 주입(기본: AuthService.currentRole == student).
  final bool? isStudentOverride;

  /// 생성 성공 콜백 — 호출부(멘토 상세)가 기존 질문방 이동·재조회를 수행.
  final ValueChanged<CreatedFreeQuestion>? onCreated;

  @override
  State<FreeQuestionEntrySection> createState() =>
      _FreeQuestionEntrySectionState();
}

class _FreeQuestionEntrySectionState extends State<FreeQuestionEntrySection> {
  FreeQuestionEntrySnapshot? _snapshot;
  bool _loading = false;
  bool _failed = false;
  bool _creating = false;

  bool get _isStudent =>
      widget.isStudentOverride ??
      (AuthService.instance.currentRole == AppRole.student);

  @override
  void initState() {
    super.initState();
    // 학생 + 비구독 확정일 때만 조회(그 외엔 조회 자체가 불필요).
    if (_isStudent && widget.alreadySubscribed == false) {
      _fetch();
    }
  }

  @override
  void didUpdateWidget(covariant FreeQuestionEntrySection old) {
    super.didUpdateWidget(old);
    // 구독 여부가 뒤늦게 '비구독 확정'으로 도착하면 그때 최초 조회를 시작한다.
    if (_isStudent &&
        widget.alreadySubscribed == false &&
        old.alreadySubscribed != false &&
        _snapshot == null &&
        !_loading) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final FreeQuestionEntrySnapshot s =
          await widget.port.fetch(widget.mentorId);
      if (!mounted) return;
      setState(() {
        _snapshot = s;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // 조회 실패 = '사용 가능' 추정 금지(fail-closed) — 재시도 전 CTA 비활성.
        _snapshot = null;
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _open() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      // F2 — 방 원자 확보(없으면 생성·있으면 재사용, created 플래그는 서버
      // 정본). 실패 코드는 한글 매핑으로 안내하고 compose 로 진입하지 않는다.
      final EnsuredQuestionRoom room;
      try {
        room = await widget.port.ensureRoom(widget.mentorId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e))),
          );
        }
        return;
      }
      if (!mounted) return;
      final CreatedFreeQuestion? created =
          await Navigator.of(context).push<CreatedFreeQuestion>(
        MaterialPageRoute<CreatedFreeQuestion>(
          builder: (_) => FreeQuestionComposeScreen(
            roomId: room.roomId,
            mentorName: widget.mentorName,
            port: widget.port,
          ),
        ),
      );
      if (!mounted) return;
      if (created != null) {
        // 성공 후 자격 사실값 재조회(멘토 상세 갱신 요건).
        await _fetch();
        if (!mounted) return;
        widget.onCreated?.call(created);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final FreeQuestionCtaStatus status = decideFreeQuestionCta(
      isStudent: _isStudent,
      alreadySubscribed: widget.alreadySubscribed,
      loading: _loading,
      fetchFailed: _failed,
      snapshot: _snapshot,
    );
    switch (status) {
      case FreeQuestionCtaStatus.hidden:
        return const SizedBox.shrink();
      case FreeQuestionCtaStatus.loading:
        return const Padding(
          padding: EdgeInsets.only(top: 10),
          child: SecondaryButton(
            label: '무료 질문하기',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: null, // 조회 전 활성화 금지.
          ),
        );
      case FreeQuestionCtaStatus.unavailable:
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('무료 질문 가능 여부를 확인하지 못했어요.',
                  style:
                      AppType.caption.copyWith(color: ColorTokens.secondary)),
              const SizedBox(height: 6),
              SecondaryButton(
                label: '다시 시도',
                icon: Icons.refresh_rounded,
                onPressed: _fetch,
              ),
            ],
          ),
        );
      case FreeQuestionCtaStatus.ready:
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SecondaryButton(
            label: '무료 질문하기',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: _creating ? null : _open,
          ),
        );
    }
  }
}
