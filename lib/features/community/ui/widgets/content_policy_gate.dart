import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design/tokens/app_typography.dart';

/// 콘텐츠 게시 전 정책 동의 게이트(UGC 규정 준수 — 게시글·댓글 공통).
///
/// ★ 앱스토어 심사(Apple 1.2 / Google UGC): 사용자가 콘텐츠를 만들기 전에
///   '불쾌·불법·음란 콘텐츠 무관용' 정책에 **능동 동의**하도록 요구된다.
///   가입이 웹 전용이라 인앱 EULA 접점이 없으므로, 최초 게시 동선에서 1회 동의를 받는다.
///
/// C13: 동의는 **기기에 영속화**된다(shared_preferences) — 앱 재실행마다
/// 재동의를 요구하던 인메모리 한계 제거. 저장 실패는 조용히 무시(그 실행은
/// 인메모리로만 기억 — 다음 실행에 다시 노출될 뿐, 게시 흐름은 안 막는다).
class ContentPolicyGate {
  ContentPolicyGate._();

  /// 영속 키(규정 문구가 실질 변경되면 버전을 올려 재동의를 받는다).
  static const String prefsKey = 'content_policy_agreed_v1';

  /// 이번 실행에서 동의 확인됨(중복 노출·중복 디스크 읽기 방지). 테스트에서 리셋 가능.
  static bool agreedThisSession = false;

  /// 게시 전 정책 동의를 보장한다. 이미 동의했으면 즉시 true.
  /// 다이얼로그에서 '동의' → true, 취소/바깥 탭 → false.
  static Future<bool> ensureAgreed(BuildContext context) async {
    if (agreedThisSession) return true;
    // 기기 저장분 확인 — 있으면 노출 없이 통과.
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(prefsKey) ?? false) {
        agreedThisSession = true;
        return true;
      }
    } catch (_) {
      // 저장소 접근 실패 → 인메모리 게이트로만 진행.
    }
    if (!context.mounted) return false;
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext ctx) => const _ContentPolicyDialog(),
    );
    if (ok == true) {
      agreedThisSession = true;
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool(prefsKey, true);
      } catch (_) {
        // 영속화 실패 — 이번 실행은 인메모리로 기억, 다음 실행에 재노출.
      }
      return true;
    }
    return false;
  }
}

class _ContentPolicyDialog extends StatelessWidget {
  const _ContentPolicyDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('커뮤니티 이용 규정', style: AppTypography.section),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '쌤버십은 불쾌하거나 불법·음란·폭력적이거나 타인을 비방·괴롭히는 콘텐츠를 '
            '허용하지 않아요. 위반 콘텐츠는 사전 통지 없이 삭제되고 계정이 제한될 수 있어요.',
            style: AppTypography.body,
          ),
          const SizedBox(height: 12),
          Text(
            '부적절한 게시물은 신고하거나 작성자를 차단할 수 있어요. '
            '게시하면 위 규정에 동의하는 것으로 간주돼요.',
            style: AppTypography.captionSecondary,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('동의하고 계속'),
        ),
      ],
    );
  }
}
