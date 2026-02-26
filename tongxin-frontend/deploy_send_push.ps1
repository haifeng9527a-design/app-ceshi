# 部署 Edge Functions：send_push、create_call_invitation（及可选 notify_new_message）
# 在 PowerShell 中执行: cd app; .\deploy_send_push.ps1

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $PSScriptRoot

Write-Host "1. 若未登录过 Supabase，请先运行: supabase login" -ForegroundColor Yellow
Write-Host "2. 若未关联项目，请先运行: supabase link --project-ref <你的项目Reference ID>" -ForegroundColor Yellow
Write-Host "   项目 ID 在: Supabase 控制台 -> Project Settings -> General -> Reference ID`n" -ForegroundColor Gray

Write-Host "正在部署 send_push..." -ForegroundColor Cyan
supabase functions deploy send_push --workdir .
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "正在部署 create_call_invitation..." -ForegroundColor Cyan
supabase functions deploy create_call_invitation --workdir .
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n部署完成（send_push + create_call_invitation）." -ForegroundColor Green
