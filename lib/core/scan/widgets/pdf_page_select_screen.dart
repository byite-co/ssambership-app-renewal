import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_page.dart';
import '../../../shared/errors/friendly_error.dart';
import '../pdf_rasterizer.dart';
import '../picked_image.dart';

/// PDF 페이지 선택 그리드(S19, §6-1).
///
/// 썸네일은 GridView.builder 로 **보이는 칸만 지연 렌더**한다(50페이지
/// 문제집 대비 메모리 보호 — 렌더 future 는 페이지당 1회 캐시).
/// 다중 선택(최대 [maxSelect]) 후 '가져오기'를 누르면 선택 페이지를
/// 본렌더(장변 [kPdfRenderLongSidePx])해 [PickedImage] 목록으로 pop 한다.
class PdfPageSelectScreen extends StatefulWidget {
  const PdfPageSelectScreen({
    super.key,
    required this.document,
    required this.baseName,
    required this.maxSelect,
  });

  /// 열린 PDF 핸들. 수명은 호출부 소유 — 이 화면은 close 하지 않는다.
  final PdfDocumentHandle document;

  /// 첨부 파일명 접두(원본 PDF 이름, 확장자 제외).
  final String baseName;

  /// 선택 상한(§6-1 최대 5 와 남은 첨부 슬롯 중 작은 값 — 호출부가 계산).
  final int maxSelect;

  @override
  State<PdfPageSelectScreen> createState() => _PdfPageSelectScreenState();
}

class _PdfPageSelectScreenState extends State<PdfPageSelectScreen> {
  /// 선택 순서 보존(가져오기 시 이 순서대로 첨부가 된다).
  final List<int> _selected = <int>[];

  /// 썸네일 지연 렌더 캐시 — 스크롤로 다시 보여도 재렌더하지 않는다.
  final Map<int, Future<Uint8List>> _thumbs = <int, Future<Uint8List>>{};

  bool _importing = false;

  Future<Uint8List> _thumb(int index) => _thumbs.putIfAbsent(
        index,
        () => widget.document
            .renderPage(index, longSide: kPdfThumbLongSidePx),
      );

  void _toggle(int index) {
    if (_importing) return;
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
        return;
      }
      if (_selected.length >= widget.maxSelect) {
        // 초과 선택 즉시 안내(§6-1 — 슬롯 연동 상한).
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('페이지는 최대 ${widget.maxSelect}장까지 선택할 수 있어요.'),
        ));
        return;
      }
      _selected.add(index);
    });
  }

  /// 선택 페이지 본렌더 → PickedImage 목록으로 닫기.
  Future<void> _import() async {
    if (_selected.isEmpty || _importing) return;
    setState(() => _importing = true);
    try {
      final List<PickedImage> images = <PickedImage>[];
      for (final int index in _selected) {
        final Uint8List png = await widget.document
            .renderPage(index, longSide: kPdfRenderLongSidePx);
        images.add(PickedImage(
          bytes: png,
          fileName: '${widget.baseName}-p${index + 1}.png',
          mimeType: 'image/png',
        ));
      }
      if (mounted) Navigator.of(context).pop(images);
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '질문할 페이지 선택 (${_selected.length}/${widget.maxSelect})',
      actions: <Widget>[
        TextButton(
          onPressed: _selected.isEmpty || _importing ? null : _import,
          child: _importing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('가져오기 (${_selected.length})'),
        ),
      ],
      body: GridView.builder(
        clipBehavior: Clip.none,
        padding: AppPage.contentPadding(context),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.72, // A4 세로 비율 근사.
        ),
        itemCount: widget.document.pageCount,
        itemBuilder: (BuildContext context, int index) {
          final int order = _selected.indexOf(index);
          return _PageTile(
            pageNumber: index + 1,
            selectedOrder: order < 0 ? null : order + 1,
            thumbnail: _thumb(index),
            onTap: () => _toggle(index),
          );
        },
      ),
    );
  }
}

/// 페이지 1칸 — 지연 썸네일 + 선택 순번 배지.
class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.pageNumber,
    required this.selectedOrder,
    required this.thumbnail,
    required this.onTap,
  });

  final int pageNumber;

  /// 선택됐으면 1-기준 순번, 아니면 null.
  final int? selectedOrder;
  final Future<Uint8List> thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool selected = selectedOrder != null;
    final Color role = RoleTheme.of(context).color;
    return Semantics(
      button: true,
      label: '$pageNumber페이지${selected ? ' 선택됨' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.glass,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? role : AppColors.ring,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: FutureBuilder<Uint8List>(
                      future: thumbnail,
                      builder: (BuildContext context,
                          AsyncSnapshot<Uint8List> snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        if (snap.hasError || snap.data == null) {
                          return const Center(
                            child: Icon(Icons.broken_image_rounded,
                                color: AppColors.textSecondary),
                          );
                        }
                        return Image.memory(
                          snap.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded,
                                color: AppColors.textSecondary),
                          ),
                        );
                      },
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: role,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$selectedOrder',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text('$pageNumber', style: AppTypography.meta),
          ],
        ),
      ),
    );
  }
}
