import 'package:flutter/material.dart';

import '../../../../core/scan/picked_image.dart';
import '../../../../design/shape_tokens.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/primary_button.dart';
import '../../../question_room/data/attachments/attachment_upload.dart'
    show ImagePickerPort;
import '../../../question_room/data/attachments/device_image_picker.dart';
import '../../data/board_post_create_gateway.dart';
import '../../data/board_post_media_gateway.dart';
import '../../data/community_labels.dart';
import '../../data/community_models.dart';
import '../../data/community_write_repository.dart';
import '../widgets/content_policy_gate.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 게시판 글쓰기·수정 — 제목 + 본문 + 카테고리 + 이미지(최대 5장, 즉시 공개).
/// [editing] 지정 시 자기 글 수정 모드(호출부가 소유권을 확인해 진입 —
/// 보안 정본은 서버 community_post_update 의 author_id 검사).
/// 성공 시 pop(true) 로 알린다(호출부가 목록 새로고침).
/// ★ 학생·멘토 동일 화면 — 역할로 UI 를 분기하지 않는다(판정은 서버).
class BoardWriteScreen extends StatefulWidget {
  const BoardWriteScreen({
    super.key,
    this.write = const CommunityWriteRepository(),
    this.editing,
    this.imagePicker = const DeviceImagePicker(),
  });

  final CommunityWriteRepository write;

  /// null = 새 글, 지정 시 이 글의 수정.
  final BoardPost? editing;

  final ImagePickerPort imagePicker;

  @override
  State<BoardWriteScreen> createState() => _BoardWriteScreenState();
}

/// 이번 작성/수정 작업에서 새로 고른 이미지. [uploadedRef]가 채워지면 이미
/// Storage 에 올라간 상태 — 제출 재시도에서 다시 올리지 않는다(중복 방지).
class _PendingImage {
  _PendingImage(this.image);

  final PickedImage image;
  String? uploadedRef;
}

class _BoardWriteScreenState extends State<BoardWriteScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  String _category = communityCategoryOptions.first.key;
  bool _submitting = false;

  /// 수정 모드: 글에 남겨 둘 기존 이미지 ref(사용자가 X 로 빼면 제거 —
  /// 실제 Storage 삭제는 서버 removed_image_refs 기준, RPC 성공 후에만).
  final List<String> _keptExistingRefs = <String>[];

  /// 이번 작업에서 새로 고른 이미지(기존과 합쳐 최대 5장).
  final List<_PendingImage> _newImages = <_PendingImage>[];

  /// 이 작성 작업(operation)의 멱등키. 실패해도 **버리지 않는다** — 응답이
  /// 유실됐을 뿐 서버에 글이 남았을 수 있어, 재시도는 같은 키로 보내야 서버가
  /// 기존 글로 수렴시킨다(중복 글 방지). 성공하면 작업이 끝나므로 비우고,
  /// 새 작성 화면(새 State)은 자연히 새 키로 시작한다. (수정 모드 미사용)
  String? _operationKey;

  bool get _isEditing => widget.editing != null;

  int get _imageCount => _keptExistingRefs.length + _newImages.length;

  @override
  void initState() {
    super.initState();
    final BoardPost? editing = widget.editing;
    if (editing != null) {
      _title.text = editing.title;
      _body.text = editing.body ?? '';
      final String? category = editing.category;
      if (category != null &&
          communityCategoryOptions
              .any((MapEntry<String, String> e) => e.key == category)) {
        _category = category;
      }
      _keptExistingRefs.addAll(editing.imageRefs);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _addImage() async {
    if (_submitting) return;
    if (_imageCount >= kCommunityPostImageMaxCount) {
      _snack('이미지는 최대 5장까지 첨부할 수 있어요.');
      return;
    }
    final PickedImage? picked = await widget.imagePicker.pickImage();
    if (picked == null || !mounted) return;
    final String? invalid = validateCommunityPostImage(picked);
    if (invalid != null) {
      _snack(invalid);
      return;
    }
    setState(() => _newImages.add(_PendingImage(picked)));
  }

  /// 새 이미지들을 Storage 에 올려 최종 ref 집합(유지 기존 + 새 업로드)을
  /// 만든다. 이미 올라간 이미지는 다시 올리지 않는다(재시도 중복 방지).
  Future<List<String>> _uploadNewImagesAndCollectRefs() async {
    for (final _PendingImage pending in _newImages) {
      pending.uploadedRef ??=
          await widget.write.uploadPostImage(pending.image);
    }
    return <String>[
      ..._keptExistingRefs,
      for (final _PendingImage pending in _newImages) pending.uploadedRef!,
    ];
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final String title = _title.text.trim();
    final String body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack('제목과 내용을 입력해 주세요.');
      return;
    }
    // 게시 전 커뮤니티 이용 규정 동의(UGC 심사 요건). 미동의 시 등록 중단.
    if (!await ContentPolicyGate.ensureAgreed(context)) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    if (_isEditing) {
      await _submitUpdate(title: title, body: body);
    } else {
      await _submitCreate(title: title, body: body);
    }
  }

  Future<void> _submitCreate(
      {required String title, required String body}) async {
    // 같은 제출 작업은 재시도해도 같은 키를 유지한다(첫 제출에서만 새로 만든다).
    final String operationKey = _operationKey ??= newBoardPostIdempotencyKey();
    try {
      final List<String> imageRefs = await _uploadNewImagesAndCollectRefs();
      await widget.write.createPost(
        title: title,
        body: body,
        category: _category,
        idempotencyKey: operationKey,
        imageRefs: imageRefs,
      );
      _operationKey = null; // 작업 종료 — 다음 작성은 새 키.
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('글 등록에 실패했어요. ${friendlyError(e)}');
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitUpdate(
      {required String title, required String body}) async {
    final BoardPost editing = widget.editing!;
    final String? expected = editing.updatedAtRaw;
    if (expected == null || expected.trim().isEmpty) {
      // 충돌 검사 기준이 없으면 보내지 않는다(fail-closed).
      _snack('글 정보를 확인하지 못했어요. 목록을 새로고침 후 다시 시도해 주세요.');
      if (mounted) setState(() => _submitting = false);
      return;
    }
    try {
      final List<String> imageRefs = await _uploadNewImagesAndCollectRefs();
      await widget.write.updatePost(
        postId: editing.id,
        title: title,
        body: body,
        category: _category,
        expectedUpdatedAt: expected,
        imageRefs: imageRefs,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('글 수정에 실패했어요. ${friendlyError(e)}');
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: AppType.caption,
      filled: true,
      fillColor: ColorTokens.elevated,
      border: const OutlineInputBorder(
        borderRadius: AppShape.inputRadius,
        borderSide: BorderSide.none,
      ),
    );
  }

  /// 이미지 첨부 영역 — 기존 이미지는 중립 라벨(원문 경로·UUID 비노출),
  /// 새 이미지는 파일명으로 표시. 각각 X 로 뺄 수 있다.
  Widget _imagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('이미지 ($_imageCount/$kCommunityPostImageMaxCount)',
            style: AppType.caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (int i = 0; i < _keptExistingRefs.length; i++)
              InputChip(
                key: ValueKey<String>('existing-${_keptExistingRefs[i]}'),
                deleteIcon: const Icon(Icons.close, size: 18),
                label: Text('기존 이미지 ${i + 1}', style: AppType.caption),
                onDeleted: _submitting
                    ? null
                    : () => setState(() => _keptExistingRefs.removeAt(i)),
              ),
            for (int i = 0; i < _newImages.length; i++)
              InputChip(
                key: ValueKey<Object>('new-$i-${_newImages[i].image.fileName}'),
                deleteIcon: const Icon(Icons.close, size: 18),
                label: Text(_newImages[i].image.fileName,
                    style: AppType.caption, overflow: TextOverflow.ellipsis),
                onDeleted: _submitting
                    ? null
                    : () => setState(() => _newImages.removeAt(i)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('이미지 추가', style: AppType.caption),
              onPressed: _submitting ? null : _addImage,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '글 수정' : '새 글쓰기')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH, 16, AppSpacing.screenH, 24),
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: _decoration('카테고리'),
            style: AppType.body,
            items: <DropdownMenuItem<String>>[
              for (final MapEntry<String, String> e in communityCategoryOptions)
                DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
            ],
            onChanged: _submitting
                ? null
                : (String? v) {
                    if (v != null) setState(() => _category = v);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            style: AppType.body,
            decoration: _decoration('제목'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            style: AppType.body,
            minLines: 8,
            maxLines: 16,
            decoration:
                _decoration('내용', hint: '커뮤니티 가이드에 맞게 작성해 주세요.'),
          ),
          const SizedBox(height: 12),
          _imagesSection(),
          const SizedBox(height: AppSpacing.s24),
          PrimaryButton(
            label: _submitting
                ? (_isEditing ? '수정 중…' : '등록 중…')
                : (_isEditing ? '수정' : '등록'),
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
