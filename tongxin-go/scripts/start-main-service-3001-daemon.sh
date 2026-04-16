#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

LOG_PATH="${LOG_PATH:-/tmp/tongxin-main-3001.log}"
ERROR_LOG_PATH="${ERROR_LOG_PATH:-/tmp/tongxin-main-3001.err.log}"

mkdir -p "$(dirname "$LOG_PATH")"

echo "[main-service] installing launch agent for :3001"
"$ROOT_DIR/scripts/install-main-service-launchagent.sh"

sleep 3

if lsof -iTCP:3001 -sTCP:LISTEN -n -P >/dev/null 2>&1; then
  echo "[main-service] up on :3001"
  exit 0
fi

echo "[main-service] failed to stay up; last stdout log lines:"
tail -n 60 "$LOG_PATH" 2>/dev/null || true
echo "[main-service] last stderr log lines:"
tail -n 60 "$ERROR_LOG_PATH" 2>/dev/null || true
exit 1
