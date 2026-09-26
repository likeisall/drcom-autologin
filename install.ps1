<#
.SYNOPSIS
    安装 / 卸载「校园网自动登录」开机自启项

.DESCRIPTION
    在用户启动文件夹创建一个快捷方式，指向 start-hidden.vbs。
    用户登录 Windows 后自动以隐藏方式启动 campus-login.ps1（守护模式）。
    不需要管理员权限，不写入注册表 Run 项。

.PARAMETER Uninstall
    移除自启项

.PARAMETER Status
    只查看当前安装状态

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Status
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
$ScriptDir  = $PSScriptRoot
$VbsPath    = Join-Path $ScriptDir 'start-hidden.vbs'
$Ps1Path    = Join-Path $ScriptDir 'campus-login.ps1'
$StartupDir = [Environment]::GetFolderPath('Startup')
$LinkPath   = Join-Path $StartupDir 'CampusNet-AutoLogin.lnk'
$LinkName   = 'CampusNet-AutoLogin'

function Get-Installed {
    if (Test-Path $LinkPath) { return $true }
    # 也检查脚本目录里直接被复制进去的 vbs
    if (Test-Path (Join-Path $StartupDir 'start-hidden.vbs')) { return $true }
    return $false
}

function Show-Status {
    Write-Host ''
    Write-Host '  校园网自动登录 · 安装状态' -ForegroundColor Cyan
    Write-Host ('  启动文件夹 : ' + $StartupDir) -ForegroundColor DarkGray
    Write-Host ('  主脚本     : ' + $Ps1Path)   -ForegroundColor DarkGray
    Write-Host ('  启动器     : ' + $VbsPath)   -ForegroundColor DarkGray
    Write-Host ''
    if (Test-Path $LinkPath) {
        Write-Host ('  [已安装] 快捷方式存在：' + $LinkPath) -ForegroundColor Green
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($LinkPath)
        Write-Host ('           目标：' + $sc.TargetPath + ' ' + $sc.Arguments) -ForegroundColor DarkGray
    } else {
        Write-Host '  [未安装] 启动文件夹中没有快捷方式。' -ForegroundColor Yellow
    }
    # 守护进程是否在跑
    $running = Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like '*campus-login.ps1*' }
    if ($running) {
        Write-Host ('  [运行中] 守护进程 PID: ' + ($running.ProcessId -join ', ')) -ForegroundColor Green
    } else {
        Write-Host '  [未运行] 当前没有守护进程在跑。' -ForegroundColor Yellow
    }
    $log = Join-Path $ScriptDir 'campus-login.log'
    if (Test-Path $log) {
        Write-Host ''
        Write-Host '  最近 10 条日志：' -ForegroundColor DarkGray
        Get-Content $log -Tail 10 | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor DarkGray }
    }
    Write-Host ''
}

if ($Status) { Show-Status; exit }

if ($Uninstall) {
    if (Test-Path $LinkPath) { Remove-Item $LinkPath -Force; Write-Host ('已删除：' + $LinkPath) -ForegroundColor Yellow }
    $copiedVbs = Join-Path $StartupDir 'start-hidden.vbs'
    if (Test-Path $copiedVbs) { Remove-Item $copiedVbs -Force; Write-Host ('已删除：' + $copiedVbs) -ForegroundColor Yellow }
    $running = Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like '*campus-login.ps1*' }
    foreach ($p in $running) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host ('已结束守护进程 PID ' + $p.ProcessId) -ForegroundColor Yellow }
    Write-Host '自启项已卸载。' -ForegroundColor Green
    exit
}

# ------------------------------ 安装 ----------------------------------------
if (-not (Test-Path $Ps1Path)) { throw "找不到主脚本：$Ps1Path" }
if (-not (Test-Path $VbsPath)) { throw "找不到启动器：$VbsPath" }

Write-Host ''
Write-Host '  安装「校园网自动登录」开机自启...' -ForegroundColor Cyan

$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($LinkPath)
$sc.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
$sc.Arguments        = '"' + $VbsPath + '"'
$sc.WorkingDirectory = $ScriptDir
$sc.WindowStyle      = 7          # 最小化
$sc.Description      = '校园网（Dr.COM ePortal）自动登录守护'
$sc.Save()

Write-Host ('  [OK] 已创建快捷方式：' + $LinkPath) -ForegroundColor Green
Write-Host '  [OK] 下次登录 Windows 后将自动在后台运行。' -ForegroundColor Green
Write-Host ''
Write-Host '  提示：现在就可以先手动跑一次验证：' -ForegroundColor Yellow
Write-Host '        .\start-hidden.vbs      (隐藏运行)' -ForegroundColor DarkGray
Write-Host '        或 .\campus-login.ps1   (可见窗口，便于观察)' -ForegroundColor DarkGray
Write-Host ''
Show-Status
