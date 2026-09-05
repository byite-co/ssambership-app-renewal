import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app_scope.dart';
import '../../app/entry_guard.dart';
import '../../design/role_theme.dart' show RoleTheme;
import '../../design/tokens/app_spacing.dart';
import '../../design/tokens/app_typography.dart';
import '../../design/widgets/app_background.dart';
import '../../design/widgets/app_input_field.dart';
import '../../design/widgets/app_primary_button.dart';
import '../../design/widgets/app_secondary_button.dart';
import '../../design/widgets/glass_card.dart';
import '../../design/widgets/glass_inner.dart';
import '../../shared/constants/app_constants.dart';
import '../dev/dev_flags.dart';
import '../../shared/errors/friendly_error.dart';

/// 로그인 화면(design-v3 §5-1) — 이메일+비밀번호 로그인 / 둘러보기(게스트) / 웹 가입 안내.
/// 주색은 로그인 역할(RoleTheme)이 정한다 — 학생 파랑 · 멘토 초록.
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
      await AppScope.of(context).auth.signInWithPassword(
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
    AppScope.of(context).auth.enterAsGuest();
    context.go(EntryGuard.home);
  }

  @override
  Widget build(BuildContext context) {
    final String? notice =
        GoRouterState.of(context).uri.queryParameters['notice'];
    final bool loginRequired = notice == 'login_required';

    return AppBackground(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenH, vertical: 32),
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
                      style: AppTypography.title,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    const Text(
                      '질문 멘토링, 모바일에서',
                      style: AppTypography.captionSecondary,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s24),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (loginRequired) ...<Widget>[
                            const _NoticeBanner(),
                            const SizedBox(height: AppSpacing.s16),
                          ],
                          AppInputField(
                            controller: _email,
                            labelText: '이메일',
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const <String>[
                              AutofillHints.email,
                              AutofillHints.username,
                            ],
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          AppInputField(
                            controller: _password,
                            labelText: '비밀번호',
                            obscureText: true,
                            autofillHints: const <String>[
                              AutofillHints.password
                            ],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _signIn(),
                            errorText: _error,
                          ),
                          const SizedBox(height: AppSpacing.s20),
                          AppPrimaryButton(
                            label: _loading ? '로그인 중…' : '로그인',
                            onPressed: _loading ? null : _signIn,
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          AppSecondaryButton(
                            label: '둘러보기',
                            onPressed: _loading ? null : _browse,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    // 가입은 웹에서만 — 확정된 가입 경로가 없어 링크(어포던스)
                    // 없이 순수 안내만 둔다(죽은 버튼 금지, P0-4).
                    // 웹 가입 라우트 확정 시 web_bridge 에 signupPath 를 추가해
                    // 버튼으로 승격한다.
                    const Text(
                      '아직 회원이 아니신가요? 회원가입은 웹에서 진행돼요.',
                      style: AppTypography.captionSecondary,
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
      ),
    );
  }
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
    final Color role = RoleTheme.of(context).color;
    return GlassInner(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ringColor: role.withValues(alpha: 0.35),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_rounded, size: 18, color: role),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('로그인이 필요해요', style: AppTypography.body),
          ),
        ],
      ),
    );
  }
}
