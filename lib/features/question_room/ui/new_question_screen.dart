import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/entitlement/weekly_question_usage.dart';
import '../../../data/mappings/subject_labels.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_blocks.dart';
import '../../../design/widgets/app_input_field.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/chip_scroll.dart';
import '../../../shared/errors/friendly_error.dart';
import '../data/models/question_thread.dart';
import '../data/models/room.dart';
import '../data/question_room_read_repository.dart';
import '../data/question_room_write_repository.dart';

/// 새 질문 작성(design-v3 §3-3). 제목·과목(선택)·내용 → 서버 원자 생성 RPC 한 번(P1-8).
/// 활성 구독·잔여>0 확인은 호출부(질문영역)에서 게이팅하지만, 실패 에러는 그대로 노출한다.
///
/// 사진은 질문이 만들어진 뒤 대화 화면에서 붙인다(생성 RPC 는 첨부를 받지 않는다) —
/// 첨부 직후 1회 펜 안내는 그 입력 바([ChatInputBar])에 있다.
class NewQuestionScreen extends StatefulWidget {
  const NewQuestionScreen({
    super.key,
    required this.room,
    this.readRepository,
    this.writeRepository,
  });

  final Room room;

  /// 테스트 주입 지점. null 이면 AppScope의 운영 레포를 사용.
  final QuestionRoomReadRepository? readRepository;
  final QuestionRoomWriteRepository? writeRepository;

  @override
  State<NewQuestionScreen> createState() => _NewQuestionScreenState();
}

class _NewQuestionScreenState extends State<NewQuestionScreen> {
  late final QuestionRoomWriteRepository _write;
  late final QuestionRoomReadRepository _read;
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  String? _subjectCode; // null = 선택 안 함

  /// 방 멘토의 담당 과목 코드. null = 로딩 전(칩 잠금), 로드 후 후보 제한 근거.
  List<String>? _mentorCodes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read = widget.readRepository ?? AppScope.of(context).questionRoomRead;
    _write = widget.writeRepository ?? AppScope.of(context).questionRoomWrite;
    _loadMentorSubjects();
  }

  /// 방 멘토(teaching_subjects)를 읽어 과목 후보를 그 멘토 담당 과목만으로 제한한다(A1).
  /// 조회 실패/미지정이면 빈 리스트 → 후보는 전체 정본 과목으로 폴백한다
  /// (restrictQuestionSubjectCodes — 웹과 동일, '선택 안 함'만 남기지 않는다).
  Future<void> _loadMentorSubjects() async {
    final List<String> codes =
        await _read.mentorTeachingSubjects(widget.room.mentorId);
    if (!mounted) return;
    setState(() => _mentorCodes = codes);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String titleInput = _title.text.trim();
    final String body = _body.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      // A2: 제출 '직전' 주간한도 검사(읽기전용 RPC) — UX 사전검사일 뿐이고
      // 최종 판정은 생성 RPC(서버 트랜잭션)가 한다.
      // ★ fail-closed(P2-13): 조회 실패(usage==null)=판정 불가면 제출을 막고
      //   재시도를 안내한다(과거 fail-open 제거).
      final WeeklyQuestionUsage? usage =
          await _read.weeklyUsage(mentorId: widget.room.mentorId);
      if (usage == null) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('질문 가능 여부를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.')),
          );
        }
        return;
      }
      if (!usage.canAsk) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(usage.blockMessage)),
          );
        }
        return;
      }
      // 제목 미입력 → 방의 질문 순번으로 자동 제목("{N}번 질문", N=기존 질문 수+1).
      // 순번 계산에 방의 스레드 수를 1회 조회한다(미입력일 때만). '(제목 없음)' 폴백 대신 저장.
      String title = titleInput;
      if (title.isEmpty) {
        // N23: 순번 계산에 전 행(select *) 대신 서버 count 1회.
        final int existing = await _read.threadCount(widget.room.id);
        title = autoQuestionTitle(existing);
      }
      // P1-8: 생성은 서버 원자 RPC 한 번 — thread+첫 메시지+사용량 소비가 한 트랜잭션.
      // 실패하면 빈 thread/로컬 성공 상태가 남지 않는다(별도 append 호출 없음).
      await _write.createThread(
        roomId: widget.room.id,
        title: title,
        subject: _subjectCode,
        firstMessageBody: body,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('질문 등록에 실패했어요. ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '새 질문',
      body: ListView(
        clipBehavior: Clip.none,
        padding: AppPage.contentPadding(context),
        children: <Widget>[
          AppField(
            label: '제목 (선택)',
            child: AppInputField(
              controller: _title,
              hintText: '한 줄 제목',
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          AppField(
            label: '어떤 과목인가요?',
            child: _subjectPicker(),
          ),
          const SizedBox(height: AppSpacing.s20),
          AppField(
            label: '무엇이 궁금한가요?',
            child: AppInputField(
              controller: _body,
              hintText: '어디까지 풀었는지 함께 적으면 답변이 훨씬 정확해져요',
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ],
      ),
      bottom: AppPrimaryButton(
        label: _busy ? '보내는 중…' : '질문 보내기',
        onPressed: _busy ? null : _submit,
      ),
    );
  }

  /// 과목 칩 — 로딩 전(_mentorCodes==null)에는 잠가 두어, 로드 후 후보에서 빠질
  /// 값이 미리 선택되는 문제를 막는다. 로드되면 정규화된 멘토 담당 과목만 노출하고,
  /// 담당 과목이 없거나 조회·정규화 결과가 비면 전체 정본 과목으로 폴백한다
  /// (restrictQuestionSubjectCodes — 빈 목록으로 '선택 안 함'만 남기지 않는다).
  /// 후보는 전부 정본 code 라 화면엔 한글 라벨, 전송엔 code 또는 null 만 나간다.
  Widget _subjectPicker() {
    final List<String>? mentorCodes = _mentorCodes;
    if (mentorCodes == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('과목 불러오는 중…', style: AppTypography.captionSecondary),
      );
    }
    final List<String> codes = restrictQuestionSubjectCodes(mentorCodes);
    final List<String?> values = <String?>[null, ...codes];
    final int selected = values.indexOf(_subjectCode);
    return ChipScroll(
      padding: EdgeInsets.zero,
      labels: <String>[
        '선택 안 함',
        for (final String code in codes) subjectLabel(code),
      ],
      selectedIndex: selected < 0 ? 0 : selected,
      onSelected: (int i) => setState(() => _subjectCode = values[i]),
    );
  }
}
