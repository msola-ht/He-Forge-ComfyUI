@echo off
setlocal

set "ROOT=%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%ROOT%docker\open-runtime-shell.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" pause
exit /b %EXIT_CODE%
