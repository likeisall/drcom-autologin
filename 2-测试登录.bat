@echo off
chcp 936 >nul
title 校园网自动登录 - 第2步 测试登录
set "DIR=%~dp0"
where pwsh >nul 2>nul
if %errorlevel%==0 (set "PS=pwsh") else (set "PS=powershell")
echo.
echo   正在检测网络并尝试登录，请稍候...
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%DIR%campus-login.ps1" -Once
echo.
echo   ==================================================
echo    网络在线，无需登录   = 当前已在线，正常
echo    检测到未登录...登录成功 = 自动登录成功
echo    密码未填写           = 请先双击 1-填写密码.bat
echo    登录失败             = 请看 campus-login.log
echo   ==================================================
echo.
pause