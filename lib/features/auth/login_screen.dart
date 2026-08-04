import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/entry_guard.dart';
import '../../core/auth/auth_service.dart';
import '../../design/shape_tokens.dart';
import '../../design/spacing_tokens.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
import '../../design/widgets/primary_button.dart';
import '../../design/widgets/secondary_button.dart';
import '../../shared/constants/app_constants.dart';
import '../dev/dev_flags.dart';
import '../../shared/errors/friendly_error.dart';

/// 로그인 화면. 이메일+비밀번호 로그인 / 둘러보기(게스트) / 웹 가입 안내(자리).
///
/// ★ 컴패니언 앱: 회원가입 폼 없음(가입은 웹). 결제·가격 UI 없음(Commerce-Zero).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithPassword(
        email: _email.text,
        password: _password.text,
      );
      // 성공 시 router redirect 가 /home 또는 /blocked 로 이동시킨다.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } catch (_) {
      if (mounted) {
        setState(() => _error = '로그인 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _browse() {
    AuthService.instance.enterAsGuest();
    context.go(EntryGuard.home);
  }

  @override
  Widget build(BuildContext context) {
    final String? notice =
        GoRouterState.of(context).uri.queryParameters['notice'];
    final bool loginRequired = notice == 'login_required';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: _BrandSymbol()),
                  const SizedBox(height: AppSpacing.s16),
                  const Text(
                    AppConstants.appDisplayName,
                    style: AppType.display,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  const Text(
                    '질문 멘토링, 모바일에서',
                    style: AppType.caption,
                    textAlign: TextAlign.center,
                  ),
                  if (loginRequired) ...<Widget>[
                    const SizedBox(height: AppSpacing.s24),
                    const _NoticeBanner(),
                  ],
                  const SizedBox(height: AppSpacing.s32),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const <String>[
                      AutofillHints.email,
                      AutofillHints.username,
                    ],
                    textInputAction: TextInputAction.next,
                    style: AppType.body,
                    decoration: _decoration('이메일'),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const <String>[AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _signIn(),
                    style: AppType.body,
                    decoration: _decoration('비밀번호'),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      _error!,
                      style: AppType.caption.copyWith(
                        color: ColorTokens.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s24),
                  PrimaryButton(
                    label: _loading ? '로그인 중…' : '로그인',
                    onPressed: _loading ? null : _signIn,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  SecondaryButton(
                    label: '둘러보기',
                    neutral: true,
                    onPressed: _loading ? null : _browse,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  // 가입은 웹에서만 — 확정된 가입 경로가 없어 링크(어포던스)
                  // 없이 순수 안내만 둔다(죽은 버튼 금지, P0-4).
                  // 웹 가입 라우트 확정 시 web_bridge 에 signupPath 를 추가해
                  // 버튼으로 승격한다.
                  const Text(
                    '아직 회원이 아니신가요? 회원가입은 웹에서 진행돼요.',
                    style: TextStyle(color: ColorTokens.secondary),
                    textAlign: TextAlign.center,
                  ),
                  // ★ 개발 전용 — 출시 빌드에서는 노출되지 않는다.
                  if (kDevToolsEnabled)
                    TextButton(
                      onPressed: () => context.go(EntryGuard.devGallery),
                      child: const Text('위젯 갤러리 (개발용)'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: AppType.caption,
        filled: true,
        fillColor: ColorTokens.elevated,
        border: OutlineInputBorder(
          borderRadius: AppShape.inputRadius,
          borderSide: BorderSide.none,
        ),
      );
}

/// 브랜드 심볼(단 하나) — 확정 앱 로고(졸업모자 + 말풍선). 과한 장식 금지.
/// 로고 PNG 자체가 둥근 사각·여백을 포함하므로 별도 배경/장식 없이 이미지만 표시.
class _BrandSymbol extends StatelessWidget {
  const _BrandSymbol();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppConstants.brandLogoAsset,
      width: 76,
      height: 76,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// '로그인이 필요해요' 안내 배너(보호 탭을 게스트가 눌렀을 때).
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ColorTokens.elevated,
        borderRadius: AppShape.inputRadius,
        border: Border.all(color: ColorTokens.border),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.info_rounded, size: 18, color: ColorTokens.muted),
          SizedBox(width: 10),
          Expanded(
            child: Text('로그인이 필요해요', style: AppType.body),
          ),
        ],
      ),
    );
  }
}
