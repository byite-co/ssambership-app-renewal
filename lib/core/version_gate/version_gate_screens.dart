import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
import '../../design/widgets/primary_button.dart';
import '../../design/widgets/secondary_button.dart';
import 'store_url_policy.dart';
import 'version_policy.dart';

/// 스토어 열기 함수(테스트 주입용 — 실제 url_launcher 를 쓰지 않는 fake 주입).
typedef StoreLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultStoreLauncher(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// 스토어 버튼 공통 처리: 열기 직전 URL 재검증(https + 허용 호스트 정확 일치).
/// 검증 탈락/열기 실패 → 열지 않고 안내 스낵바만 띄운다(원문 비노출).
Future<void> _openStore({
  required BuildContext context,
  required String storeUrl,
  required StoreLauncher launcher,
}) async {
  final Uri? uri = validatedStoreUri(storeUrl);
  if (uri == null) {
    _showStoreUnavailable(context);
    return;
  }
  final bool ok = await launcher(uri);
  if (!ok && context.mounted) _showStoreUnavailable(context);
}

void _showStoreUnavailable(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('스토어를 열 수 없어요. 스토어에서 직접 업데이트해 주세요.')),
  );
}

/// 강제 업데이트 화면 — 최소 지원 빌드 미만.
///
/// ★ 진입 차단: PopScope(canPop:false) 로 뒤로가기를 막고, 앱으로 들어가는
///   어떤 동선도 제공하지 않는다(스토어 버튼뿐).
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    required this.policy,
    StoreLauncher? launcher,
  }) : _launcher = launcher ?? _defaultStoreLauncher;

  final VersionPolicy policy;
  final StoreLauncher _launcher;

  @override
  Widget build(BuildContext context) {
    final String message = policy.message.isNotEmpty
        ? policy.message
        : '새 버전으로 업데이트해야 계속 이용할 수 있어요.';
    return PopScope(
      canPop: false, // 뒤로가기로 게이트를 우회할 수 없다.
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.system_update_alt,
                      size: 44, color: ColorTokens.muted),
                  const SizedBox(height: 14),
                  const Text('업데이트가 필요해요',
                      style: AppType.title, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(message,
                      style: AppType.caption, textAlign: TextAlign.center),
                  if (policy.minimumVersionName.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    // 표기 전용 버전명 — 판정은 정수 빌드번호로 이미 끝났다.
                    Text('최소 지원 버전: ${policy.minimumVersionName}',
                        style: AppType.caption, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: '스토어에서 업데이트',
                    onPressed: () => _openStore(
                      context: context,
                      storeUrl: policy.storeUrl,
                      launcher: _launcher,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 버전 정책 조회 실패 화면 — 강제 업데이트가 아니라 '재시도' 안내다.
class VersionGateRetryScreen extends StatelessWidget {
  const VersionGateRetryScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.wifi_off_outlined,
                    size: 44, color: ColorTokens.muted),
                const SizedBox(height: 14),
                const Text('잠시 확인이 필요해요',
                    style: AppType.title, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('버전 정보를 확인하지 못했어요. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
                    style: AppType.caption, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                SecondaryButton(label: '재시도', onPressed: onRetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 권장 업데이트 배너 — 최소는 충족, 최신 빌드가 더 높을 때. 닫기 가능(실행당 1회).
class RecommendUpdateBanner extends StatelessWidget {
  const RecommendUpdateBanner({
    super.key,
    required this.policy,
    required this.onDismiss,
    StoreLauncher? launcher,
  }) : _launcher = launcher ?? _defaultStoreLauncher;

  final VersionPolicy policy;
  final VoidCallback onDismiss;
  final StoreLauncher _launcher;

  @override
  Widget build(BuildContext context) {
    final String message =
        policy.message.isNotEmpty ? policy.message : '새 버전이 나왔어요.';
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            color: ColorTokens.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ColorTokens.border),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1A0F172A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(message, style: AppType.body)),
              TextButton(
                onPressed: () => _openStore(
                  context: context,
                  storeUrl: policy.storeUrl,
                  launcher: _launcher,
                ),
                child: const Text('업데이트'),
              ),
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 게이트 조회 중 로딩(스플래시와 같은 톤 — 진입 보류).
class VersionGateLoading extends StatelessWidget {
  const VersionGateLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: ColorTokens.accent)),
    );
  }
}
