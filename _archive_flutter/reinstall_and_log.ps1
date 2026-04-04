# 重新安装 App 并抓取运行日志（TH_CALL + Flutter）
# 用法：连接一台手机，在 app 目录执行 .\reinstall_and_log.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$logsDir = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logsDir "app_$ts.log"

Write-Host "=== 1. 重新安装 App ==="
flutter clean
flutter pub get

# 多设备时自动选第一台 Android，避免交互选择
$devicesJson = flutter devices --machine 2>$null
$devices = $devicesJson | ConvertFrom-Json -ErrorAction SilentlyContinue
$android = $devices | Where-Object { $_.platform -eq "android" } | Select-Object -First 1
if ($android) {
    Write-Host "安装到: $($android.name) ($($android.id))"
    flutter install -d $android.id
} else {
    flutter install
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "安装失败，退出码: $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "=== 2. 抓取运行日志 ==="
Write-Host "日志将保存到: $logFile"
Write-Host "过滤: TH_CALL 与 I/flutter（含 onError、joinChannel 等）"
Write-Host "进行你的通话测试，完成后按 Enter 停止抓包。"
Write-Host ""

$deviceId = if ($android) { $android.id } else { $null }
# 清空该设备 logcat 再开始
if ($deviceId) { & adb -s $deviceId logcat -c 2>$null } else { & adb logcat -c 2>$null }
Start-Sleep -Seconds 1

# 后台抓 logcat（同一台设备），只保留 TH_CALL 与 I/flutter
$job = Start-Job -ScriptBlock {
    param($path, $devId)
    $cmd = if ($devId) { & adb -s $devId logcat -v time 2>&1 } else { & adb logcat -v time 2>&1 }
    $cmd | Where-Object { $_ -match "TH_CALL|I/flutter" } | Out-File -FilePath $path -Encoding utf8 -Append
} -ArgumentList $logFile, $deviceId

Write-Host "正在记录... 完成通话测试后按 Enter 停止。"
Read-Host
Stop-Job $job
Remove-Job $job

Write-Host "日志已保存: $logFile"
