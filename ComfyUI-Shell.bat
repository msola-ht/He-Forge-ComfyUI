@echo off
setlocal

set "ROOT=%~dp0"
pushd "%ROOT%"

pwsh -NoProfile -ExecutionPolicy Bypass -File "%ROOT%docker\compose.ps1" run --rm --service-ports comfyui-runtime bash
set "EXIT_CODE=%ERRORLEVEL%"

popd
if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
