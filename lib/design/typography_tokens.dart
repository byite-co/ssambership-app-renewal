import 'package:flutter/material.dart';

import 'tokens/color_tokens.dart';

/// 타입 스케일(단일 소스). "AI 기본값" 제거 토대 4가지 중 '타이포'.
///
/// 폰트 패밀리는 [ThemeData.fontFamily]=Pretendard 로 전역 주입되므로 여기서는
/// 원칙적으로 family 를 지정하지 않는다(크기·굵기·색·수치 정렬만 시맨틱으로 정의).
/// ★ 예외 — [display]: AppBar 의 `titleTextStyle` 처럼 **DefaultTextStyle 의 루트**로
///   쓰이는 스타일은 테마 family 를 상속받지 못한다(2026-09 골든으로 확인 — 실기기에서도
///   시스템 폰트로 그려지고 있었다). 그런 스타일에는 [fontFamily] 를 명시한다.
/// 위계: display(화면 타이틀) > title(섹션) > cardTitle(카드제목) > body(본문) > caption(보조).
/// 위계 대비 강화: 제목은 확실히 크고 굵게, 메타(caption)는 확실히 작고 흐리게.
/// 숫자 정렬(A-5): 전 스타일에 고정폭 숫자(tabular figures) — 요금·캐시·날짜·카운트 자릿수 정렬.
/// number 는 잔여·금액 등 큰 수치 전용.
class AppType {
  AppType._();

  /// 앱 전역 폰트 패밀리(정적 4종 400/500/600/700 등록 — pubspec `fonts:`).
  /// 테마([ThemeData.fontFamily])와 DefaultTextStyle 루트 스타일이 같은 값을 쓴다.
  static const String fontFamily = 'Pretendard';

  /// 고정폭 숫자(tabular figures) — 모든 스타일 공통 주입(A-5).
  static const List<FontFeature> _tnum = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// 화면 타이틀(앱바·페이지 헤더) — 24 / w700.
  static const TextStyle display = TextStyle(
    fontFamily: fontFamily, // AppBar titleTextStyle 루트 — 테마 family 미상속(위 주석)
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: ColorTokens.primary,
    fontFeatures: _tnum,
  );

  /// 섹션 제목 — 17 / w600.
  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: ColorTokens.primary,
    fontFeatures: _tnum,
  );

  /// 카드 제목(섹션보다 한 단계 작게) — 15 / w600.
  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: ColorTokens.primary,
    fontFeatures: _tnum,
  );

  /// 본문 — 14 / w400.
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: ColorTokens.primary,
    fontFeatures: _tnum,
  );

  /// 보조 텍스트(캡션·메타) — 12 / w400 / #64748B.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: ColorTokens.muted, // #64748B
    fontFeatures: _tnum,
  );

  /// 수치(잔여·금액 등) — 26 / w700 / 고정폭 숫자(tabular figures).
  static const TextStyle number = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: ColorTokens.primary,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
