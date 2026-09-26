@echo off
chcp 936 >nul
title 校园网自动登录 - 第1步 填写密码
set "DIR=%~dp0"
if not exist "%DIR%password.txt" (
    echo.> "%DIR%password.txt"
    echo   [已创建 password.txt]
)
echo.
echo   ==================================================
echo    即将打开记事本。
echo    请删掉里面的空行，只填你的校园网密码，
echo    然后按 Ctrl+S 保存、关闭记事本。
echo   ==================================================
echo.
notepad "%DIR%password.txt"
echo.
echo   完成。下一步请双击：2-测试登录.bat
echo.
pause