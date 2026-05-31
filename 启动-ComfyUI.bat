@echo off
setlocal

set "ROOT=%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%ROOT%docker\start-runtime.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

if "%EXIT_CODE%"=="0" (
    echo.
    echo ComfyUI runtime start command completed.
    pause
)

if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
