import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scribble/scribble.dart';

import '../../core/ink/ink_coordinate_mapper.dart';
import '../../core/ink/ink_document.dart';
import '../../core/ink/ink_input_mode.dart';
import '../../core/ink/scribble_ink_adapter.dart';
import '../../core/scan/image_downscaler.dart';
import '../../design/tokens/color_tokens.dart';
import '../../core/ink/widgets/ink_toolbar.dart';
import 'annotation_flattener.dart';
import 'annotation_sketch.dart';
import 'annotation_target.dart';
import 'data/scan_annotation_repository.dart';
import '../../shared/errors/friendly_error.dart';

/// 첨부 이미지 위 주석 화면(S15, S18 에서 전송 대상 포트화).
///
/// ★ 재사용: S13 코어(InkCoordinateMapper·ScribbleInkAdapter·InkDocument)와
///   S14 툴바(InkToolbar)를 그대로 쓴다 — 재구현하지 않는다.
/// ★ 좌표 정합(기획서 잠금): 캔버스를 fit 된 이미지 영역과 '정확히 같은 사각형'에
///   올려, 스트로크는 이미지 정규화 좌표(0..1)로 저장/복원한다. InteractiveViewer
///   줌·팬은 이미지와 캔버스가 같은 레이어라 추가 보정 없이 함께 변환된다.
/// ★ 전송 대상(S18): [target] 이 있으면 완료 결과를 그 포트로 보낸다.
///   없으면 기존처럼 [roomId]/[threadId] 의 질문방 스레드 첨부로 보낸다
///   (기존 호출부 무변경 — 옵션 추가 방식).
class ScanAnnotationScreen extends StatefulWidget {
  const ScanAnnotationScreen({
    super.key,
    required this.background,
    this.roomId,
    this.threadId,
    this.target,
    this.initial,
    this.repository,
    this.title,
    this.initialPenColor,
    @visibleForTesting this.backgroundImageOverride,
  }) : assert(
          target != null || (roomId != null && threadId != null),
          'target 이 없으면 roomId/threadId(질문방 기본 경로)가 필요하다.',
        );

  /// 배경 이미지 바이트(질문방 첨부 또는 갤러리 선택). 디코딩해서 배경·평탄화에 쓴다.
  final Uint8List background;

  /// 질문방 기본 경로의 대상 방. [target] 사용 시 무시된다.
  final String? roomId;

  /// 평탄화 PNG 를 첨부로 보낼 대상 스레드. [target] 사용 시 무시된다.
  final String? threadId;

  /// 완료 결과 전송 포트(S18). null 이면 질문방 기본 경로(S15 현행 동작).
  final AnnotationTarget? target;

  /// 앱바 제목. null 이면 기존 '사진에 주석 달기'.
  final String? title;

  /// 시작 펜 색(멘토 첨삭 = 빨강 프리셋, §6-2). null 이면 엔진 기본색.
  final Color? initialPenColor;

  /// 재편집 진입 시 복원할 기존 주석(정규화 좌표). null 이면 새 주석.
  final InkDocument? initial;

  /// 저장/전송 레포 오버라이드(테스트 fake 주입). null 이면 Supabase 기본.
  final ScanAnnotationRepository? repository;

  /// 디코딩된 배경 오버라이드(테스트용 — 실제 디코드 회피).
  @visibleForTesting
  final ui.Image? backgroundImageOverride;

  @override
  State<ScanAnnotationScreen> createState() => _ScanAnnotationScreenState();
}

class _ScanAnnotationScreenState extends State<ScanAnnotationScreen> {
  late final ScribbleNotifier _notifier;
  late final AnnotationTarget _target;

  ui.Image? _bg;
  Size? _imageSize;
  InkInputMode _inputMode = InkInputMode.penOnly;
  bool _submitting = false;
  bool _restored = false;

  /// 최신 좌표 매퍼/이미지 영역(빌드의 LayoutBuilder 에서 갱신, 완료 시 사용).
  InkCoordinateMapper? _mapper;
  Rect? _fitted;

  @override
  void initState() {
    super.initState();
    _target = widget.target ??
        QuestionRoomAnnotationTarget(
          repository: widget.repository ?? ScanAnnotationRepository.supabase(),
          roomId: widget.roomId!,
          threadId: widget.threadId!,
        );
    _inputMode = widget.initial?.inputMode ?? InkInputMode.penOnly;
    _notifier = ScribbleInkAdapter.createNotifier(mode: _inputMode);
    final Color? preset = widget.initialPenColor;
    if (preset != null) _notifier.setColor(preset);
    _loadBackground();
  }

  Future<void> _loadBackground() async {
    // P2-20: 초대형 배경은 합성 '전에' 장변을 §6-4 캡(2560px)으로 줄인다 —
    // 평탄화가 배경 원본 해상도로 출력되므로, 여기서 줄여야 OOM·초과 출력이 없다.
    // (스트로크는 정규화(0..1) 좌표라 배경 축소와 무관하게 위치가 보존된다.)
    final ui.Image image = widget.backgroundImageOverride ??
        await AnnotationFlattener.decodeImage(
            await downscaleFlattenBackground(widget.background));
    if (!mounted) {
      if (widget.backgroundImageOverride == null) image.dispose();
      return;
    }
    setState(() {
      _bg = image;
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    });
  }

  @override
  void dispose() {
    _notifier.dispose();
    if (widget.backgroundImageOverride == null) _bg?.dispose();
    super.dispose();
  }

  void _onInputModeChanged(InkInputMode mode) =>
      setState(() => _inputMode = mode);

  /// 캔버스-로컬 좌표 → 이미지 정규화(저장용). fitted 왼쪽위 오프셋을 더해 뷰포트로.
  Offset _normalizePoint(Offset local) =>
      _mapper!.normalize(local + _fitted!.topLeft);

  /// 이미지 정규화 → 캔버스-로컬(복원용).
  Offset _denormalizePoint(Offset norm) =>
      _mapper!.denormalize(norm) - _fitted!.topLeft;

  /// 재편집: 기존 정규화 스케치를 현재 뷰포트의 캔버스-로컬로 복원(1회).
  void _restoreIfNeeded() {
    if (_restored || widget.initial == null || _mapper == null) return;
    _restored = true;
    final Map<String, dynamic> local = AnnotationSketch.transform(
      widget.initial!.sketch,
      point: _denormalizePoint,
      width: (double w) => _mapper!.denormalizeLength(w),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifier.setSketch(sketch: Sketch.fromJson(local));
    });
  }

  /// '완료' — 스트로크를 정규화해 문서로 만들고, 평탄화 PNG 를 첨부로 전송한다.
  /// 빈 주석이면 전송 없이 닫는다(결과 null).
  Future<void> _onDone() async {
    if (_mapper == null ||
        _fitted == null ||
        _bg == null ||
        _imageSize == null) {
      return;
    }
    final Map<String, dynamic> normalized = AnnotationSketch.transform(
      _notifier.currentSketch.toJson(),
      point: _normalizePoint,
      width: (double w) => _mapper!.normalizeLength(w),
    );
    final InkDocument document = InkDocument(
      canvasWidth: _imageSize!.width,
      canvasHeight: _imageSize!.height,
      sketch: normalized,
      inputMode: _inputMode,
      updatedAt: DateTime.now().toUtc(),
    );
    if (document.isEmpty) {
      Navigator.of(context).pop(); // 빈 주석 → 전송 없음.
      return;
    }

    setState(() => _submitting = true);
    try {
      final Uint8List png = await AnnotationFlattener.flatten(
        background: _bg!,
        normalizedSketch: normalized,
      );
      await _target.submit(
        AnnotationResult(document: document, flattenedPng: png),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('주석 전송에 실패했어요. ${friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorTokens.page,
      appBar: AppBar(
        title: Text(widget.title ?? '사진에 주석 달기'),
        actions: <Widget>[
          TextButton(
            onPressed: _submitting || _bg == null ? null : _onDone,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('완료'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _canvasArea()),
          InkToolbar(
            notifier: _notifier,
            inputMode: _inputMode,
            onInputModeChanged: _onInputModeChanged,
          ),
        ],
      ),
    );
  }

  Widget _canvasArea() {
    final ui.Image? bg = _bg;
    final Size? imageSize = _imageSize;
    if (bg == null || imageSize == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final InkCoordinateMapper mapper = InkCoordinateMapper.contain(
          imageSize: imageSize,
          viewport: viewport,
        );
        _mapper = mapper;
        _fitted = mapper.fitted;
        _restoreIfNeeded();

        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          // 손가락은 줌·팬(펜 전용 모드에선 스타일러스만 그린다 — S13 입력모드).
          panEnabled: true,
          scaleEnabled: true,
          child: SizedBox(
            width: viewport.width,
            height: viewport.height,
            child: Stack(
              children: <Widget>[
                Positioned.fromRect(
                  rect: mapper.fitted,
                  child: RawImage(
                    image: bg,
                    width: mapper.fitted.width,
                    height: mapper.fitted.height,
                    fit: BoxFit.fill, // fitted 는 이미지 비율과 동일 → 왜곡 없음.
                  ),
                ),
                Positioned.fromRect(
                  rect: mapper.fitted,
                  child: Scribble(notifier: _notifier), // 투명 캔버스(배경 위).
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
