import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/auth/app_auth.dart';
import '../../design/role_theme.dart' show RoleTheme;
import '../../design/tokens/app_spacing.dart';
import '../../design/tokens/app_typography.dart';
import '../../design/widgets/app_background.dart';
import '../../design/widgets/app_primary_button.dart';
import '../../design/widgets/app_secondary_button.dart';

/// 차단 화면: 계정 정지/제한(banned·suspended), 탈퇴 진행·완료, 조회 실패(일시 오류),
/// 관리자 계정 등으로 앱 이용 불가일 때. 사유 안내는 상태별 문구(blockedMessage)로
/// 구분되고, '일시 조회 실패'(isRecoverableBlock)일 때만 재시도 버튼을 노출한다.
/// 탈퇴 진행·완료는 재시도 버튼 없이 재로그인·재가입 안내 문구만 보여준다(자동 재시도 없음).
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppAuth auth = AppScope.of(context).auth; // A-2: 싱글턴 직접 참조 0.
    final bool retryable = auth.isRecoverableBlock;
    final RoleTheme roleTheme = RoleTheme.of(context);
    return AppBackground(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: roleTheme.tint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          retryable
                              ? Icons.wifi_off_outlined
                              : Icons.lock_outline,
                          size: 36,
                          color: roleTheme.color,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    Text(
                      // 일시 오류는 '이용 불가'처럼 보이지 않게 제목부터 구분한다.
                      retryable ? '잠시 확인이 필요해요' : '앱을 이용할 수 없어요',
                      style: AppTypography.title,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      auth.blockedMessage,
                      style: AppTypography.captionSecondary,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s24),
                    if (retryable) ...<Widget>[
                      AppSecondaryButton(
                        label: '다시 시도',
                        onPressed: () => auth.reloadProfile(),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                    AppPrimaryButton(
                      label: '로그아웃',
                      onPressed: () => auth.signOut(),
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
