<#
.SYNOPSIS
    校园网自动登录 —— Windows 通知小工具  v2.3

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

    ★ v2.0：正文支持多行，参数改用 Base64 传入 ★
    正文是多行中文，经 Start-Process 拼命令行会被空格与换行拆坏，因此改成传 Base64：
        -TitleB64 / -BodyB64   （只含 A-Za-z0-9+/=，绝无空格）
    正文里的换行会被拆成多个 <text> 元素，在通知里逐行显示。
    老的 -Title / -Body 明文参数仍保留，手工调试照样能用。
    新增 -Preview：只打印将要提交的 Toast XML，不真的弹。

    ★ v2.1 / v2.2：颜色（-Accent）★

    ⚠️ 先说清楚：Windows 的 Toast **没有「整条通知变绿/变黄/变红」的接口** ——
       卡片底色由系统主题决定，应用无权改。能真正上色的只有两处：

       ① 标题前的彩色圆点 🟢🟡🔴（用 [char]::ConvertFromUtf32 按码点构造，
          源码里不出现补充平面字符，免得 5.1 读文件时出幺蛾子）

       ② 卡片左侧的大徽章图（appLogoOverride + hint-crop="circle"）
          图片是同目录 icons\green.png / yellow.png / red.png
          （64x64 透明底：绿✓ / 黄! / 红✗）。
          实测（2026-10-01）：file:/// 本地路径可被 Toast 接受，Show() 正常返回。

    ★ v2.2：**去掉标题圆点，只用大徽章** ★
       看过实物后说「有了大图标，那些小圆点就去掉吧」—— 两处同时上色确实重复。
       所以现在：图标文件在 → 只用大图，标题保持干净；
                 图标文件丢了 → 才退回圆点垫一下，免得整条通知没颜色。
       注意：左上角那个「Windows PowerShell」小图标不受本参数影响 ——
       它来自发通知的应用身份（本脚本借用的是 PowerShell 的 AppUserModelID），
       要换掉得往开始菜单注册带自定义图标的应用快捷方式，改动面更大，未做。

    ★ v2.3：新增蓝色徽章给「换号成功」★
       原先「换号成功」跟「主账号登录失败」共用黄色，两件事一个色容易混。
       换号成功改用**蓝底白对号**（icons\blue.png）。
       于是四档颜色各司其职：
           green  绿✓  掉线后用当前账号正常登回
           blue   蓝✓  主账号被拒、已自动换到下一个账号并成功
           yellow 黄!  主账号被拒、正在尝试换号（主账号自己的坏消息）
           red    红✗  表里所有账号都登不上

    -Accent 取值：none（默认，不加色）/ green / blue / yellow / red

.PARAMETER Title
    通知标题（明文）

.PARAMETER Body
    通知正文（明文，可含换行）

.PARAMETER TitleB64
    通知标题的 Base64（UTF-8），优先于 -Title

.PARAMETER BodyB64
    通知正文的 Base64（UTF-8），优先于 -Body

.PARAMETER Accent
    颜色标记：none / green / blue / yellow / red

.PARAMETER Silent
    静音弹出（不出声）

.PARAMETER Preview
    只打印 Toast XML，不弹通知

.EXAMPLE
    powershell.exe -NoProfile -File notify.ps1 -Title '校园网' -Body '已自动登录' -Accent green

.EXAMPLE
    .\notify.ps1 -Title '校园网 · 已自动登录' -Body "账号：主账号`n时间：01:23" -Accent green -Preview
    看一眼 XML 长什么样（不弹窗）

.NOTES
    · 版本 2.3
    · 本脚本最初为作者本校的校园网而写，现整理开源。
#>
[CmdletBinding()]
param(
    [string]$Title = '',
    [string]$Body = '',
    [string]$TitleB64 = '',
    [string]$BodyB64 = '',
    [ValidateSet('none', 'green', 'blue', 'yellow', 'red')][string]$Accent = 'none',
    [switch]$Silent,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'

# ---- Base64 优先（调用方用它绕开命令行引号/空格/换行问题）----
try {
    if (-not [string]::IsNullOrWhiteSpace($TitleB64)) {
        $Title = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($TitleB64))
    }
    if (-not [string]::IsNullOrWhiteSpace($BodyB64)) {
        $Body = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($BodyB64))
    }
} catch {
    Write-Error ('通知参数 Base64 解码失败：' + $_.Exception.Message)
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Title)) { $Title = '校园网' }

# ---- 颜色：只靠卡片大图 ----
# 既然卡片左侧已经有彩色大徽章，标题前的彩色圆点就去掉，免得重复。
# 唯一例外：图标文件缺失时退回圆点，否则整条通知一点颜色标识都没有了。
#
# 圆点用码点构造（源码里不写 emoji，5.1 读文件更保险）
$dotMap = @{
    'green'  = [char]::ConvertFromUtf32(0x1F7E2)   # 绿圆
    'blue'   = [char]::ConvertFromUtf32(0x1F535)   # 蓝圆
    'yellow' = [char]::ConvertFromUtf32(0x1F7E1)   # 黄圆
    'red'    = [char]::ConvertFromUtf32(0x1F534)   # 红圆
}

$iconFile = Join-Path (Join-Path $PSScriptRoot 'icons') ($Accent + '.png')
$imgTag   = ''
if ($Accent -ne 'none' -and (Test-Path $iconFile)) {
    # 正常路径：同色徽章大图（绿✓ / 蓝✓ / 黄! / 红✗）
    $imgTag = '<image placement="appLogoOverride" hint-crop="circle" src="' + ([System.Uri]$iconFile).AbsoluteUri + '"/>'
} elseif ($Accent -ne 'none' -and $dotMap.ContainsKey($Accent)) {
    # 兜底路径：图标文件丢了，退而用标题圆点保住颜色标识
    $Title = $dotMap[$Accent] + ' ' + $Title
}

# 借用 Windows PowerShell 自身的 AppUserModelID，
# 这样通知来源显示为「Windows PowerShell」而不是无名应用。
$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

# XML 转义（先 & 后 < >，顺序不能反）
$esc = {
    param($s)
    (([string]$s -replace '&', '&amp;') -replace '<', '&lt;') -replace '>', '&gt;'
}

# 正文按行拆开：每个非空行单独一个 <text>，通知里逐行显示
$bodyLines = @()
if (-not [string]::IsNullOrWhiteSpace($Body)) {
    $bodyLines = @($Body -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$silentAttr = if ($Silent) { ' silent="true"' } else { '' }

$xmlText = '<toast' + $silentAttr + '>' +
           '<visual><binding template="ToastGeneric">' +
           $imgTag +
           '<text>' + (& $esc $Title) + '</text>'
foreach ($line in $bodyLines) {
    $xmlText += '<text>' + (& $esc $line) + '</text>'
}
$xmlText += '</binding></visual></toast>'

if ($Preview) {
    Write-Output $xmlText
    exit 0
}

try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlText)

    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
