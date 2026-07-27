import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/web_bridge/shortform_compose_bridge.dart';
import '../../../../core/web_bridge/web_bridge_config.dart';
import '../../../../core/web_bridge/web_session_hygiene.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';

/// 멘토 숏폼 작성 — 비결제 전용 인앱 WebView(`shortform_create` 단일 목적).
///
/// 흐름: 쿠키 정리 → 웹 `/api/app-session/bootstrap` 에 form-urlencoded POST
/// (access/refresh 토큰은 body 로만) → 303 → 앱 전용 작성 표면. 완료 브릿지
/// URL 을 intercept 해 [ShortformComposeResult] 로 pop 한다.
///
/// ★ 실제 write(INSERT·Storage 업로드)는 전부 웹 작성기(PR #42 계약)가 수행한다 —
///   앱에는 숏폼 INSERT repository·네이티브 업로더가 없다(Commerce-Zero 와 동일한
///   단일 정본 원칙).
/// ★ 탐색 allowlist·완료 판정은 [ShortformComposeBridge](순수, 단위테스트됨).
class ShortformComposeScreen extends StatefulWidget {
  const ShortformComposeScreen({super.key});

  @override
  State<ShortformComposeScreen> createState() => _ShortformComposeScreenState();
}

enum _ComposeState { needLogin, loading, ready, error }

class _ShortformComposeScreenState extends State<ShortformComposeScreen> {
  final ShortformComposeBridge _bridge =
      ShortformComposeBridge(baseUrl: WebBridgeConfig.baseUrl);

  WebViewController? _controller;
  _ComposeState _state = _ComposeState.loading;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // 화면 수명 = WebView 세션 수명: 닫을 때 쿠키를 정리해 재사용을 막는다.
    // (진입 시에도 정리하므로 이 정리가 실패해도 다음 진입이 안전하다)
    WebSessionHygiene.clear();
    super.dispose();
  }

  Future<void> _start() async {
    final Session? session = SupabaseInit.clientOrNull?.auth.currentSession;
    final String? refreshToken = session?.refreshToken;
    if (session == null || refreshToken == null || refreshToken.isEmpty) {
      // currentSession 없음 → WebView 를 만들지 않고 로그인 유도.
      setState(() => _state = _ComposeState.needLogin);
      return;
    }
    if (!WebBridgeConfig.isConfigured) {
      setState(() {
        _state = _ComposeState.error;
        _errorMessage = '웹 주소가 설정되지 않았어요. 앱을 업데이트해 주세요.';
      });
      return;
    }

    // 이전 사용자(계정 전환 포함)의 쿠키가 남아 있지 않게 먼저 정리한다.
    await WebSessionHygiene.clear();
    if (!mounted) return;

    final WebViewController controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _decideNavigation,
          onPageFinished: (_) {
            if (mounted && _state == _ComposeState.loading) {
              setState(() => _state = _ComposeState.ready);
            }
          },
          onWebResourceError: (WebResourceError error) {
            // 서브리소스 오류로 화면 전체를 죽이지 않는다 — 메인 프레임만.
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _state = _ComposeState.error;
                _errorMessage = '페이지를 불러오지 못했어요. 네트워크를 확인해 주세요.';
              });
            }
          },
        ),
      );

    // Android: <input type=file> → 시스템 파일 선택기(단일 영상, mp4/mov/webm).
    // 전체 저장소 권한을 요청하지 않는다(SAF 경유). iOS(WKWebView)는 기본 지원.
    final Object platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      await platformController.setOnShowFileSelector(_onShowFileSelector);
    }

    // 토큰은 URL 이 아니라 POST body 로만. Android postUrl 은 헤더를 무시하고
    // form-urlencoded 로 보내므로 헤더 적용 여부에 의존하지 않는다(iOS 는 명시 헤더).
    await controller.loadRequest(
      _bridge.bootstrapUri,
      method: LoadRequestMethod.post,
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: ShortformComposeBridge.buildBootstrapBody(
        accessToken: session.accessToken,
        refreshToken: refreshToken,
      ),
    );

    if (!mounted) return;
    setState(() => _controller = controller);
  }

  NavigationDecision _decideNavigation(NavigationRequest request) {
    final Uri? uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    // 완료 브릿지: kind/result enum 이 맞을 때만 pop(로컬 가짜 게시물 생성 없음 —
    // 피드는 복귀 후 서버 재조회).
    final ShortformComposeResult? done = _bridge.completionOf(uri);
    if (done != null) {
      if (mounted) Navigator.of(context).pop(done);
      return NavigationDecision.prevent;
    }

    // allowlist 밖(외부 호스트·evil suffix·결제/구독/충전 경로·비 https)은 전부 차단.
    return _bridge.isAllowedNavigation(uri)
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  /// Android 파일 선택 — 단일 영상(mp4/mov/webm)만. 취소 시 빈 목록(크래시 없음).
  Future<List<String>> _onShowFileSelector(FileSelectorParams params) async {
    try {
      // file_picker 11.x: 정적 FilePicker.pickFiles(구 .platform 싱글턴 제거됨).
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['mp4', 'mov', 'webm'],
      );
      final String? path = result?.files.single.path;
      if (path == null) return const <String>[];
      return <String>[Uri.file(path).toString()];
    } catch (_) {
      return const <String>[];
    }
  }

  void _retry() {
    setState(() {
      _state = _ComposeState.loading;
      _controller = null;
    });
    _start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('숏폼 작성'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '취소',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    switch (_state) {
      case _ComposeState.needLogin:
        return _Notice(
          icon: Icons.lock_outline_rounded,
          title: '로그인이 필요해요',
          message: '로그인하면 앱 안에서 영상을 선택해 숏폼을 올릴 수 있어요.',
          actionLabel: '닫기',
          onAction: () => Navigator.of(context).maybePop(),
        );
      case _ComposeState.error:
        return _Notice(
          icon: Icons.wifi_off_rounded,
          title: '불러오지 못했어요',
          message: _errorMessage,
          actionLabel: '다시 시도',
          onAction: _retry,
        );
      case _ComposeState.loading:
      case _ComposeState.ready:
        final WebViewController? controller = _controller;
        if (controller == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Stack(
          children: <Widget>[
            WebViewWidget(controller: controller),
            if (_state == _ComposeState.loading)
              const Center(child: CircularProgressIndicator()),
          ],
        );
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 46, color: ColorTokens.muted),
            const SizedBox(height: 12),
            Text(title, style: AppType.title, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: AppType.caption, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
