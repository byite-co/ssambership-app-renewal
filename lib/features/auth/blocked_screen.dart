import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
import '../../design/widgets/primary_button.dart';
import '../../design/widgets/secondary_button.dart';

/// 차단 화면: 계정 정지/제한(banned·suspended), 탈퇴 진행·완료, 조회 실패(일시 오류),
/// 관리자 계정 등으로 앱 이용 불가일 때. 사유 안내는 상태별 문구(blockedMessage)로
/// 구분되고, '일시 조회 실패'(isRecoverableBlock)일 때만 재시도 버튼을 노출한다.
/// 탈퇴 진행·완료는 재시도 버튼 없이 재로그인·재가입 안내 문구만 보여준다(자동 재시도 없음).
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthService auth = AuthService.instance;
    final bool retryable = auth.isRecoverableBlock;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  retryable ? Icons.wifi_off_outlined : Icons.lock_outline,
                  size: 44,
                  color: ColorTokens.muted,
                ),
                const SizedBox(height: 14),
                Text(
                  // 일시 오류는 '이용 불가'처럼 보이지 않게 제목부터 구분한다.
                  retryable ? '잠시 확인이 필요해요' : '앱을 이용할 수 없어요',
                  style: AppType.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  auth.blockedMessage,
                  style: AppType.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (retryable) ...<Widget>[
                  SecondaryButton(
                    label: '다시 시도',
                    onPressed: () => auth.reloadProfile(),
                  ),
                  const SizedBox(height: 10),
                ],
                PrimaryButton(
                  label: '로그아웃',
                  onPressed: () => auth.signOut(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
