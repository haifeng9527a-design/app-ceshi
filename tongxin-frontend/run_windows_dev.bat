@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64
cd /d "%~dp0"
REM 先生成 cpp_client_wrapper，避免并行构建时 .cc 尚未生成
set "CMAKE_EXE=C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if exist build\windows\x64 if exist "%CMAKE_EXE%" (
  "%CMAKE_EXE%" --build build\windows\x64 --target flutter_assemble --config Debug
)
flutter run -d windows
