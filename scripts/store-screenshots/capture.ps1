# capture.ps1 — 스토어 스크린샷 반자동 촬영 (Windows PowerShell)
#
# 완전 자동화가 아니다: 로그인·데이터 준비·화면 이동은 사람이 손으로 한다.
# 이 스크립트는 8개 항목을 순회하며, 화면이 준비되면 Enter 를 받아
# adb screencap 으로 저장하고, 저장 직후 해상도를 출력한다.
#
#   Enter = 촬영   s = 이 항목 건너뛰기   r = 직전 항목 다시 찍기   q = 종료
#
# 사용법:  powershell -ExecutionPolicy Bypass -File scripts\store-screenshots\capture.ps1
# 출력:    build/store-screenshots/phone/<파일명>.png

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$outDir = Join-Path $repoRoot "build\store-screenshots\phone"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# adb 연결 확인
& adb get-state *> $null
if ($LASTEXITCODE -ne 0) { Write-Error "연결된 기기/에뮬레이터가 없습니다. 에뮬레이터를 먼저 부팅하세요." }

# 촬영 목록: 파일명 | 안내 문구
$shots = @(
    @{ Name = "01_questionroom";         Label = "질문방 홈(학생) — 내 멘토 칩, 질문 카드 2~3장, 상태칩, 잔여 질문 수" }
    @{ Name = "02_thread_answered";      Label = "질문 상세 — 멘토 답변 + 첨부 이미지/수식" }
    @{ Name = "03_connection_note";      Label = "연결노트 — 내용이 3~5줄 쌓인 상태" }
    @{ Name = "04_notifications";        Label = "알림 — 답변 도착 알림 3~4건" }
    @{ Name = "05_mentors";              Label = "멘토 찾기 — 멘토 카드 목록, 인증 배지" }
    @{ Name = "06_mentor_detail";        Label = "멘토 상세 — 인증 배지·후기·답변률" }
    @{ Name = "07_community_shorts";     Label = "커뮤니티 — 숏폼 피드" }
    @{ Name = "08_individual_questions"; Label = "개별질문 — 목록 또는 작성 화면" }
)

# PNG 헤더(IHDR)에서 width/height 를 직접 읽는다 (외부 도구 불필요)
function Get-PngSize {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 24) { return $null }
    $w = ($bytes[16] -shl 24) -bor ($bytes[17] -shl 16) -bor ($bytes[18] -shl 8) -bor $bytes[19]
    $h = ($bytes[20] -shl 24) -bor ($bytes[21] -shl 16) -bor ($bytes[22] -shl 8) -bor $bytes[23]
    return @($w, $h)
}

function Take-Shot {
    param([string]$Name)
    $dest = Join-Path $outDir "$Name.png"
    # PowerShell 파이프는 바이너리를 깨뜨리므로 기기 내 저장 → pull 방식을 쓴다.
    & adb shell screencap -p /sdcard/_store_shot.png
    if ($LASTEXITCODE -ne 0) { Write-Warning "screencap 실패"; return $false }
    & adb pull /sdcard/_store_shot.png $dest | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "pull 실패"; return $false }
    & adb shell rm /sdcard/_store_shot.png

    $size = Get-PngSize $dest
    if ($size) {
        $mark = if ($size[0] -eq 1080 -and $size[1] -eq 1920) { "OK" } else { "!! 1080x1920 아님" }
        Write-Host ("    저장: {0}  ({1}x{2})  [{3}]" -f $dest, $size[0], $size[1], $mark)
    } else {
        Write-Warning "PNG 헤더를 읽지 못했습니다: $dest"
    }
    return $true
}

Write-Host "출력 폴더: $outDir"
Write-Host "Enter=촬영 / s=건너뛰기 / r=직전 것 다시 / q=종료`n"

$i = 0
:mainLoop while ($i -lt $shots.Count) {
    $shot = $shots[$i]
    $prompt = "[{0}/{1}] {2} — 화면 준비되면 Enter (s=건너뛰기, r=직전 것 다시, q=종료)" -f ($i + 1), $shots.Count, $shot.Label
    $answer = Read-Host $prompt

    switch ($answer.Trim().ToLower()) {
        "s" { Write-Host "    건너뜀: $($shot.Name)`n"; $i++ }
        "q" { Write-Host "종료합니다."; break mainLoop }
        "r" {
            if ($i -gt 0) {
                $i--
                Write-Host "    직전 항목으로 돌아갑니다: $($shots[$i].Name)`n"
            } else {
                Write-Host "    첫 항목입니다. 되돌아갈 항목이 없습니다.`n"
            }
        }
        default {
            if (Take-Shot $shot.Name) { $i++ }
            Write-Host ""
        }
    }
}

Write-Host "`n촬영 종료. 검증:  python scripts\store-screenshots\verify.py"
