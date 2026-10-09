@echo off
REM Double-click friendly Windows launcher for the drone census stack.
REM Forwards any args to start.ps1 (e.g. start.bat -Webcam).

setlocal
cd /d "%~dp0.."

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
set EXITCODE=%ERRORLEVEL%

if %EXITCODE% NEQ 0 (
  echo.
  echo [start.bat] Launcher exited with code %EXITCODE%.
  echo See CLIENT_QUICKSTART.md if you need setup help.
  pause
)
exit /b %EXITCODE%
