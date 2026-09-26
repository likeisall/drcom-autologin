@echo off
chcp 936 >nul
title Ð£Ô°Íø×Ô¶¯µÇÂ¼ - Ð¶ÔØ×ÔÆô
set "DIR=%~dp0"
where pwsh >nul 2>nul
if %errorlevel%==0 (set "PS=pwsh") else (set "PS=powershell")
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%DIR%install.ps1" -Uninstall
pause