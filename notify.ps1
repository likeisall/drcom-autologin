<#
.SYNOPSIS
    校园网自动登录 —— Windows 通知小工具  v1.0

.DESCRIPTION
    弹一条 Windows 通知（Toast）。由 campus-login.ps1 在状态变化时调用。

    ★ 为什么要单独一个文件、而且必须用 5.1 跑？★
    PowerShell 7（Core）加载不了 WinRT 类型，实测报：
        找不到类型 [Windows.UI.Notifications.ToastNotificationManager,
                    Windows.UI.Notifications, ContentType=WindowsRuntime]
    所以 campus-login.ps1 改用 Windows PowerShell 5.1 来执行本脚本。
    已验证：5.1 无需任何第三方模块即可弹出通知。

    ★ 本文件必须带 UTF-8 BOM，不要用编辑器去掉 ★
    5.1 读「无 BOM 的 .ps1」时按系统 ANSI（本机 GBK）解码，
    中文会乱码并直接导致语法错误（实测 UnexpectedToken）。
    带 BOM 后，5.1 与 7 都能正确解析。

.PARAMETER Title
    通知标题

.PARAMETER Body
    通知正文

.PARAMETER Silent
    静音弹出（不出声）

.EXAMPLE
    powershell.exe -NoProfile -File notify.ps1 -Title '校园网' -Body '已自动登录'

.NOTES
    · 版本 1.0
    · 最初为作者本校的校园网而写，现整理开源。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Title,
    [string]$Body = '',
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'

# 借用 Windows PowerShell 自身的 AppUserModelID，
# 这样通知来源显示为「Windows PowerShell」而不是无名应用。
$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $esc = {
        param($s)
        ($s -replace '&', '&amp;') -replace '<', '&lt;' -replace '>', '&gt;'
    }

    $silentAttr = if ($Silent) { ' silent="true"' } else { '' }

    $xmlText = '<toast' + $silentAttr + '>' +
               '<visual><binding template="ToastGeneric">' +
               '<text>' + (& $esc $Title) + '</text>' +
               '<text>' + (& $esc $Body)  + '</text>' +
               '</binding></visual></toast>'

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlText)

    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
