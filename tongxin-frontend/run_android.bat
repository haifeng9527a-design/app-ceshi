@echo off
setlocal

set "APP_DIR=%~dp0"
set "SUPABASE_URL=https://theqizksqjrylsnrrrhx.supabase.co"
set "SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRoZXFpemtzcWpyeWxzbnJycmh4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA2MTA4NzQsImV4cCI6MjA4NjE4Njg3NH0.8GYXS6D1rcjp3KZOTJ28e7hJfu0mxiD5LHZiTq6oDVc"
set "DEVICE_ID=K5J0220C17003236"

if "%SUPABASE_ANON_KEY%"=="" (
  echo Please set SUPABASE_ANON_KEY in run_android.bat
  exit /b 1
)

cd /d "%APP_DIR%"
flutter pub get
flutter run -d %DEVICE_ID% --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
