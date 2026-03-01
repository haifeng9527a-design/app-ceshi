# 持续捕获来电相关日志，保存到 call_logs_YYYYMMDD_HHmmss.txt
# 用法: .\scripts\capture_call_logs.ps1
# 来电测试时保持此脚本运行，结束后 Ctrl+C 停止

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "call_logs_$timestamp.txt"
$device = (adb devices | Select-String "device$" | ForEach-Object { ($_ -split "\s+")[0] } | Select-Object -First 1)

if (-not $device) {
    Write-Host "未检测到已连接的设备，请确保手机已通过 USB 连接并开启调试"
    exit 1
}

Write-Host "设备: $device"
Write-Host "日志保存到: $logFile"
Write-Host "请退到主屏幕/锁屏，用另一台设备发起语音通话进行测试"
Write-Host "按 Ctrl+C 停止捕获"
Write-Host ""

adb -s $device logcat -c  # 清空旧日志
# 持续捕获日志（来电时会有 FlutterIntentService、Call notification 等输出）
adb -s $device logcat -v time 2>&1 | Tee-Object -FilePath $logFile
