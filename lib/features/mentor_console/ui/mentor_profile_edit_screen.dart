import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../app/app_scope.dart';
import '../../../core/scan/image_downscaler.dart';
import '../../../core/scan/picked_image.dart';
import '../../../core/scan/scan_source_picker.dart';
import '../../../data/mappings/subject_labels.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_input_field.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../design/widgets/glass_inner.dart';
import '../../question_room/data/attachments/attachment_upload.dart'
    show validatePickedImage;
import '../../../shared/errors/friendly_error.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_blocks.dart';
import '../data/mentor_console_models.dart';
import '../data/mentor_console_repository.dart';
import 'academic_record_change_screen.dart';
import 'mentor_document_field.dart';

/// 입력 상한 — 웹 `MentorProfileEditForm` maxLength 미러(고교 40, 한줄 50, 상세 500).
const int kMentorNameFieldMax = 40;
const int kMentorIntroLineMax = 50;
const int kMentorBioMax = 500;

/// 멘토 프로필 편집(A-4a α2·α3) — `/profile/edit`. 웹 `MentorProfileEditForm` 대조 결과
/// (2026-09-05): 사용자가 고칠 수 있는 것은 사진·출신 고등학교·담당 과목·한줄 소개·상세
/// 소개 5개뿐이다. 대학교·학과는 웹에서 readOnly(잠금 · 학적변경요청으로만), 답변
/// 스타일·구독 열림은 웹에 편집 UI 가 없어 현재 값을 그대로 재전송한다(웹 동일).
///
/// F7 `mentor_profile_update_self` 는 allowlist 9필드 **전면 교체**라 현재 값을
/// 먼저 읽어 폼에 채우고 9개를 모두 다시 보낸다. 담당 과목은 정본 코드만 전송
/// (서버도 `subjects.code` 실존 값만 남긴다). 과목이 0개면 웹과 같이 구독 열림을
/// 닫아서 보낸다. 사진은 `profile-avatars/{uid}/…` 에 먼저 올리고 공개 URL 을
/// `p_profile_image_url` 로 넘긴다.
class MentorProfileEditScreen extends StatefulWidget {
  const MentorProfileEditScreen({
    super.key,
    this.portOverride,
    this.scanPicker = const DeviceScanSourcePicker(),
  });

  final MentorConsolePort? portOverride;
  final ScanSourcePort scanPicker;

  @override
  State<MentorProfileEditScreen> createState() =>
      _MentorProfileEditScreenState();
}

class _MentorProfileEditScreenState extends State<MentorProfileEditScreen> {
  late final MentorConsolePort _port;
  late Future<MentorOwnProfile> _future;

  final TextEditingController _highSchool = TextEditingController();
  final TextEditingController _introLine = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  final Set<String> _subjects = <String>{};
  String? _avatarUrl;

  /// 마지막으로 읽은 현재 프로필 — 편집 UI 가 없는 필드(대학·학과·답변 스타일·
  /// 구독 열림)는 여기 값을 그대로 재전송한다.
  MentorOwnProfile? _current;

  bool _seeded = false;
  bool _saving = false;
  bool _uploading = false;
  String? _avatarError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _port = widget.portOverride ?? AppScope.of(context).mentorConsole;
    _future = _load();
    for (final TextEditingController c in _controllers) {
      c.addListener(_onEdit);
    }
  }

  List<TextEditingController> get _controllers => <TextEditingController>[
        _highSchool,
        _introLine,
        _bio,
      ];

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onEdit() => setState(() => _saveError = null);

  Future<MentorOwnProfile> _load() async {
    final MentorOwnProfile p = await _port.loadOwnProfile();
    _current = p;
    if (!_seeded) {
      _seeded = true;
      _highSchool.text = p.highSchoolName ?? '';
      _introLine.text = p.introLine ?? '';
      _bio.text = p.bio ?? '';
      _subjects
        ..clear()
        ..addAll(mentorSubjectCodesStrict(p.teachingSubjects));
      _avatarUrl = p.profileImageUrl;
    }
    return p;
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  // ── 검증(클라이언트) ──
  String? _lengthError(TextEditingController c, int max, String what) {
    if (c.text.trim().length > max) return '$what은(는) $max자까지 입력할 수 있어요.';
    return null;
  }

  String? get _highSchoolError =>
      _lengthError(_highSchool, kMentorNameFieldMax, '고등학교');
  String? get _introLineError =>
      _lengthError(_introLine, kMentorIntroLineMax, '한줄 소개');
  String? get _bioError => _lengthError(_bio, kMentorBioMax, '상세 소개');

  bool get _canSave =>
      !_saving &&
      !_uploading &&
      _current != null &&
      _highSchoolError == null &&
      _introLineError == null &&
      _bioError == null;

  List<String> get _selectedSubjectCodes => <String>[
        for (final SubjectCatalogEntry e in subjectCatalogEntries)
          if (_subjects.contains(e.code)) e.code,
      ];

  /// 웹 과목 필수 게이트 미러: 과목 0개면 구독 열림을 켤 수 없다(현재 값이 열림이어도 닫아 보낸다).
  bool get _subscriptionOpenToSend =>
      (_current?.isOpenForSubscriptions ?? false) && _subjects.isNotEmpty;

  String? _nullIfEmpty(TextEditingController c) {
    final String v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  // ── 사진 ──
  Future<void> _changeAvatar() async {
    final PickedImage? picked = await pickMentorDocument(
      context,
      widget.scanPicker,
      title: '프로필 사진',
      includeFile: false,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _uploading = true;
      _avatarError = null;
    });
    try {
      final PickedImage image = await downscaleIfOversized(picked);
      final String? invalid = validatePickedImage(image);
      if (invalid != null) {
        setState(() => _avatarError = invalid);
        return;
      }
      final String url = await _port.uploadAvatar(image);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _avatarError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeAvatar() => setState(() {
        _avatarUrl = null;
        _avatarError = null;
      });

  // ── 저장 ──
  Future<void> _openAcademicRecordChange() async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.mentorAcademicRecordChange,
      fallbackBuilder: (_) =>
          AcademicRecordChangeScreen(portOverride: widget.portOverride),
    );
  }

  Future<void> _save() async {
    final MentorOwnProfile? current = _current;
    if (current == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _port.updateOwnProfile(MentorProfileUpdate(
        // 대학·학과는 웹 readOnly(학적 변경 요청 경로) — 현재 값 재전송.
        universityName: current.universityName ?? '',
        departmentName: current.departmentName ?? '',
        highSchoolName: _nullIfEmpty(_highSchool),
        teachingSubjects: _selectedSubjectCodes,
        introLine: _nullIfEmpty(_introLine),
        bio: _nullIfEmpty(_bio),
        // 답변 스타일·구독 열림은 웹에 편집 UI 가 없다 — 현재 값 재전송(과목 게이트만 적용).
        answerStyle: current.answerStyle,
        profileImageUrl: _avatarUrl,
        isOpenForSubscriptions: _subscriptionOpenToSend,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필을 저장했어요.')),
      );
      Navigator.of(context).maybePop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '프로필 편집',
      body: FutureBuilder<MentorOwnProfile>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<MentorOwnProfile> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView(cards: 3);
          }
          if (snap.hasError || snap.data == null) {
            return AppErrorView(
              title: '프로필을 불러오지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _retry,
            );
          }
          return _form(context, snap.data!);
        },
      ),
    );
  }

  Widget _form(BuildContext context, MentorOwnProfile profile) {
    final bool busy = _saving || _uploading;
    return ListView(
      padding: AppPage.contentPadding(context),
      children: <Widget>[
        // ── 사진 + 구독 열림 ──
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _AvatarPreview(url: _avatarUrl, uploading: _uploading),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('프로필 사진', style: AppTypography.section),
                        const SizedBox(height: 2),
                        Text(
                          '학생이 멘토 목록에서 보는 사진이에요. JPG · PNG, 5MB 이하.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          children: <Widget>[
                            TextButton.icon(
                              onPressed: busy ? null : _changeAvatar,
                              icon: const Icon(Icons.photo_camera_rounded,
                                  size: 18),
                              label: Text(
                                _avatarUrl == null ? '사진 올리기' : '사진 바꾸기',
                              ),
                            ),
                            if (_avatarUrl != null)
                              TextButton(
                                onPressed: busy ? null : _removeAvatar,
                                child: const Text('사진 지우기'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_avatarError != null) ...<Widget>[
                const SizedBox(height: 8),
                AppCallout(tone: AppCalloutTone.danger, text: _avatarError!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── 학력 ──
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('학력', style: AppTypography.section),
              const SizedBox(height: 4),
              Text(
                profile.isApproved
                    ? '인증된 학교예요. 학교를 옮겼다면 학적 변경 요청으로 알려 주세요.'
                    : '학력 인증이 끝나면 학생에게 인증 표시가 붙어요.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              _LockedField(label: '대학교', value: profile.universityName),
              const SizedBox(height: AppSpacing.base),
              _LockedField(label: '학과', value: profile.departmentName),
              const SizedBox(height: 6),
              AppEntryRow(
                icon: Icons.swap_horiz_rounded,
                label: '학적 변경 요청하기',
                caption: '대학교·학과는 웹과 같이 학적 변경 요청으로만 바꿔요',
                onTap: _openAcademicRecordChange,
              ),
              const SizedBox(height: 6),
              AppField(
                label: '출신 고등학교',
                error: _highSchoolError,
                child: AppInputField(
                  controller: _highSchool,
                  hintText: '예: 한국고등학교',
                  enabled: !busy,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── 소개 ──
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('소개', style: AppTypography.section),
              const SizedBox(height: AppSpacing.base),
              AppField(
                label: '한줄 소개',
                help: '${_introLine.text.trim().length}/$kMentorIntroLineMax',
                error: _introLineError,
                child: AppInputField(
                  controller: _introLine,
                  hintText: '학생이 처음 보는 한 줄이에요',
                  enabled: !busy,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              AppField(
                label: '상세 소개',
                help: '${_bio.text.trim().length}/$kMentorBioMax',
                error: _bioError,
                child: AppInputField(
                  controller: _bio,
                  hintText: '멘토링 스타일, 경력, 강점을 적어 주세요',
                  enabled: !busy,
                  minLines: 4,
                  maxLines: 8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── 담당 과목 ──
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('담당 과목', style: AppTypography.section),
              const SizedBox(height: 4),
              Text(
                '학생은 고른 과목으로만 질문할 수 있어요. ${_subjects.length}개 선택',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (_subjects.isEmpty &&
                  (profile.isOpenForSubscriptions)) ...<Widget>[
                const SizedBox(height: 8),
                const AppCallout(
                  tone: AppCalloutTone.warning,
                  text: '담당 과목이 없으면 저장할 때 새 구독 받기가 닫혀요(웹과 동일).',
                ),
              ],
              const SizedBox(height: AppSpacing.base),
              _SubjectPicker(
                selected: _subjects,
                enabled: !busy,
                onToggle: (String code) => setState(() {
                  if (!_subjects.remove(code)) _subjects.add(code);
                  _saveError = null;
                }),
              ),
            ],
          ),
        ),
        if (_saveError != null) ...<Widget>[
          const SizedBox(height: 12),
          AppCallout(tone: AppCalloutTone.danger, text: _saveError!),
        ],
        const SizedBox(height: AppSpacing.section),
        AppPrimaryButton(
          label: _saving ? '저장 중…' : '저장하기',
          onPressed: _canSave ? _save : null,
        ),
        const SizedBox(height: 8),
        Text(
          '저장하면 프로필이 한 번에 반영돼요. 대학교·학과는 학적 변경 요청으로 바꿔요.',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.url, required this.uploading});

  final String? url;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final Widget fallback = Icon(
      Icons.person_rounded,
      size: 36,
      color: roleTheme.color,
    );
    return ClipOval(
      child: Container(
        width: 72,
        height: 72,
        color: roleTheme.tint,
        child: uploading
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : url == null
                ? fallback
                : Image.network(
                    url!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback,
                  ),
      ),
    );
  }
}

/// 정본 카탈로그를 대분류 → 소분류로 그린 칩 선택기. 코드는 화면에 노출하지 않는다.
class _SubjectPicker extends StatelessWidget {
  const _SubjectPicker({
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final Set<String> selected;
  final bool enabled;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final List<SubjectCatalogEntry> parents = <SubjectCatalogEntry>[
      for (final SubjectCatalogEntry e in subjectCatalogEntries)
        if (e.parent == null) e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final SubjectCatalogEntry parent in parents) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _SubjectChip(
                  entry: parent,
                  selected: selected.contains(parent.code),
                  enabled: enabled,
                  emphasized: true,
                  onTap: () => onToggle(parent.code),
                ),
                for (final SubjectCatalogEntry child in subjectCatalogEntries)
                  if (child.parent == parent.code)
                    _SubjectChip(
                      entry: child,
                      selected: selected.contains(child.code),
                      enabled: enabled,
                      emphasized: false,
                      onTap: () => onToggle(child.code),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({
    required this.entry,
    required this.selected,
    required this.enabled,
    required this.emphasized,
    required this.onTap,
  });

  final SubjectCatalogEntry entry;
  final bool selected;
  final bool enabled;
  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: entry.label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        child: GlassInner(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: BorderRadius.circular(AppRadius.badge),
          ringColor: selected ? roleTheme.color : null,
          child: Text(
            entry.label,
            style: AppTypography.caption.copyWith(
              fontWeight:
                  selected || emphasized ? FontWeight.w700 : FontWeight.w500,
              color: selected ? roleTheme.color : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 웹 readOnly 필드(대학교·학과) — 값만 보여주고 잠금 표시.
class _LockedField extends StatelessWidget {
  const _LockedField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final bool empty = value == null || value!.trim().isEmpty;
    return AppField(
      label: label,
      child: GlassInner(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                empty ? '미입력' : value!,
                style: AppTypography.body.copyWith(
                  color: empty ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
