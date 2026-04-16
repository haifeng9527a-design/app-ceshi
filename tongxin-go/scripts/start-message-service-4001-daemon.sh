#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

LOG_PATH="${LOG_PATH:-/tmp/tongxin-message-4001.log}"
PID_PATH="${PID_PATH:-/tmp/tongxin-message-4001.pid}"

if [ -f "$PID_PATH" ]; then
  old_pid="$(cat "$PID_PATH" 2>/dev/null || true)"
  if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "[message-service] stopping existing pid ${old_pid}"
    kill "$old_pid" || true
    sleep 1
  fi
fi

port_pid="$(lsof -tiTCP:4001 -sTCP:LISTEN || true)"
if [ -n "${port_pid:-}" ]; then
  echo "[message-service] freeing port 4001 from pid ${port_pid}"
  kill "$port_pid" || true
  sleep 1
fi

echo "[message-service] launching detached daemon on :4001"
nohup "$ROOT_DIR/scripts/run-message-service-4001.sh" >"$LOG_PATH" 2>&1 </dev/null &
daemon_pid=$!
echo "$daemon_pid" >"$PID_PATH"

sleep 6

if lsof -iTCP:4001 -sTCP:LISTEN -n -P >/dev/null 2>&1; then
  echo "[message-service] up on :4001 (pid ${daemon_pid})"
  exit 0
fi

echo "[message-service] failed to stay up; last log lines:"
tail -n 40 "$LOG_PATH" || true
exit 1
