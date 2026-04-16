#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.tongxin.main-service-3001"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_PATH="/tmp/tongxin-main-3001.log"
ERROR_LOG_PATH="/tmp/tongxin-main-3001.err.log"
RUNTIME_DIR="$HOME/Library/Application Support/tongxin-go-run"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$RUNTIME_DIR"

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>cd "${ROOT_DIR}" &amp;&amp; if [ -f "${ROOT_DIR}/.env" ]; then set -a; source "${ROOT_DIR}/.env"; set +a; fi; export PORT=3001; mkdir -p "${RUNTIME_DIR}"; BIN_PATH="${RUNTIME_DIR}/api-3001"; go build -o "\${BIN_PATH}" ./cmd/api &amp;&amp; exec "\${BIN_PATH}"</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>${LOG_PATH}</string>

  <key>StandardErrorPath</key>
  <string>${ERROR_LOG_PATH}</string>
</dict>
</plist>
PLIST

uid="$(id -u)"
launchctl bootout "gui/${uid}" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/${uid}" "$PLIST_PATH"
launchctl enable "gui/${uid}/${LABEL}" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/${uid}/${LABEL}"

echo "[main-service] launch agent installed: ${PLIST_PATH}"
echo "[main-service] label: ${LABEL}"
