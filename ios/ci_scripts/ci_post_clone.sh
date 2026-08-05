#!/bin/sh
# Xcode Cloud post-clone bootstrap — Flutter SwiftPM 프로젝트 준비 스크립트.
#
# 왜 필요한가: Xcode Cloud 는 clean clone 직후 Xcode dependency resolution 을
# 수행하는데, Runner 가 참조하는 local Swift package
# (ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage)는
# Flutter 가 생성하는 ignored/ephemeral 산출물이라 저장소에 없다.
# 이 스크립트가 resolution 이전(ci_post_clone 단계)에 Flutter 를 준비하고
# 해당 패키지를 생성한다. archive 자체는 이후 Xcode Cloud 가 수행한다.
#
# 필수 Xcode Cloud 환경변수(Workflow > Environment > Secret 권장):
#   SUPABASE_URL       — 운영 프로젝트 URL (아래 EXPECTED_SUPABASE_URL 과 일치해야 함)
#   SUPABASE_ANON_KEY  — 운영 anon key (값은 어떤 로그에도 출력하지 않는다)
#
# 주의: set -x 금지(secret 노출). 스토어 빌드는 기능 플래그 기본값 유지 —
# IQ_CREATE_ENABLED 등 dart-define 주입 금지(계약: xcode_cloud_bootstrap_contract_test).
set -eu

FLUTTER_PIN="3.44.6"
EXPECTED_SUPABASE_URL="https://lbeqxarxothkmzqvpudy.supabase.co"

# 저장소 루트: 이 스크립트는 항상 <repo>/ios/ci_scripts/ 에 있다.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
echo "==> repo root: $REPO_ROOT"

# ── 1. Flutter ${FLUTTER_PIN} 준비 ──────────────────────────────────────────
# 시스템 flutter 가 정확히 핀 버전이면 재사용, 아니면 홈 캐시에 태그로 클론.
installed_flutter_version() {
  command -v flutter >/dev/null 2>&1 || return 1
  flutter --version 2>/dev/null | awk '/^Flutter/ {print $2; exit}'
}

if [ "$(installed_flutter_version || true)" = "$FLUTTER_PIN" ]; then
  echo "==> using preinstalled Flutter $FLUTTER_PIN"
else
  FLUTTER_CACHE="$HOME/flutter-$FLUTTER_PIN"
  if [ ! -x "$FLUTTER_CACHE/bin/flutter" ]; then
    echo "==> cloning Flutter $FLUTTER_PIN into $FLUTTER_CACHE"
    rm -rf "$FLUTTER_CACHE"
    git clone --depth 1 --branch "$FLUTTER_PIN" \
      https://github.com/flutter/flutter.git "$FLUTTER_CACHE"
  else
    echo "==> reusing cached Flutter at $FLUTTER_CACHE"
  fi
  PATH="$FLUTTER_CACHE/bin:$PATH"
  export PATH
fi

FLUTTER_ROOT="$(dirname "$(dirname "$(command -v flutter)")")"
export FLUTTER_ROOT

flutter --version

ACTUAL_VERSION="$(installed_flutter_version)"
if [ "$ACTUAL_VERSION" != "$FLUTTER_PIN" ]; then
  echo "ERROR: Flutter version mismatch — expected $FLUTTER_PIN, got $ACTUAL_VERSION." >&2
  exit 1
fi

flutter --disable-analytics >/dev/null 2>&1 || true
flutter config --enable-swift-package-manager

# ── 2. 운영 .env 생성 (fail closed — 값은 절대 출력하지 않는다) ─────────────
: "${SUPABASE_URL:?SUPABASE_URL is required (set it as an Xcode Cloud secret environment variable)}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is required (set it as an Xcode Cloud secret environment variable)}"

case "$SUPABASE_URL" in
  *localhost*|*127.0.0.1*)
    echo "ERROR: SUPABASE_URL points at a local dev instance — store builds must use production." >&2
    exit 1
    ;;
esac

if [ "$SUPABASE_URL" != "$EXPECTED_SUPABASE_URL" ]; then
  echo "ERROR: SUPABASE_URL does not match the expected production project." >&2
  exit 1
fi

umask 077
{
  printf 'SUPABASE_URL=%s\n' "$SUPABASE_URL"
  printf 'SUPABASE_URL_LAN=\n'
  printf 'SUPABASE_ANON_KEY=%s\n' "$SUPABASE_ANON_KEY"
} > "$REPO_ROOT/.env"
chmod 600 "$REPO_ROOT/.env"
echo "==> .env created (production URL verified; values not logged)"

# ── 3. 의존성 해석 + iOS generated config / ephemeral Swift package 생성 ────
flutter pub get

flutter precache --ios

# config-only: xcodebuild 없이 Generated.xcconfig 와
# FlutterGeneratedPluginSwiftPackage 등 iOS 빌드 전제 산출물만 생성한다.
# (옵션 지원은 Flutter 3.44.6 flutter_tools 소스로 검증 — 계약 테스트 참조.)
flutter build ios --release --config-only --no-codesign

# ── 4. 생성 검증 — 실패 시 원인 명시 후 중단 ────────────────────────────────
GENERATED_PACKAGE="$REPO_ROOT/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
if [ ! -f "$GENERATED_PACKAGE" ]; then
  echo "ERROR: FlutterGeneratedPluginSwiftPackage was not generated at:" >&2
  echo "  $GENERATED_PACKAGE" >&2
  echo "Xcode dependency resolution will fail. Check the flutter build output above." >&2
  exit 1
fi
echo "==> generated Swift package present: $GENERATED_PACKAGE"

GENERATED_XCCONFIG="$REPO_ROOT/ios/Flutter/Generated.xcconfig"
if [ ! -f "$GENERATED_XCCONFIG" ]; then
  echo "ERROR: ios/Flutter/Generated.xcconfig was not generated." >&2
  exit 1
fi
echo "==> Generated.xcconfig present"

echo "Xcode Cloud Flutter bootstrap complete."
