import 'package:flutter/material.dart';

import '../../../../design/tokens/color_tokens.dart';

/// 숏폼 썸네일/영상 플레이스홀더. 네트워크 이미지 실패·부재 시 중립 배경으로
/// 폴백한다(깨진 이미지 금지). 이미지 실패는 이 위젯 안에서 끝나며 상세의
/// 영상 재생 경로로 전파되지 않는다.
///
/// [showPlayAffordance] 가 true 면 중앙에 재생 아이콘을 얹는다 — 상세 화면에
/// video_player 재생이 실제로 배선돼 있어(App-SF1) 거짓 어포던스가 아니다.
/// 웹 finalize 가 thumbnail_url 을 null 로 저장하는 현재 계약에서는
/// '중립 영상 배경 + 재생 어포던스'가 피드 카드의 정직한 기본 표시다.
class ThumbnailView extends StatelessWidget {
  const ThumbnailView({super.key, this.url, this.showPlayAffordance = false});

  final String? url;

  /// 중앙 재생 어포던스 — '탭하면 영상이 열림'을 약속하는 곳(피드 카드)만
  /// true. 상세의 로딩·실패 배경은 false(문구·오버레이가 상태를 설명한다).
  final bool showPlayAffordance;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (url != null && url!.isNotEmpty)
          Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _Placeholder(showIcon: !showPlayAffordance),
            // 로딩 중/테스트(네트워크 없음)에도 깨지지 않도록 폴백 유지.
            loadingBuilder: (BuildContext c, Widget child,
                    ImageChunkEvent? p) =>
                p == null ? child : _Placeholder(showIcon: !showPlayAffordance),
          )
        else
          _Placeholder(showIcon: !showPlayAffordance),
        if (showPlayAffordance)
          Center(
            child: Semantics(
              label: '숏폼 영상 열기',
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0x66000000), // 밝은 배경 대비용 스크림
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_circle_fill,
                    size: 44, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.showIcon = true});

  /// 재생 어포던스가 위에 얹히는 자리에서는 영화 아이콘을 겹치지 않는다.
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ColorTokens.elevated,
      alignment: Alignment.center,
      child: showIcon
          ? const Icon(Icons.movie_outlined, size: 36, color: ColorTokens.muted)
          : null,
    );
  }
}
