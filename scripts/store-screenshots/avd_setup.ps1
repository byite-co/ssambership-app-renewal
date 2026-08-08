# avd_setup.ps1 — 스토어 스크린샷용 AVD 생성·설정 (Windows PowerShell)
#
# 하는 일:
#   1) android/app/build.gradle.kts 에서 targetSdk 를 읽는다
#   2) sdkmanager 로 system-images;android-<targetSdk>;google_apis;x86_64 설치
#      (google_apis_playstore 는 adb root 가 막혀 데모 모드 등에 제약 → 금지)
#   3) avdmanager 로 AVD "Ssambeship_Store_1080x1920" 생성
#   4) config.ini 를 1080x1920 / 420dpi 로 강제 수정 후 결과 출력
#
# 사용법:  powershell -ExecutionPolicy Bypass -File scripts\store-screenshots\avd_setup.ps1

$ErrorActionPreference = "Stop"

$AvdName = "Ssambeship_Store_1080x1920"

# ---------- 0. Android SDK 위치 ----------
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
if (-not (Test-Path $sdk)) {
    Write-Error "Android SDK 를 찾을 수 없습니다: $sdk`nANDROID_HOME 환경변수를 설정하거나 SDK 를 설치하세요."
}
Write-Host "[SDK] $sdk"

$sdkmanager = Join-Path $sdk "cmdline-tools\latest\bin\sdkmanager.bat"
$avdmanager = Join-Path $sdk "cmdline-tools\latest\bin\avdmanager.bat"
if (-not (Test-Path $sdkmanager)) {
    Write-Error "sdkmanager 가 없습니다: $sdkmanager`nAndroid Studio > SDK Manager > SDK Tools 에서 'Android SDK Command-line Tools (latest)' 를 설치하세요."
}

# ---------- 1. targetSdk 읽기 ----------
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$gradleKts = Join-Path $repoRoot "android\app\build.gradle.kts"
$gradle    = Join-Path $repoRoot "android\app\build.gradle"
$gradleFile = if (Test-Path $gradleKts) { $gradleKts } elseif (Test-Path $gradle) { $gradle } else {
    Write-Error "android/app/build.gradle(.kts) 를 찾을 수 없습니다 (repo: $repoRoot)"
}

$targetSdk = $null
foreach ($line in Get-Content $gradleFile) {
    if ($line -match 'targetSdk(Version)?\s*=?\s*(\d+)') { $targetSdk = [int]$Matches[2]; break }
}
if (-not $targetSdk) {
    Write-Warning "targetSdk 를 파싱하지 못해 36 으로 폴백합니다 ($gradleFile 확인 필요)"
    $targetSdk = 36
}
Write-Host "[targetSdk] $targetSdk  (from $gradleFile)"

$sysImage = "system-images;android-$targetSdk;google_apis;x86_64"
Write-Host "[system image] $sysImage"

# ---------- 2. 시스템 이미지 설치 ----------
Write-Host "`n=== sdkmanager: 시스템 이미지 설치 (최초 1회는 라이선스 수락 필요) ==="
& $sdkmanager --install $sysImage "platform-tools" "emulator"
if ($LASTEXITCODE -ne 0) {
    Write-Error "sdkmanager 설치 실패. 'sdkmanager --licenses' 로 라이선스를 먼저 수락한 뒤 다시 실행하세요."
}

# ---------- 3. AVD 생성 ----------
$avdDir = Join-Path $env:USERPROFILE ".android\avd\$AvdName.avd"
if (Test-Path $avdDir) {
    $answer = Read-Host "AVD '$AvdName' 이 이미 존재합니다. 삭제 후 재생성할까요? (y/N)"
    if ($answer -eq 'y') {
        & $avdmanager delete avd -n $AvdName
    } else {
        Write-Host "기존 AVD 를 유지하고 config.ini 수정만 진행합니다."
    }
}

if (-not (Test-Path $avdDir)) {
    Write-Host "`n=== avdmanager: AVD 생성 ==="
    # 커스텀 하드웨어 프로필 질문("Do you wish to create a custom hardware profile?")에 no 자동 응답
    "no" | & $avdmanager create avd -n $AvdName -k $sysImage -d "pixel_5"
    if ($LASTEXITCODE -ne 0) { Write-Error "avdmanager create avd 실패" }
}

# ---------- 4. config.ini 강제 수정 ----------
# density 는 반드시 420: 1080px / (420/160) = 411dp (의도한 논리 폭).
# 480 이면 360dp 로 좁아지고 320 이면 540dp 로 넓어져 레이아웃이 달라진다.
$configIni = Join-Path $avdDir "config.ini"
if (-not (Test-Path $configIni)) { Write-Error "config.ini 가 없습니다: $configIni" }

$overrides = [ordered]@{
    "hw.lcd.width"   = "1080"
    "hw.lcd.height"  = "1920"
    "hw.lcd.density" = "420"
    "hw.keyboard"    = "yes"
    "skin.name"      = "1080x1920"
    "skin.dynamic"   = "yes"
    "hw.gpu.enabled" = "yes"
    "hw.gpu.mode"    = "auto"
}
# skin.path 가 기존 기기 스킨을 가리키면 lcd 값보다 우선되므로 함께 정리한다.
$lines = Get-Content $configIni | Where-Object { $_ -notmatch '^\s*skin\.path\s*=' }
foreach ($key in $overrides.Keys) {
    $pattern = "^\s*$([regex]::Escape($key))\s*="
    $lines = $lines | Where-Object { $_ -notmatch $pattern }
    $lines += "$key=$($overrides[$key])"
}
Set-Content -Path $configIni -Value $lines -Encoding ASCII

Write-Host "`n=== config.ini 반영 결과 ($configIni) ==="
Get-Content $configIni | Where-Object {
    $_ -match '^(hw\.lcd\.|hw\.keyboard|skin\.|hw\.gpu\.)'
} | ForEach-Object { Write-Host "  $_" }

Write-Host "`n[OK] AVD '$AvdName' 준비 완료."
Write-Host "부팅:  emulator -avd $AvdName"
Write-Host "확인:  adb shell wm size   → Physical size: 1080x1920"
Write-Host "       adb shell wm density → Physical density: 420"
