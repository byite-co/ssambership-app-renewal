import 'package:flutter/material.dart';
import '../../../design/widgets/glass_inner.dart';
import '../../../design/role_theme.dart';
import '../../../data/mappings/subject_labels.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../core/ink/ink_document.dart';
import '../../../core/refresh/data_refresh_bus.dart';
import '../../../core/scan/image_downscaler.dart';
import '../../../core/scan/pdf_rasterizer.dart';
import '../../../core/scan/picked_image.dart';
import '../../../core/scan/scan_source_picker.dart';
import '../../../core/scan/widgets/scan_pick_expander.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_input_field.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_blocks.dart';
import '../../question_room/data/attachments/attachment_upload.dart'
    show ImagePickerPort, validatePickedImage;
import '../../question_room/data/attachments/device_image_picker.dart';
import '../../question_room/ui/widgets/scan_source_sheet.dart';
import '../../scan_annotation/annotation_target.dart';
import '../../scan_annotation/scan_annotation_screen.dart';
import '../data/individual_question_repository.dart';
import '../data/iq_attachments_repository.dart';
import '../data/iq_error_mapper.dart';
import '../data/models/individual_question_models.dart';

/// 작성 화면 사전 정보(잔액 + 지정형 가격).
class IqCreatePrefill {
  const IqCreatePrefill({required this.balanceCents, this.pricing});

  final int balanceCents;

  /// 지정형일 때 멘토 가격. 미설정이면 null(작성 불가 안내).
  final IqPricing? pricing;
}

/// 새 개별질문 작성 — 캐시 예치(에스크로). A-4a #11 로 네이티브 개방(`/iq/new`).
/// [mentorId] 가 있으면 지정형(가격은 멘토 가격표에서 서버가 결정),
/// 없으면 공개형(금액 자유 입력 — 웹과 동일하게 최소/최대 강제 없음).
///
/// ★ Commerce-Zero 유지: 잔액 부족은 "잔액이 부족해요" 사실 안내 + 등록 버튼
///   비활성까지만. 충전 버튼·링크·인앱 브라우저 0. 성공 시 생성된 질문을 pop
///   결과로 돌려주고, 호출 화면이 상세로 이어간다.
class IqCreateScreen extends StatefulWidget {
  const IqCreateScreen({
    super.key,
    this.mentorId,
    this.mentorName,
    this.prefillOverride,
    this.submitOverride,
    this.scanPicker = const DeviceScanSourcePicker(),
    this.galleryPicker = const DeviceImagePicker(),
    this.pdfRasterizer = const PdfxRasterizer(),
    this.attachments,
    this.annotateOverride,
    this.submitWithSubjectOverride,
  });

  final String? mentorId;
  final String? mentorName;

  /// 테스트용 사전 정보 주입. null 이면 실제 레포 사용.
  final Future<IqCreatePrefill> Function()? prefillOverride;

  /// 테스트용 제출 동작 주입. null 이면 실제 RPC.
  final Future<IndividualQuestion> Function({
    required IndividualQuestionType type,
    required String title,
    required String body,
    int? amountCents,
    String? designatedMentorId,
    String? idempotencyKey,
  })? submitOverride;

  /// A-4b ⑧ 테스트용 등록 함수(과목 포함) — 있으면 [submitOverride] 보다 우선.
  /// 기존 테스트의 6인자 [submitOverride] 는 그대로 둔다(동작 테스트 무수정).
  final Future<IndividualQuestion> Function({
    required IndividualQuestionType type,
    required String title,
    required String body,
    int? amountCents,
    String? designatedMentorId,
    String? idempotencyKey,
    String? subject,
  })? submitWithSubjectOverride;

  /// 스캔 소스 포트(S16 시트의 촬영·파일). 테스트에서 fake 주입.
  final ScanSourcePort scanPicker;

  /// 갤러리 포트(하위호환 주입 지점).
  final ImagePickerPort galleryPicker;

  /// PDF 래스터라이저 포트(S19: 파일 소스 PDF → 페이지 선택). fake 주입 지점.
  final PdfRasterizerPort pdfRasterizer;

  /// 첨부 업로드 포트(S17: 버킷 업로드 + RPC 행 등록). 테스트 override가
  /// 없으면 AppScope의 운영 의존성을 사용한다.
  final IqAttachmentsPort? attachments;

  /// 테스트용 필기 화면 진입 오버라이드(S18). null 이면 실제
  /// [ScanAnnotationScreen] push. 인자는 (배경 원본, 기존 스트로크).
  final Future<AnnotationResult?> Function(
    PickedImage background,
    InkDocument? initial,
  )? annotateOverride;

  bool get isDirect => mentorId != null;

  /// A-4b ⑧ 과목 후보 — `subjects.code` 정본과 같은 앱 상수 집합(대분류 순).
  static List<String> get subjectCodes => subjectCatalogEntries
      .map((SubjectCatalogEntry e) => e.code)
      .toList(growable: false);

  @override
  State<IqCreateScreen> createState() => _IqCreateScreenState();
}

class _IqCreateScreenState extends State<IqCreateScreen> {
  /// A-4b ⑧ 선택한 과목 코드(null = 미선택). 공개형은 필수, 지정형은 선택.
  String? _subjectCode;

  IndividualQuestionRepository get _repo =>
      AppScope.of(context).individualQuestions;
  IqAttachmentsPort get _attachments =>
      widget.attachments ?? AppScope.of(context).iqAttachments;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  late Future<IqCreatePrefill> _future;
  bool _submitting = false;

  /// 첨부 대기 이미지(최대 5장, §6-1). 제출 성공 후엔 '업로드 실패분'만 남는다.
  final List<PickedImage> _images = <PickedImage>[];

  /// 슬롯별 로컬 첨삭 상태(S18) — [_images] 와 같은 인덱스로 함께 증감한다.
  /// 필기 완료 시 평탄화본이 [_images] 의 슬롯을 '대체'하지만, 화면 생존 동안
  /// 원본 배경과 스트로크는 여기 보관해 이어 그리기(재편집)를 지원한다(§3).
  final List<_DraftInk?> _inks = <_DraftInk?>[];

  /// 질문 생성 RPC 성공 후의 질문(부분 실패 재시도 기준).
  /// null 아님 = 질문(텍스트)은 이미 등록됨 — 재제출 금지, 첨부 재시도만.
  IndividualQuestion? _created;

  static const int _maxImages = 5;

  @override
  void initState() {
    super.initState();
    _future = _loadPrefill();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<IqCreatePrefill> _loadPrefill() async {
    if (widget.prefillOverride != null) return widget.prefillOverride!();
    final int balance = await _repo.fetchWalletBalanceCents();
    IqPricing? pricing;
    if (widget.isDirect) {
      pricing = await _repo.fetchMentorPricing(widget.mentorId!);
    }
    return IqCreatePrefill(balanceCents: balance, pricing: pricing);
  }

  void _retryPrefill() {
    setState(() {
      _future = _loadPrefill();
    });
  }

  /// 공개형 입력 금액(캐시) → cents. 유효하지 않으면 null.
  int? get _openAmountCents {
    final int? cash = int.tryParse(_amountController.text.trim());
    if (cash == null || cash <= 0) return null;
    return cash * 100;
  }

  /// 첨부 추가 — S16 소스 시트(촬영/갤러리/파일) 재사용.
  /// PDF(S19)는 expandScanPick 이 페이지 선택 그리드로 확장한다 — 남은
  /// 첨부 슬롯 수를 상한으로 넘겨 페이지당 1장씩 붙는다(§6-1).
  Future<void> _addImage() async {
    if (_images.length >= _maxImages) {
      _snack('사진은 최대 $_maxImages장까지 첨부할 수 있어요.');
      return;
    }
    final ScanSource? source = await showScanSourceSheet(context);
    if (source == null || !mounted) return;
    try {
      final PickedImage? picked = source == ScanSource.gallery
          ? await widget.galleryPicker.pickImage()
          : await widget.scanPicker.pick(source);
      if (!mounted) return;
      final List<PickedImage> expanded = await expandScanPick(
        context,
        picked: picked,
        rasterizer: widget.pdfRasterizer,
        maxCount: _maxImages - _images.length, // 슬롯 연동 상한.
      );
      for (final PickedImage one in expanded) {
        final PickedImage img = await downscaleIfOversized(one);
        final String? invalid = validatePickedImage(img);
        if (invalid != null) {
          _snack(invalid);
          continue; // 한 장 불량이 나머지 페이지를 막지 않는다.
        }
        if (!mounted) return;
        setState(() {
          _images.add(img);
          _inks.add(null);
        });
      }
    } catch (e) {
      _snack(friendlyError(e)); // PDF 열기 실패 폴백 안내(AppError) 포함.
    }
  }

  void _removeImage(int index) => setState(() {
        _images.removeAt(index);
        _inks.removeAt(index);
      });

  /// '필기하기'(S18) — 전송 전 로컬 첨삭. 완료된 평탄화본이 해당 첨부를
  /// 대체한다(업로드 전 단계). 재진입 시 보관해 둔 원본+스트로크로 이어 그린다.
  Future<void> _annotateImage(int index) async {
    final _DraftInk? ink = _inks[index];
    final PickedImage background = ink?.original ?? _images[index];
    final AnnotationResult? result = await (widget.annotateOverride ??
        _pushAnnotationScreen)(background, ink?.document);
    if (result == null || !mounted) return;

    final int dot = background.fileName.lastIndexOf('.');
    final String base =
        dot <= 0 ? background.fileName : background.fileName.substring(0, dot);
    // 평탄화 PNG 도 일반 첨부와 같은 크기 규약(§6-4)을 통과시킨다.
    final PickedImage flattened = await downscaleIfOversized(PickedImage(
      bytes: result.flattenedPng,
      fileName: '$base-ink.png',
      mimeType: 'image/png',
    ));
    final String? invalid = validatePickedImage(flattened);
    if (invalid != null) {
      _snack(invalid);
      return;
    }
    if (!mounted) return;
    setState(() {
      _images[index] = flattened; // 원본 슬롯 대체(전송 전 로컬 단계).
      _inks[index] = _DraftInk(original: background, document: result.document);
    });
  }

  /// 실제 필기 화면 진입(테스트에서는 [IqCreateScreen.annotateOverride] 로 대체).
  Future<AnnotationResult?> _pushAnnotationScreen(
    PickedImage background,
    InkDocument? initial,
  ) async {
    final LocalAnnotationTarget target = LocalAnnotationTarget();
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ScanAnnotationScreen(
          background: background.bytes,
          initial: initial,
          target: target,
          title: '필기하기',
        ),
      ),
    );
    return done == true ? target.result : null;
  }

  /// 첨부 업로드 — 실패분은 [_images] 에 남겨 재시도 가능(작업물 유실 금지).
  /// 반환: 전부 성공 여부.
  Future<bool> _uploadImages(String questionId) async {
    final List<PickedImage> failed = <PickedImage>[];
    for (final PickedImage img in List<PickedImage>.of(_images)) {
      try {
        await _attachments.upload(questionId: questionId, image: img);
      } catch (_) {
        failed.add(img);
      }
    }
    if (!mounted) return failed.isEmpty;
    setState(() {
      _images
        ..clear()
        ..addAll(failed);
      // 제출 후에는 잠금 상태(재시도만)라 첨삭 상태는 더 쓰지 않는다 — 길이만 정합.
      _inks
        ..clear()
        ..addAll(List<_DraftInk?>.filled(failed.length, null));
    });
    return failed.isEmpty;
  }

  /// 부분 실패 후 재시도(질문은 이미 등록됨 — 재생성 없음).
  Future<void> _retryUpload() async {
    final IndividualQuestion? q = _created;
    if (q == null || _submitting) return;
    setState(() => _submitting = true);
    final bool ok = await _uploadImages(q.id);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      _finishSuccess();
    } else {
      _snack('첨부 ${_images.length}장 업로드에 실패했어요. 다시 시도해 주세요.');
    }
  }

  /// 성공 종료 — 생성된 질문을 결과로 돌려준다(호출 화면이 상세로 이어감).
  void _finishSuccess() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('질문이 전달됐어요. 캐시는 해결 완료 전까지 안전 보관돼요.'),
      ),
    );
    Navigator.of(context).pop<Object>(_created ?? true);
  }

  Future<void> _submit(IqCreatePrefill prefill) async {
    // 질문이 이미 생성됐다면(첨부 부분 실패 상태) 재생성 금지 — 재시도만.
    if (_created != null) return _retryUpload();

    if (_submitting) return;
    final String title = _titleController.text.trim();
    final String body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack('제목과 내용을 입력해 주세요.');
      return;
    }

    final int? priceCents =
        widget.isDirect ? prefill.pricing?.amountCents : _openAmountCents;
    if (priceCents == null) {
      _snack(widget.isDirect
          ? '이 멘토는 아직 개별질문 가격을 설정하지 않았어요.'
          : '질문 금액(캐시)을 입력해 주세요.');
      return;
    }
    // 서버도 거부하지만(에스크로 잔액 검사) 클라이언트에서 먼저 막는다 — 안내만.
    if (prefill.balanceCents < priceCents) {
      _snack('잔액이 부족해요');
      return;
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('질문을 등록할까요?'),
        content: Text(
          '${formatIqCash(priceCents)}가 안전 보관(예치)돼요.\n'
          '답변을 확인하고 해결 완료를 누르면 멘토에게 정산되고,\n'
          '답변 전에는 언제든 취소(환불)할 수 있어요.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('등록'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final IndividualQuestionType type = widget.isDirect
          ? IndividualQuestionType.direct
          : IndividualQuestionType.open;
      // 지정형 가격은 서버가 가격표에서 결정(클라이언트 금액 미신뢰).
      final int? amountCents = widget.isDirect ? null : _openAmountCents;
      final String idempotencyKey =
          'iqapp-${DateTime.now().microsecondsSinceEpoch}';
      // A-4b ⑧: 과목은 코드 정본(subjects.code) — v2 래퍼로. 공개형 미선택은
      // 서버가 SUBJECT_REQUIRED 로 거부하고 문구 사전이 안내한다.
      final IndividualQuestion created;
      if (widget.submitWithSubjectOverride != null) {
        created = await widget.submitWithSubjectOverride!(
          type: type,
          title: title,
          body: body,
          amountCents: amountCents,
          designatedMentorId: widget.mentorId,
          idempotencyKey: idempotencyKey,
          subject: _subjectCode,
        );
      } else if (widget.submitOverride != null) {
        created = await widget.submitOverride!(
          type: type,
          title: title,
          body: body,
          amountCents: amountCents,
          designatedMentorId: widget.mentorId,
          idempotencyKey: idempotencyKey,
        );
      } else {
        created = await _repo.createAsStudent(
          type: type,
          title: title,
          body: body,
          amountCents: amountCents,
          designatedMentorId: widget.mentorId,
          idempotencyKey: idempotencyKey,
          subject: _subjectCode,
        );
      }
      _created = created;
      // §4: 생성(캐시 예치)은 잔액·원장에 영향 — 지갑 표면 무효화 신호.
      DataRefreshBus.bumpWallet();
      if (!mounted) return;
      if (_images.isEmpty) {
        _finishSuccess();
        return;
      }
      // 질문 생성 성공 → 첨부 업로드(경로에 질문 id 필요 — 생성 후에만 가능).
      final bool allUploaded = await _uploadImages(created.id);
      if (!mounted) return;
      if (allUploaded) {
        _finishSuccess();
      } else {
        _snack('질문은 등록됐어요. 첨부 ${_images.length}장 업로드에 실패해 '
            '아래에서 다시 시도할 수 있어요.');
      }
    } catch (e) {
      _snack(iqActionFailureText(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// A-4b ⑧ 과목 시트 — 정본 코드(`subjects.code`) 목록에서 하나 고른다.
  /// 공개형은 필수(서버 `SUBJECT_REQUIRED`), 지정형은 '선택 안 함' 가능.
  Future<void> _openSubjectSheet() async {
    final String? picked = await showAppBottomSheet<String>(
      context,
      builder: (BuildContext sheet) => _SubjectSheet(
        isDirect: widget.isDirect,
        selected: _subjectCode,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _subjectCode = picked == _SubjectSheet.none ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: widget.isDirect ? '개별질문 하기 (지정형)' : '새 개별질문 (공개형)',
      // A-4b ⑧: 과목 선택은 앱바 액션 + 시트 — 본문 목록 높이를 늘리지 않는다(레이아웃 예산).
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton.icon(
            key: const ValueKey<String>('iq-subject-action'),
            onPressed: _submitting ? null : _openSubjectSheet,
            icon: const Icon(Icons.category_outlined, size: 18),
            label: Text(
              _subjectCode == null
                  ? (widget.isDirect ? '과목 (선택)' : '과목 선택')
                  : subjectLabel(_subjectCode),
            ),
          ),
        ),
      ],
      body: FutureBuilder<IqCreatePrefill>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<IqCreatePrefill> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView(cards: 3);
          }
          if (snap.hasError || snap.data == null) {
            return AppErrorView(
              title: '정보를 불러오지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _retryPrefill,
            );
          }
          return _form(snap.data!);
        },
      ),
    );
  }

  Widget _form(IqCreatePrefill prefill) {
    final int? priceCents =
        widget.isDirect ? prefill.pricing?.amountCents : _openAmountCents;
    final bool insufficient =
        priceCents != null && prefill.balanceCents < priceCents;
    final bool directPriceMissing = widget.isDirect && prefill.pricing == null;
    final bool locked = _created != null;
    final int? remainingCents =
        priceCents == null ? null : prefill.balanceCents - priceCents;
    final TextStyle caption =
        AppTypography.caption.copyWith(color: AppColors.textSecondary);

    // ★ 레이아웃 예산: 첨부·등록 버튼이 기본 위젯 테스트 표면(800×600)에서 스크롤
    //   없이(또는 아주 조금만) 닿아야 한다 — 기존 첨부·PDF·첨삭 테스트가 그 전제로
    //   `ensureVisible` 뒤 곧바로 탭한다. 카드·여백을 늘리지 않는다.
    return ListView(
      padding: AppPage.contentPadding(context),
      children: <Widget>[
        // ── 누구에게 · 내 캐시 ──
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.isDirect
                    ? '${widget.mentorName ?? '멘토'}에게 지정 · 멘토가 수락하면 시작돼요'
                    : (_subjectCode == null
                        ? '공개 · 과목을 고르면 그 과목 멘토에게 먼저 보여요'
                        : '공개 · ${subjectLabel(_subjectCode)} 멘토에게 먼저 보여요'),
                style: AppTypography.body,
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Text('내 캐시', style: caption),
                  const Spacer(),
                  Text(
                    formatIqCash(prefill.balanceCents),
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (directPriceMissing) ...<Widget>[
          const SizedBox(height: 10),
          const AppCallout(
            tone: AppCalloutTone.danger,
            text: '이 멘토는 아직 개별질문 가격을 설정하지 않아 질문할 수 없어요.',
          ),
        ],
        const SizedBox(height: 12),
        // ── 무엇을 ──
        if (!widget.isDirect) ...<Widget>[
          AppInputField(
            controller: _amountController,
            labelText: '질문 금액 (캐시)',
            hintText: '예: $kIqOpenPricePlaceholderCash',
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            enabled: !locked && !_submitting,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
        ],
        AppInputField(
          controller: _titleController,
          labelText: '제목',
          enabled: !locked && !_submitting,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        AppInputField(
          controller: _bodyController,
          labelText: '질문 내용',
          hintText: '문제 상황과 어디까지 시도했는지 적어 주세요.',
          enabled: !locked && !_submitting,
          minLines: 4,
          maxLines: 12,
        ),
        const SizedBox(height: 12),
        _AttachArea(
          images: _images,
          maxImages: _maxImages,
          locked: locked, // 부분 실패 상태: 목록 편집 대신 재시도.
          onAdd: _submitting ? null : _addImage,
          onRemove: _submitting ? null : _removeImage,
          onAnnotate: _submitting ? null : _annotateImage,
        ),
        if (locked) ...<Widget>[
          const SizedBox(height: 10),
          AppCallout(
            tone: AppCalloutTone.warning,
            text: '질문은 등록됐어요. 남은 첨부 ${_images.length}장을 다시 업로드하거나, '
                '첨부 없이 완료할 수 있어요.',
          ),
        ],
        const SizedBox(height: 12),
        // ── 결제 요약(사실만) ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: <Widget>[
              Text('결제될 금액', style: caption),
              const Spacer(),
              Text(
                priceCents == null
                    ? (widget.isDirect ? '—' : '금액을 입력해 주세요')
                    : formatIqCash(priceCents),
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (remainingCents != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: <Widget>[
                Text('등록 후 남는 캐시', style: caption),
                const Spacer(),
                Text(
                  // formatIqCash 는 절댓값만 찍는다 — 모자라면 부호를 붙여 사실대로.
                  remainingCents < 0
                      ? '-${formatIqCash(remainingCents)}'
                      : formatIqCash(remainingCents),
                  style: AppTypography.body.copyWith(
                    color:
                        insufficient ? AppColors.danger : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        if (insufficient) ...<Widget>[
          const SizedBox(height: 10),
          // ★ Commerce-Zero: 사실 안내만 — 충전 버튼·링크·인앱 브라우저 없음.
          const AppCallout(
            tone: AppCalloutTone.warning,
            title: '잔액이 부족해요',
            text: '지금 캐시로는 이 질문을 등록할 수 없어요.',
          ),
        ],
        const SizedBox(height: 14),
        AppPrimaryButton(
          label: locked ? '첨부 다시 업로드' : '질문 등록',
          onPressed: _submitting || directPriceMissing || insufficient
              ? null
              : () => _submit(prefill),
        ),
        if (locked) ...<Widget>[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting ? null : _finishSuccess,
            child: const Text('첨부 없이 완료'),
          ),
        ],
      ],
    );
  }
}

/// 첨부 영역 — 썸네일 미리보기 + 개별 삭제 + '필기하기'(S18) +
/// 추가 버튼(최대 [maxImages]장).
class _AttachArea extends StatelessWidget {
  const _AttachArea({
    required this.images,
    required this.maxImages,
    required this.locked,
    required this.onAdd,
    required this.onRemove,
    required this.onAnnotate,
  });

  final List<PickedImage> images;
  final int maxImages;
  final bool locked;
  final VoidCallback? onAdd;
  final void Function(int index)? onRemove;
  final void Function(int index)? onAnnotate;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '문제 스캔 첨부 (${images.length}/$maxImages)',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (images.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (int i = 0; i < images.length; i++)
                  Stack(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          images[i].bytes,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 72,
                            height: 72,
                            color: AppColors.bgMid,
                            child: const Icon(Icons.image_rounded,
                                color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      if (!locked)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Semantics(
                            button: true,
                            label: '첨부 삭제',
                            child: GestureDetector(
                              onTap:
                                  onRemove == null ? null : () => onRemove!(i),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      if (!locked)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Semantics(
                            button: true,
                            label: '필기하기',
                            child: GestureDetector(
                              onTap: onAnnotate == null
                                  ? null
                                  : () => onAnnotate!(i),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(3),
                                child: const Icon(Icons.draw_rounded,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
          if (!locked) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: images.length >= maxImages ? null : onAdd,
              icon: const Icon(Icons.add_a_photo_rounded, size: 18),
              label: const Text('사진 첨부'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 슬롯별 로컬 첨삭 상태(S18) — 평탄화본이 슬롯을 대체한 뒤에도 이어 그리기가
/// 가능하도록 '원본 배경'과 '최신 스트로크'를 화면 생존 동안 보관한다.
class _DraftInk {
  const _DraftInk({required this.original, required this.document});

  /// 첨삭 전 원본 이미지 — 재편집 배경(평탄화본 위에 다시 그리지 않는다).
  final PickedImage original;

  /// 최신 정규화(0..1) 스트로크 문서.
  final InkDocument document;
}

/// 공개형 금액 placeholder(웹 정본 `OPEN_INDIVIDUAL_QUESTION_PRICE_PLACEHOLDER_CASH`
/// 미러 — 예시일 뿐 최소/최대 강제 아님).
const int kIqOpenPricePlaceholderCash = 5000;

/// 과목 선택 시트(A-4b ⑧). 코드값은 화면에 노출하지 않고 한글 라벨만.
class _SubjectSheet extends StatelessWidget {
  const _SubjectSheet({required this.isDirect, required this.selected});

  final bool isDirect;
  final String? selected;

  /// '선택 안 함' 반환값(지정형 전용).
  static const String none = '__none__';

  @override
  Widget build(BuildContext context) {
    final Color accent = RoleTheme.of(context).color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 4),
        const Text('과목을 골라 주세요', style: AppTypography.section),
        const SizedBox(height: 4),
        Text(
          isDirect
              ? '선택 사항이에요. 골라 두면 멘토가 질문을 더 빨리 파악해요.'
              : '공개 질문은 과목을 골라야 그 과목 멘토에게 배정돼요.',
          style: AppTypography.captionSecondary,
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (isDirect)
                  _SubjectPill(
                    label: '선택 안 함',
                    active: selected == null,
                    accent: accent,
                    onTap: () => Navigator.of(context).pop(none),
                  ),
                for (final String code in IqCreateScreen.subjectCodes)
                  _SubjectPill(
                    label: subjectLabel(code),
                    active: selected == code,
                    accent: accent,
                    onTap: () => Navigator.of(context).pop(code),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SubjectPill extends StatelessWidget {
  const _SubjectPill({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassInner(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ringColor: active ? accent : null,
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: active ? accent : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
