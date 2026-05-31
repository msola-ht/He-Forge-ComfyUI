@echo off
setlocal

set "ROOT=%~dp0"
pushd "%ROOT%"

pwsh -NoProfile -ExecutionPolicy Bypass -File "%ROOT%docker\compose.ps1" up comfyui-runtime
set "EXIT_CODE=%ERRORLEVEL%"

popd
if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
