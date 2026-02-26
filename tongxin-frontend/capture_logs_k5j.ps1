# 在 K5J 设备上抓取 teacher_hub 运行日志（来电、通知、FCM 等）
# 用法：连接 K5J 后执行 .\capture_logs_k5j.ps1
# 日志会保存到 app\logs_k5j.txt，默认抓取 90 秒（可测试来电）

$deviceId = "K5J0220C17003236"
$logFile = Join-Path $PSScriptRoot "logs_k5j.txt"
$durationSec = 90

Write-Host "设备: $deviceId"
Write-Host "日志文件: $logFile"
Write-Host "抓取时长: ${durationSec} 秒（可 Ctrl+C 提前结束）"
Write-Host ""

# 清空设备 logcat 缓冲区
& adb -s $deviceId logcat -c 2>$null
Start-Sleep -Seconds 1

Write-Host "开始抓取日志，按 Ctrl+C 结束..."
# 抓取 logcat 并同时输出到屏幕和文件
& adb -s $deviceId logcat -v time 2>&1 | Tee-Object -FilePath $logFile
Write-Host "`n日志已保存到: $logFile"
