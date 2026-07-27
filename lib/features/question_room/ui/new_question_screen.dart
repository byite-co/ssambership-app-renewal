import 'package:flutter/material.dart';

import '../../../core/entitlement/weekly_question_usage.dart';
import '../../../data/mappings/subject_labels.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/shape_tokens.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/primary_button.dart';
import '../data/models/question_thread.dart';
import '../data/models/room.dart';
import '../data/question_room_read_repository.dart';
import '../data/question_room_write_repository.dart';
import '../../../shared/errors/friendly_error.dart';

/// 새 질문 작성. 제목·내용·과목(선택) → 서버 원자 생성 RPC 한 번(P1-8).
/// 활성 구독·잔여>0 확인은 호출부(질문영역)에서 게이팅하지만, 실패 에러는 그대로 노출한다.
class NewQuestionScreen extends StatefulWidget {
  const NewQuestionScreen({
    super.key,
    required this.room,
    this.readRepository = const QuestionRoomReadRepository(),
    this.writeRepository = const QuestionRoomWriteRepository(),
  });

  final Room room;

  /// 테스트 주입 지점(기본: 운영 레포).
  final QuestionRoomReadRepository readRepository;
  final QuestionRoomWriteRepository writeRepository;

  @override
  State<NewQuestionScreen> createState() => _NewQuestionScreenState();
}

class _NewQuestionScreenState extends State<NewQuestionScreen> {
  QuestionRoomWriteRepository get _write => widget.writeRepository;
  QuestionRoomReadRepository get _read => widget.readRepository;
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  String? _subjectCode; // null = 선택 안 함

  /// 방 멘토의 담당 과목 코드. null = 로딩 전(드롭다운 잠금), 로드 후 후보 제한 근거.
  List<String>? _mentorCodes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadMentorSubjects();
  }

  /// 방 멘토(teaching_subjects)를 읽어 과목 후보를 그 멘토 담당 과목만으로 제한한다(A1).
  /// 조회 실패/미지정이면 후보가 비어 '선택 안 함'만 남는다(전체 과목을 뿌리지 않음).
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
      final WeeklyQuestionUsage? usage = await _read.weeklyUsage(
        studentId: widget.room.studentId,
        mentorId: widget.room.mentorId,
      );
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
        final int existing = (await _read.threads(widget.room.id)).length;
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
    return Scaffold(
      appBar: AppBar(title: const Text('새 질문')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH, vertical: AppSpacing.s16),
        children: <Widget>[
          Text('제목 (선택)', style: AppType.caption),
          const SizedBox(height: AppSpacing.titleBody),
          TextField(
            controller: _title,
            style: AppType.body,
            decoration: _decoration('한 줄 제목'),
          ),
          const SizedBox(height: AppSpacing.s16),
          Text('과목 (선택)', style: AppType.caption),
          const SizedBox(height: AppSpacing.titleBody),
          _subjectPicker(),
          const SizedBox(height: AppSpacing.s16),
          Text('질문 내용', style: AppType.caption),
          const SizedBox(height: AppSpacing.titleBody),
          TextField(
            controller: _body,
            style: AppType.body,
            minLines: 5,
            maxLines: 10,
            decoration: _decoration('궁금한 점을 적어주세요.'),
          ),
          const SizedBox(height: AppSpacing.s24),
          PrimaryButton(
            label: _busy ? '등록 중…' : '질문 등록',
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _subjectPicker() {
    // 로딩 전(_mentorCodes==null)에는 잠가 두어, 로드 후 후보에서 빠질 값이
    // 미리 선택되는 문제를 막는다. 로드되면 '해당 멘토 담당 과목만' 노출(전체 폴백 없음).
    final bool loaded = _mentorCodes != null;
    final List<String> codes =
        loaded ? mentorSubjectCodesStrict(_mentorCodes!) : const <String>[];
    final List<DropdownMenuItem<String?>> items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('선택 안 함')),
      for (final String code in codes)
        DropdownMenuItem<String?>(value: code, child: Text(subjectLabel(code))),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        borderRadius: AppShape.inputRadius,
        border: Border.all(color: ColorTokens.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: _subjectCode,
          dropdownColor: ColorTokens.surface,
          style: AppType.body,
          hint: Text(loaded ? '선택 안 함' : '과목 불러오는 중…', style: AppType.body),
          items: items,
          // 로딩 중에는 비활성(onChanged=null) — 로드 후 제한된 후보로만 선택.
          onChanged:
              loaded ? (String? v) => setState(() => _subjectCode = v) : null,
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: ColorTokens.elevated,
      border: OutlineInputBorder(
        borderRadius: AppShape.inputRadius,
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
