@echo off
chcp 936 >nul
title 校园网自动登录 - 第3步 安装开机自启
set "DIR=%~dp0"
where pwsh >nul 2>nul
if %errorlevel%==0 (set "PS=pwsh") else (set "PS=powershell")
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%DIR%install.ps1"
pause