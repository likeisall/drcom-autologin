@echo off
chcp 936 >nul
title 校园网自动登录 - 填写账号和密码
set "DIR=%~dp0"
set "FILE=%DIR%accounts.txt"
where pwsh >nul 2>nul
if %errorlevel%==0 (set "PS=pwsh") else (set "PS=powershell")
if not exist "%FILE%" (
    echo.
    echo   accounts.txt 不存在，正在按模板生成...
    "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%DIR%campus-login.ps1" -InitAccountFile
)
echo.
echo   ==================================================
echo    即将打开 accounts.txt —— 账号和密码都写在这里。
echo.
echo    一行一个账号，格式：
echo        学号^|运营商^|密码^|名字
echo.
echo    例如：
echo        20230001^|校园网^|你的密码^|主账号
echo        20230002^|中国联通^|另一个密码^|备选账号
echo.
echo    第 1 行是主账号，后面都是备选账号。
echo    只想用一个账号就只写一行；以 # 开头的是注释行。
echo    改完按 Ctrl+S 保存、关闭记事本。
echo   ==================================================
echo.
notepad "%FILE%"
echo.
echo   完成。建议双击：2-测试登录.bat 验证一次
echo.
pause
