@echo off
REM Client entry point - double-click this file to start the full stack.
cd /d "%~dp0"
call "%~dp0scripts\start.bat" %*
