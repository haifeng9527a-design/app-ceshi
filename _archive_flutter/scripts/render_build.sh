#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.5}"
FLUTTER_ROOT="${FLUTTER_ROOT:-$PWD/.flutter-sdk}"

if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  rm -rf "$FLUTTER_ROOT"
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
fi

export PATH="$FLUTTER_ROOT/bin:$PATH"

if [ -z "${TONGXIN_API_URL:-}" ] && [ -z "${BACKEND_URL:-}" ]; then
  echo "Render build aborted: set TONGXIN_API_URL or BACKEND_URL." >&2
  exit 1
fi

write_env_var() {
  local key="$1"
  local value="${2:-}"
  printf '%s=%s\n' "$key" "$value" >> .env
}

: > .env
write_env_var "TONGXIN_API_URL" "${TONGXIN_API_URL:-}"
write_env_var "BACKEND_URL" "${BACKEND_URL:-}"
write_env_var "SUPABASE_URL" "${SUPABASE_URL:-}"
write_env_var "SUPABASE_ANON_KEY" "${SUPABASE_ANON_KEY:-}"
write_env_var "FIREBASE_API_KEY" "${FIREBASE_API_KEY:-}"
write_env_var "FIREBASE_APP_ID" "${FIREBASE_APP_ID:-}"
write_env_var "FIREBASE_MESSAGING_SENDER_ID" "${FIREBASE_MESSAGING_SENDER_ID:-}"
write_env_var "FIREBASE_PROJECT_ID" "${FIREBASE_PROJECT_ID:-}"
write_env_var "FIREBASE_AUTH_DOMAIN" "${FIREBASE_AUTH_DOMAIN:-}"
write_env_var "FIREBASE_STORAGE_BUCKET" "${FIREBASE_STORAGE_BUCKET:-}"
write_env_var "FIREBASE_MEASUREMENT_ID" "${FIREBASE_MEASUREMENT_ID:-}"
write_env_var "AGORA_APP_ID" "${AGORA_APP_ID:-}"
write_env_var "AGORA_TOKEN" "${AGORA_TOKEN:-}"
write_env_var "POLYGON_API_KEY" "${POLYGON_API_KEY:-}"
write_env_var "TWELVE_DATA_API_KEY" "${TWELVE_DATA_API_KEY:-}"
write_env_var "APP_DOWNLOAD_URL" "${APP_DOWNLOAD_URL:-}"
write_env_var "WEBVIEW_USER_PAGE_URL" "${WEBVIEW_USER_PAGE_URL:-}"
write_env_var "LOCAL_DEV_MODE" "${LOCAL_DEV_MODE:-false}"

flutter --version
flutter config --enable-web
flutter pub get
flutter build web --release
