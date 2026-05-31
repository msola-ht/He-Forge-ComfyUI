@echo off
setlocal

set "ROOT=%~dp0"
pushd "%ROOT%"

pwsh -NoProfile -ExecutionPolicy Bypass -File "%ROOT%docker\export-runtime-state.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

popd
if "%EXIT_CODE%"=="0" (
    echo.
    echo Runtime state export command completed.
    pause
)

if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
