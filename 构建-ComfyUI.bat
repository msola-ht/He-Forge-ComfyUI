@echo off
setlocal

set "ROOT=%~dp0"
pushd "%ROOT%"

pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -File "%ROOT%docker\build.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

popd
exit /b %EXIT_CODE%
