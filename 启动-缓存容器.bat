@echo off
setlocal

set "ROOT=%~dp0"
pushd "%ROOT%"

pwsh -NoProfile -ExecutionPolicy Bypass -File "%ROOT%docker\start-cache-services.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

popd
if "%EXIT_CODE%"=="0" (
    echo.
    echo Cache services start command completed.
    pause
)

if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
