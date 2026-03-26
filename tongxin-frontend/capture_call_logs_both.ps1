# Capture [TH_CALL] logs from both phones for call debugging.
# Usage: Connect both phones via USB, run: .\capture_call_logs_both.ps1
# Then make a voice call (caller -> callee answer), press Enter to stop.

$ErrorActionPreference = "Stop"
$logsDir = Join-Path $PSScriptRoot "logs"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logNOP = Join-Path $logsDir "call_NOP_4EU_$ts.log"
$logELS = Join-Path $logsDir "call_ELS_K5J_$ts.log"

$idNOP = "4EU0221706000336"
$idELS = "K5J0220C17003236"

New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

# Suppress adb daemon stderr so "daemon not running; starting now" does not stop the script
$devicesOut = & adb devices 2>$null | Out-String
if ($devicesOut -notmatch [regex]::Escape($idNOP)) { Write-Warning "NOP device not found: $idNOP" }
if ($devicesOut -notmatch [regex]::Escape($idELS)) { Write-Warning "ELS device not found: $idELS" }

Write-Host "[TH_CALL] Clearing logcat on both devices..."
& adb -s $idNOP logcat -c 2>$null
& adb -s $idELS logcat -c 2>$null
Start-Sleep -Seconds 1

$rawNOP = Join-Path $logsDir "call_NOP_4EU_${ts}_raw.log"
$rawELS = Join-Path $logsDir "call_ELS_K5J_${ts}_raw.log"

Write-Host "[TH_CALL] Capturing full logcat to file, then extract TH_CALL."
Write-Host "  NOP (caller): $logNOP"
Write-Host "  ELS (callee): $logELS"
Write-Host "Do your call test, then press Enter to stop."
Write-Host ""

$pNOP = Start-Process -FilePath "adb" -ArgumentList "-s", $idNOP, "logcat", "-v", "time" -RedirectStandardOutput $rawNOP -RedirectStandardError (Join-Path $logsDir "nop_err.txt") -NoNewWindow -PassThru
$pELS = Start-Process -FilePath "adb" -ArgumentList "-s", $idELS, "logcat", "-v", "time" -RedirectStandardOutput $rawELS -RedirectStandardError (Join-Path $logsDir "els_err.txt") -NoNewWindow -PassThru

Read-Host
try { $pNOP.Kill() } catch {}
try { $pELS.Kill() } catch {}
Start-Sleep -Seconds 1

Get-Content -LiteralPath $rawNOP -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "TH_CALL" } | Set-Content -LiteralPath $logNOP -Encoding utf8
Get-Content -LiteralPath $rawELS -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "TH_CALL" } | Set-Content -LiteralPath $logELS -Encoding utf8

Write-Host ""
Write-Host "Done. Logs (TH_CALL only):"
Write-Host "  Caller (NOP): $logNOP"
Write-Host "  Callee (ELS): $logELS"
Write-Host "Full raw: $rawNOP , $rawELS"
Write-Host "Check: caller got accepted? both onJoinChannelSuccess/onUserJoined?"
