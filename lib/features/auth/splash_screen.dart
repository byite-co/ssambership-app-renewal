import 'package:flutter/material.dart';

import '../../shared/constants/app_constants.dart';

/// 부팅 스플래시(세션 복원/프로필 로드 중). 로드 끝나면 진입 가드가 이동시킨다.
/// 브랜드 로고 + 로딩 인디케이터(배경은 앱 루트 그라디언트).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image(
              image: AssetImage(AppConstants.brandLogoAsset),
              width: 96,
              height: 96,
              filterQuality: FilterQuality.medium,
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
