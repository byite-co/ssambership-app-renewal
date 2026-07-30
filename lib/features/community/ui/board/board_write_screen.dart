import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../design/shape_tokens.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/primary_button.dart';
import '../../../../shared/errors/app_error.dart';
import '../../data/community_labels.dart';
import '../../data/community_post_actions.dart';
import '../../data/community_post_images.dart';
import '../../data/community_write_repository.dart';
import '../widgets/content_policy_gate.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 갤러리에서 고른 이미지 원본(테스트 주입용 최소 형태).
typedef PickedBoardImage = ({Uint8List bytes, String name});

/// 이미지 선택 seam(기본: image_picker 갤러리 다중 선택).
typedef BoardImagePicker = Future<List<PickedBoardImage>> Function();

Future<List<PickedBoardImage>> _defaultPickImages() async {
  final List<XFile> files = await ImagePicker().pickMultiImage();
  return <PickedBoardImage>[
    for (final XFile f in files) (bytes: await f.readAsBytes(), name: f.name),
  ];
}

/// 게시판 글쓰기(승인 멘토 전용 — 서버 F4 가 최종 판정) — 제목 + 본문 +
/// 카테고리 + 이미지 최대 5장, 즉시 공개. 성공 시 pop(true).
///
/// S2-2 멱등 규약(앱 계약 §6.3): 멱등키는 작성 시도당 1회 생성하고,
/// 응답 불명확([CommunityCreateUnclear]) 후 재등록은 **같은 키**로 다시
/// 시도한다(새 키 금지 — 같은 키 재호출이 정본 복구 경로).
class BoardWriteScreen extends StatefulWidget {
  const BoardWriteScreen({
    super.key,
    this.write = const CommunityWriteRepository(),
    this.pickImages = _defaultPickImages,
  });

  final CommunityWriteRepository write;
  final BoardImagePicker pickImages;

  @override
  State<BoardWriteScreen> createState() => _BoardWriteScreenState();
}

class _BoardWriteScreenState extends State<BoardWriteScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  String _category = communityCategoryOptions.first.key;
  bool _submitting = false;

  final List<ValidatedPostImage> _images = <ValidatedPostImage>[];

  /// 진행 중 작성 시도의 멱등키. 응답 불명확 시 유지(같은 키 재시도),
  /// 확정 거부(도메인 실패) 후에는 새 시도로 보고 재발급한다.
  String? _idempotencyKey;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_submitting) return;
    final List<PickedBoardImage> picked;
    try {
      picked = await widget.pickImages();
    } catch (_) {
      _snack('이미지를 불러오지 못했어요.');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    final List<ValidatedPostImage> next = <ValidatedPostImage>[];
    for (final PickedBoardImage p in picked) {
      if (_images.length + next.length >= kCommunityPostImageMaxCount) {
        _snack('이미지는 최대 5장까지 첨부할 수 있어요.');
        break;
      }
      try {
        next.add(validateCommunityPostImage(bytes: p.bytes, fileName: p.name));
      } on AppError catch (e) {
        _snack(e.userMessage);
      }
    }
    if (next.isNotEmpty) setState(() => _images.addAll(next));
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
    // 작성 시도당 1회 생성 — 불명확 실패 후 재시도는 같은 키를 재사용한다.
    final String key = _idempotencyKey ??= generateUuidV4();
    try {
      await widget.write.createPost(
        title: title,
        body: body,
        category: _category,
        idempotencyKey: key,
        images: List<ValidatedPostImage>.unmodifiable(_images),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CommunityCreateUnclear catch (e) {
      // 키 유지 — 다음 '등록'이 같은 멱등키로 replay-first 재시도한다.
      _snack(e.userMessage);
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      // 확정 거부·업로드 실패 등 — 이번 시도는 종결, 다음 등록은 새 시도.
      _idempotencyKey = null;
      _snack('글 등록에 실패했어요. ${friendlyError(e)}');
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

  Widget _imageStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickImages,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text('이미지 첨부 (${_images.length}/'
                  '$kCommunityPostImageMaxCount)'),
            ),
          ],
        ),
        if (_images.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (int i = 0; i < _images.length; i++)
                Stack(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _images[i].bytes,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _submitting
                            ? null
                            : () => setState(() => _images.removeAt(i)),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 글쓰기')),
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
          _imageStrip(),
          const SizedBox(height: AppSpacing.s24),
          PrimaryButton(
            label: _submitting ? '등록 중…' : '등록',
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
