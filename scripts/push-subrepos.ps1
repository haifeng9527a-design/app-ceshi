# 将主仓库的子树拆分并推送到对应子仓库
# 用法: .\scripts\push-subrepos.ps1
# 需先在 GitHub 创建子仓库: tongxin-backend, tongxin-frontend, tongxin-admin, webview-user-page

$ErrorActionPreference = "Stop"
$baseUrl = "https://github.com/haifeng9527a-design"
$subrepos = @(
    @{ prefix = "tongxin-backend"; branch = "split-backend"; remote = "backend"; repo = "tongxin-backend-api" },
    @{ prefix = "tongxin-frontend"; branch = "split-frontend"; remote = "frontend"; repo = "tongxin-frontend" },
    @{ prefix = "tongxin-admin"; branch = "split-admin"; remote = "admin"; repo = "tongxin-admin" },
    @{ prefix = "webview-user-page"; branch = "split-webview"; remote = "webview"; repo = "webview-user-page" }
)

$sourceBranch = "2026-03-04-r3e8"
Push-Location $PSScriptRoot\..

Write-Host "当前分支: $(git branch --show-current)" -ForegroundColor Cyan
Write-Host ""

foreach ($r in $subrepos) {
    $repoName = if ($r.repo) { $r.repo } else { $r.prefix }; $remoteUrl = "$baseUrl/$repoName.git"
    Write-Host "=== $($r.prefix) ===" -ForegroundColor Yellow
    
    # 添加 remote（若不存在）
    $existing = git remote get-url $r.remote 2>$null
    if (-not $existing) {
        git remote add $r.remote $remoteUrl
        Write-Host "  添加 remote: $r.remote -> $remoteUrl"
    }
    
    # subtree split
    Write-Host "  执行 subtree split..."
    git subtree split --prefix=$($r.prefix) -b $($r.branch) 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  split 失败，跳过" -ForegroundColor Red
        continue
    }
    
    # push
    Write-Host "  推送到 $($r.remote)..."
    git push $r.remote "$($r.branch):main" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK" -ForegroundColor Green
    } else {
        Write-Host "  推送失败（可能子仓库不存在或需先创建）" -ForegroundColor Red
    }
    Write-Host ""
}

Pop-Location
Write-Host "完成" -ForegroundColor Cyan
