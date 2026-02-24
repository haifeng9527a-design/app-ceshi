#!/bin/bash
# 自动从远程仓库拉取最新代码到本地
# 由 launchd 定时执行（默认每 5 分钟）

REPO_DIR="/Users/haifeng/Desktop/app---tongxin"
LOG_FILE="${REPO_DIR}/scripts/git-auto-pull.log"

cd "$REPO_DIR" || exit 1

# 只追加日志，避免刷屏
exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 检查远程更新..."
git fetch origin

if git status | grep -q 'Your branch is behind'; then
  git pull --ff-only origin main
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已拉取最新代码"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 本地已是最新"
fi
