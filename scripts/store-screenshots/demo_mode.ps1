# demo_mode.ps1 — 상태바 데모 모드 on/off (스토어 스크린샷용)
#
# on:  시계 09:30 고정 · 배터리 100%(비충전) · Wi-Fi/모바일 풀시그널 · 알림 아이콘 숨김
# off: 데모 모드 해제 (실제 상태바 복귀)
#
# 사용법:
#   powershell -ExecutionPolicy Bypass -File scripts\store-screenshots\demo_mode.ps1 on
#   powershell -ExecutionPolicy Bypass -File scripts\store-screenshots\demo_mode.ps1 off
#
# 여러 기기가 연결돼 있으면 $env:ANDROID_SERIAL 로 대상 지정.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("on", "off")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

function Invoke-Adb {
    param([string[]]$AdbArgs)
    & adb shell @AdbArgs
    if ($LASTEXITCODE -ne 0) { Write-Error "adb shell $($AdbArgs -join ' ') 실패" }
}

# adb 연결 확인
& adb get-state *> $null
if ($LASTEXITCODE -ne 0) { Write-Error "연결된 기기/에뮬레이터가 없습니다. 에뮬레이터를 먼저 부팅하세요." }

if ($Mode -eq "on") {
    Write-Host "[demo mode] ON — 시계 09:30 / 배터리 100% / 풀시그널 / 알림 숨김"
    Invoke-Adb @("settings", "put", "global", "sysui_demo_allowed", "1")
    Invoke-Adb @("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", "enter")
    Invoke-Adb @("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", "clock", "-e", "hhmm", "0930")
    Invoke-Adb @("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", "battery", "-e", "level", "100", "-e", "plugged", "false")
    Invoke-Adb @("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", "network", "-e", "wifi", "show", "-e", "level", "4")
    Invoke-Adb @("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", "network", "-e", "mobile", "show", "-e", "datatype", "none", "-e", "level", "4")
    Invoke-Adb @("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", "notifications", "-e", "visible", "false")
    Write-Host "[OK] 상태바가 09:30 / 100% 로 바뀌었는지 확인하세요. (capture.ps1 로 한 장 찍어 검증 가능)"
} else {
    Write-Host "[demo mode] OFF — 실제 상태바로 복귀"
    Invoke-Adb @("am", "broadcast", "-a", "com.android.systemui.demo", "-e", "command", "exit")
    Write-Host "[OK] 데모 모드 해제 완료."
}
