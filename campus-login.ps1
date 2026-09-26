<#
.SYNOPSIS
    校园网（Dr.COM ePortal）自动登录 / 保活脚本  v2.3

.DESCRIPTION
    工作流程：
      1. 探测外网连通性（多目标，任一通过即算在线）
      2. 若被重定向到认证门户或响应含门户特征 => 判定为「未登录」
      3. 自动向真实登录接口提交账号密码
      4. 登录接口报成功后，轮询等待 AC 真正放行（默认最多 45 秒）
      5. 仍不通过则自动重试登录（默认最多 3 轮）

    ★ v2.1 关键修正（v2.0 把两代接口的参数名搞混了）★

    本套 AC 的 loadConfig 实测： login_method = 1
    对应门户 a40.js 里走的是 login_portal()，它提交的是「新一代」参数名：

        var data = {
            'login_method'  : page.login_method,
            'user_account'  : this.prefixAccount,      // ← 不是 DDDDD
            'user_password' : this.form.upass.value,   // ← 不是 upass
            'wlan_user_ip'  : term.ip,
            'wlan_user_ipv6': term.ipv6,
            'wlan_user_mac' : term.mac,
            'wlan_ac_ip'    : term.wlanacip,
            'wlan_ac_name'  : term.wlanacname,
            'jsVersion'     : jsVersion
        }
        login.portal_login(data, success, fail);
        // portal_login 再补上 terminal_type / lang，
        // 最后由 util._jsonp 追加 v=<随机数> 与 lang=zh

    而 v2.0 把老接口的 DDDDD / upass 发到了新接口上，于是服务端回：
        result=0  msg=无法获取用户认证账号！
    （日志里 2026-09-26 22:43 连试三轮，就是这个原因。）

    老参数名 DDDDD / upass 属于 login.login_portal 之外的 ruckus / 表单那条支路，
    与本套 login_method=1 的 JSONP 接口不是一回事。

    账号前缀：loadConfig 的 account_prefix = 0
        => prefixAccount = '' + 账号 + 运营商后缀（例：20230001@unicom）
           （只有当 account_prefix = 1 时才需要 ',0,' 前缀）
    密码形式：en_md5 = 0 => 明文提交，不做 MD5
        若将来变为 1，upass 需为 MD5(PID + 密码 + CALG) + CALG + PID
                          = MD5('1' + 密码 + '12345678') + '12345678' + '1'

    成功判定：JSONP 响应里 result == 1 或 result == 'ok'

    ★ v2.2 新增：状态变化时弹 Windows 通知 ★
    守护模式下只在「状态真的变了」时弹一条，不会每 60 秒刷屏：
        · 自动登录成功   ->  「校园网已自动登录」
        · 多轮重试仍失败 ->  「校园网自动登录失败」
    手动 -Once / -Force 不弹（控制台本来就看得到，再弹是打扰）。
    通知由同目录 notify.ps1 弹出，必须交给 Windows PowerShell 5.1 ——
    PS7 加载不了 WinRT 类型。notify.ps1 需带 UTF-8 BOM，勿去掉。

    ★ v2.3 新增：区分「不在校园网」与「登录被拒」★
    开机那一刻 Wi-Fi 往往还没连上，或人根本不在学校 —— 这时若照样重试登录，
    就会每次弹一条「登录失败」，既误报又刷屏。现在：
        · 门户(TCP 801)连不上 -> 判定为「不在校园网」，不尝试登录、不弹通知，
                                  安静等下一轮（日志只在状态变化时记一笔）
        · 门户连得上但登录被拒 -> 才算真失败，弹一条通知
        · 同一段离线期内失败通知只弹一条，联网恢复后才允许再报

    门户地址：脚本顶部 $PortalHost（怎么找见 README 第一节）
    认证系统：Dr.COM（城市热点）ePortal（login_method = 1 的 JSONP 接口那套）

.PARAMETER Once
    只检测/登录一次后退出（手动测试用）

.PARAMETER Force
    跳过在线检测，强制提交一次登录

.PARAMETER Diagnose
    只做连通性探测并打印每个探测目标的详细结果，不登录

.PARAMETER DryRun
    只打印将要发出的登录请求（密码以 *** 遮蔽），不真正提交。
    排查参数问题时用这个。

.PARAMETER IntervalSeconds
    常驻守护模式的检测间隔秒数，默认 60

.PARAMETER Quiet
    不向控制台输出，只写日志

.EXAMPLE
    .\campus-login.ps1 -Diagnose
    打印探测详情（排查用，零副作用）

.EXAMPLE
    .\campus-login.ps1 -DryRun
    看一眼实际会发出去的那串参数（不提交）

.EXAMPLE
    .\campus-login.ps1 -Once
    立即检测一次；若未登录则登录，然后退出。

.EXAMPLE
    .\campus-login.ps1
    常驻守护模式：每 60 秒检测一次，掉线自动重登（开机自启用这个）。

.NOTES
    · 密码只保存在本脚本或同目录 password.txt 中，不上传、不打印。
    · 版本 2.3
    · 最初为作者本校的校园网而写，现整理开源。
#>
[CmdletBinding()]
param(
    [switch]$Once,
    [switch]$Force,
    [switch]$Diagnose,
    [switch]$DryRun,
    [int]$IntervalSeconds = 60,
    [switch]$Quiet
)

# ============================================================================
#  配置区 —— 第一次使用只需要改这一段
# ============================================================================

# ★必填★ 账号（学号/工号），不含运营商后缀，例：20230001
$Account = ''

# 运营商选择 —— 名称与门户页面「服务类型」选项逐字一致：
#   '校园网'     ->  无后缀
#   '中国联通'   ->  @unicom
#   '中国移动'   ->  @cmcc
#   '中国电信'   ->  @telecom
#   （为省事，简称与英文也照样认：联通/unicom、移动/cmcc、电信/telecom、校园网/campus）
$Carrier = '校园网'

# 密码：两种填法，任选其一
#   填法 A（简单）：直接写在下面这行的引号里
#   填法 B（推荐）：留空，改为把密码写进同目录的 password.txt（脚本会自动读取）
$Password = ''

# 登录时上报的本机地址（一般留空，脚本自动探测）
#   自动探测逻辑：把本机每个候选 IPv4 依次绑定为源地址去连门户 801 端口，
#   第一个连得通的，就是 AC 那边看到的地址。
#   只有在自动探测失准时（比如挂了 TUN 模式的代理）才需要手工钉死，
#   写成 '192.168.1.100' 这种形式。
$WlanUserIp  = ''

# 登录时上报的本机 MAC（一般留空 = 自动取上面那个地址所属网卡的 MAC）
$WlanUserMac = ''

# ★必填★ 校园网认证门户的地址（IP 或域名，不要带 http:// 和端口）
#   怎么找：未登录时用浏览器打开任意 http 网站，会被跳转到认证页，
#           地址栏里那个 IP / 域名就是（例：10.0.0.1）
$PortalHost = ''

# 门户 HTTP 端口（Dr.COM ePortal 通常是 801；若你的门户在 80 端口就改成 80）
$PortalPort = 801

# 调优参数（一般不用改）
$LoginRetryCount   = 3      # 登录最多尝试几轮
$PostLoginWaitSec  = 45     # 每轮登录后最多等待多少秒放行
$PostLoginPollSec  = 5      # 轮询间隔秒数

# ============================================================================


# ------------------------------ 固定参数 ------------------------------------
# （$PortalHost / $PortalPort 已挪到上面的「配置区」，请在那里填写）
# （同上）

# ★ 真实登录接口（JSONP GET）
#   由门户源码推导：portal_api = protocol//host:801/eportal/portal/
#                   var url = (page.login_method == 0 ? page.path : page.portal_api) + 'login';
#   实测返回 {"result","msg","ret_code"} 结构。
$LoginUrls = @(
    ('http://{0}:{1}/eportal/portal/login' -f $PortalHost, $PortalPort)
)

# 门户自己用的前端版本号，原样上报（util._jsonp 会校验它存不存在）
$JsVersion = '4.1.3'

$ScriptDir    = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$PasswordFile = Join-Path $ScriptDir 'password.txt'
$LogFile      = Join-Path $ScriptDir 'campus-login.log'
$NotifyScript = Join-Path $ScriptDir 'notify.ps1'
$MaxLogBytes  = 1MB

# 通知开关：只有在「守护模式」下才打开。
# 手动 -Once / -Force 不弹 —— 那时控制台窗口本来就看得到，再弹一条是打扰。
$script:NotifyEnabled = $false

# 失败通知去重：同一段「离线期」内只弹一条失败通知，否则每 60 秒一条会把人烦死。
# 联网恢复后会重置，允许下次掉线再报一次。
$script:LoginFailureNotified = $false

# 探测目标：任一个判定为「在线」即认为网络已通
# 用多个目标是为了降低误判（单一站点抽风会误触发重登）
$ProbeUrls = @(
    'http://connect.rom.miui.com/generate_204',
    'http://www.baidu.com'
)

$CarrierMap = @{
    '校园网' = '';          'campus'  = ''
    '联通'   = '@unicom';   'unicom'  = '@unicom';  '中国联通' = '@unicom'
    '移动'   = '@cmcc';     'cmcc'    = '@cmcc';    '中国移动' = '@cmcc'
    '电信'   = '@telecom';  'telecom' = '@telecom'; '中国电信' = '@telecom'
}

# MD5 认证参数（来自门户 a43.js：var PID='1'; var CALG='12345678';）
# 当前 en_md5=0，用不到；留在这里以备学校改成 1
$Md5Pid  = '1'
$Md5Calg = '12345678'

# ------------------------------ 日志 ----------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not $Quiet) {
        $color = switch ($Level) {
            'OK'    { 'Green' }
            'WARN'  { 'Yellow' }
            'ERROR' { 'Red' }
            default { 'Gray' }
        }
        Write-Host $line -ForegroundColor $color
    }
    try {
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt $MaxLogBytes) {
            Move-Item -Path $LogFile -Destination ($LogFile + '.1') -Force
        }
        Add-Content -Path $LogFile -Value $line -Encoding utf8 -ErrorAction Stop
    } catch { }
}

# ------------------------------ 通知 ----------------------------------------
# 弹一条 Windows 通知。任何失败都只记日志，绝不影响登录流程。
function Send-Notify {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Body = ''
    )
    if (-not $script:NotifyEnabled)     { return }
    if (-not (Test-Path $NotifyScript)) { return }

    try {
        # ★ PS7 加载不了 WinRT 类型，弹通知必须交给 Windows PowerShell 5.1
        $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path $ps51)) { $ps51 = 'powershell.exe' }

        # 逐项手工加引号：Start-Process 只是用空格把参数拼起来，
        # 标题/正文里带空格的话不加引号会被拆成多个参数。
        $argList = @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File',  ('"' + $NotifyScript + '"'),
            '-Title', ('"' + $Title + '"'),
            '-Body',  ('"' + $Body + '"')
        )
        Start-Process -FilePath $ps51 -ArgumentList $argList -WindowStyle Hidden | Out-Null
        Write-Log ("已发出通知：$Title") 'INFO'
    } catch {
        Write-Log ('通知发送失败（不影响登录）：' + $_.Exception.Message) 'WARN'
    }
}

# ---------------------- 组装完整账号（含运营商后缀）------------------------
function Get-FullAccount {
    if ($Account -match '@') { return $Account }   # 已经带后缀，直接用
    $key = $Carrier.Trim()
    if (-not $CarrierMap.ContainsKey($key)) {
        Write-Log ("运营商 '$Carrier' 无法识别，将按『校园网』(无后缀) 处理。可选：校园网 / 联通 / 移动 / 电信") 'WARN'
        return $Account
    }
    return ($Account + $CarrierMap[$key])
}

# ------------------------- 读取密码（含文件回退）---------------------------
function Get-PortalPassword {
    if (-not [string]::IsNullOrWhiteSpace($Password)) { return $Password.Trim() }
    if (Test-Path $PasswordFile) {
        $p = Get-Content -Path $PasswordFile -Raw -ErrorAction SilentlyContinue
        if ($p) {
            # 去掉换行与可能的 UTF-8 BOM（BOM 会让密码首字符变脏，登录静默失败）
            return $p.Trim().TrimStart([char]0xFEFF)
        }
    }
    return ''
}

# --------------- 门户是否可达（区分「登录被拒」与「不在校园网」）-----------
# 只做一次 TCP 801 连接，不发任何认证请求。
function Test-PortalReachable {
    $c = $null
    try {
        $c = [System.Net.Sockets.TcpClient]::new()
        $task = $c.ConnectAsync($PortalHost, $PortalPort)
        return ($task.Wait(3000) -and $c.Connected)
    } catch {
        return $false
    } finally {
        if ($c) { try { $c.Dispose() } catch { } }
    }
}

# --------------------- 探测「AC 看到的那个本机地址」------------------------
# 做法：把每个候选 IPv4 依次绑定为源地址，去连门户的 801 端口；
#       能连上的那个，就是真正走得通的那块网卡的地址（也就是 AC 记的地址）。
#       这比「挑名字像 WLAN 的网卡」可靠 —— 挂代理 / 多网卡时尤其明显。
function Get-PortalLocalIp {
    if (-not [string]::IsNullOrWhiteSpace($WlanUserIp)) { return $WlanUserIp.Trim() }
    if ($script:PortalLocalIp) { return $script:PortalLocalIp }   # 一次进程内只探一次

    $cands = @()
    try {
        $cands = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*' -and
                $_.AddressState -eq 'Preferred'
            } |
            Select-Object -ExpandProperty IPAddress -Unique)
    } catch { }

    # 优先保证校园网自己那块网卡排在前面（多数情况就是 WLAN）
    $sorted = @($cands | Where-Object { $_ -notlike '192.168.137.*' }) +
              @($cands | Where-Object { $_ -like '192.168.137.*' })

    foreach ($ip in $sorted) {
        $c = $null
        try {
            $c = [System.Net.Sockets.TcpClient]::new()
            $c.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($ip), 0))
            $task = $c.ConnectAsync($PortalHost, $PortalPort)
            if ($task.Wait(1500) -and $c.Connected) {
                $script:PortalLocalIp = $ip
                return $ip
            }
        } catch { } finally {
            if ($c) { try { $c.Dispose() } catch { } }
        }
    }

    # 兜底：让系统按路由表选源地址（UDP connect 不发包，只做路由查询）
    try {
        $sock = [System.Net.Sockets.Socket]::new(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp)
        try {
            $sock.Connect($PortalHost, $PortalPort)
            $ip = $sock.LocalEndPoint.Address.ToString()
            if ($ip -and $ip -notlike '0.*' -and $ip -notlike '127.*') {
                $script:PortalLocalIp = $ip
                return $ip
            }
        } finally { $sock.Dispose() }
    } catch { }

    Write-Log '未能探测到用于登录的本机地址（wlan_user_ip）。若登录报『无法获取用户认证账号』，请手工设置 $WlanUserIp。' 'WARN'
    return ''
}

# 取某个本机地址所属网卡的 MAC（去掉分隔符，小写；门户就是这么传的）
function Get-LocalMacForIp {
    param([string]$Ip)
    if (-not [string]::IsNullOrWhiteSpace($WlanUserMac)) { return ($WlanUserMac -replace '[-:]', '').ToLower() }
    if ([string]::IsNullOrWhiteSpace($Ip)) { return '000000000000' }
    try {
        $a = Get-NetIPAddress -IPAddress $Ip -ErrorAction Stop | Select-Object -First 1
        $n = Get-NetAdapter -InterfaceIndex $a.InterfaceIndex -ErrorAction Stop
        $m = ($n.MacAddress -replace '[-:]', '')
        if ($m) { return $m.ToLower() }
    } catch { }
    return '000000000000'
}

# ------------------- 构造登录参数（严格照抄门户 login_portal）--------------
function New-LoginFields {
    param([Parameter(Mandatory)][string]$PlainPassword)

    $ip  = Get-PortalLocalIp
    $mac = Get-LocalMacForIp -Ip $ip

    # 顺序与门户一致；
    # util._jsonp 会把 callback 提到最前，并在末尾追加 v=<随机数> 与 lang=zh
    [ordered]@{
        'callback'       = 'jsonpReturn'
        'login_method'   = '1'
        'user_account'   = (Get-FullAccount)
        'user_password'  = $PlainPassword
        'wlan_user_ip'   = $ip
        'wlan_user_ipv6' = ''
        'wlan_user_mac'  = $mac
        'wlan_ac_ip'     = ''
        'wlan_ac_name'   = ''
        'jsVersion'      = $JsVersion
        'terminal_type'  = '1'          # 1=PC  2=手机
        'lang'           = 'zh-cn'
        'v'              = (Get-Random -Minimum 1000000000 -Maximum 2147483647)
    }
}

function ConvertTo-QueryString {
    param([Parameter(Mandatory)]$Fields)
    return (($Fields.GetEnumerator() | ForEach-Object {
        [System.Uri]::EscapeDataString($_.Key) + '=' + [System.Uri]::EscapeDataString([string]$_.Value)
    }) -join '&')
}

# --------------------------- 单个目标的探测 --------------------------------
# 返回 @{ Online = <bool>; Reason = <string> }
function Test-OneUrl {
    param([Parameter(Mandatory)][string]$Url)

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client  = [System.Net.Http.HttpClient]::new($handler)
    try {
        $handler.AllowAutoRedirect = $false
        $handler.UseProxy          = $false
        $client.Timeout            = [TimeSpan]::FromSeconds(6)

        $resp = $client.GetAsync($Url).GetAwaiter().GetResult()
        $code = [int]$resp.StatusCode

        if ($code -eq 204) { return @{ Online = $true; Reason = 'HTTP 204（标准在线应答）' } }

        $loc = ''
        if ($null -ne $resp.Headers.Location) { $loc = $resp.Headers.Location.ToString() }

        if ($loc -match [regex]::Escape($PortalHost)) {
            return @{ Online = $false; Reason = "被 302 重定向到认证门户 $loc" }
        }
        if ($code -ge 300 -and $code -lt 400) {
            return @{ Online = $false; Reason = "HTTP $code 重定向到 $loc" }
        }
        if ($code -eq 200) {
            $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($text -match 'Dr\.COM|eportal|ACSetting|注销页|信息页') {
                return @{ Online = $false; Reason = 'HTTP 200 但内容实为门户页（HTTP 劫持）' }
            }
            return @{ Online = $true; Reason = 'HTTP 200（正常响应）' }
        }
        return @{ Online = $false; Reason = "HTTP $code" }
    } catch {
        $msg = $_.Exception.Message
        if ($_.Exception.InnerException) { $msg = $msg + ' << ' + $_.Exception.InnerException.Message }
        return @{ Online = $false; Reason = '请求异常: ' + $msg }
    } finally {
        try { $client.Dispose()  } catch { }
        try { $handler.Dispose() } catch { }
    }
}

# --------------------------- 外网连通性检测 --------------------------------
function Test-NetOnline {
    param([switch]$Explain)
    foreach ($u in $ProbeUrls) {
        $r = Test-OneUrl -Url $u
        if ($Explain) { Write-Log ("探测 $u => " + $r.Reason) 'INFO' }
        if ($r.Online) { return $true }
    }
    return $false
}

# -------------------- 登录后轮询等待 AC 真正放行 ---------------------------
function Wait-NetOnline {
    param(
        [int]$TimeoutSeconds = 45,
        [int]$PollSeconds    = 5
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds $PollSeconds
        if (Test-NetOnline) {
            Write-Log ('AC 已放行，复验通过（等待约 ' + [int]$sw.Elapsed.TotalSeconds + ' 秒）') 'OK'
            return $true
        }
    }
    return $false
}

# ------------------------------ 提交登录 ------------------------------------
function Invoke-PortalLogin {
    param([switch]$Preview)

    $pwd = Get-PortalPassword
    if ([string]::IsNullOrWhiteSpace($pwd)) {
        Write-Log "密码未填写。请编辑本脚本顶部的 \$Password，或把密码写入 $PasswordFile" 'ERROR'
        return $false
    }

    $full   = Get-FullAccount
    $fields = New-LoginFields -PlainPassword $pwd
    $qs     = ConvertTo-QueryString -Fields $fields

    if ($Preview) {
        # 只把密码遮掉，其余原样打印，方便肉眼核对参数名
        $masked = $qs -replace ('user_password=' + [regex]::Escape([System.Uri]::EscapeDataString($pwd))), 'user_password=***'
        Write-Log "账号=$full  运营商=$Carrier  密码长度=$($pwd.Length)" 'INFO'
        Write-Log "wlan_user_ip=$($fields['wlan_user_ip'])  wlan_user_mac=$($fields['wlan_user_mac'])" 'INFO'
        Write-Host ''
        Write-Host ("  GET " + $LoginUrls[0] + '?' + $masked) -ForegroundColor Cyan
        Write-Host ''
        return $true
    }

    # 只记录长度，绝不打印密码
    Write-Log ("提交登录(GET JSONP)：账号=$full  运营商=$Carrier  密码长度=$($pwd.Length)  wlan_user_ip=$($fields['wlan_user_ip'])") 'INFO'

    # 依次尝试候选接口，取第一个返回 200 的
    $code = 0; $body = ''; $usedUrl = ''
    foreach ($base in $LoginUrls) {
        $url = $base + '?' + $qs
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $client  = [System.Net.Http.HttpClient]::new($handler)
        try {
            $handler.AllowAutoRedirect = $true
            $handler.UseProxy          = $false
            $client.Timeout            = [TimeSpan]::FromSeconds(15)
            $resp = $client.GetAsync($url).GetAwaiter().GetResult()
            $code = [int]$resp.StatusCode
            $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $usedUrl = $base
        } catch {
            Write-Log ('登录请求异常（' + $base + '）：' + $_.Exception.Message) 'WARN'
            $code = 0; $body = ''
        } finally {
            try { $client.Dispose()  } catch { }
            try { $handler.Dispose() } catch { }
        }
        if ($code -eq 200 -and $body) { break }
        Write-Log ("$base 返回 HTTP $code，尝试下一个候选接口") 'WARN'
    }

    if ($code -ne 200) {
        Write-Log '所有候选登录接口均未返回 200。' 'ERROR'
        return $false
    }
    Write-Log ("使用登录接口：$usedUrl") 'INFO'

    # 剥掉 JSONP 外壳： jsonpReturn({...})
    $jsonText = $body
    $jm = [regex]::Match($body, '^\s*[A-Za-z_$][\w$]*\s*\((\{.*\})\)\s*;?\s*$', 'Singleline')
    if ($jm.Success) { $jsonText = $jm.Groups[1].Value }

    $obj = $null
    try { $obj = $jsonText | ConvertFrom-Json } catch { }

    if ($null -eq $obj) {
        $short = $body
        if ($short.Length -gt 300) { $short = $short.Substring(0, 300) + '...' }
        Write-Log ("登录响应无法解析为 JSON，原文：$short") 'WARN'
        return $false
    }

    $result = $obj.result
    $msg    = $obj.msg

    if ($result -eq 1 -or $result -eq 'ok') {
        Write-Log ('登录接口报成功（result=' + $result + '），等待 AC 放行...') 'INFO'
        return $true
    }

    # 服务端说本机地址「已经在线」：多半是网络在我们探测之后自己恢复了。
    # 这不该算登录失败 —— 否则会白发一条失败通知。复检外网再定论。
    if ("$msg" -match '已经在线') {
        if (Test-NetOnline) {
            Write-Log '服务端报本机地址已在线，且外网实测已通 —— 视为已登录。' 'OK'
            return $true
        }
        Write-Log '服务端报本机地址已在线，但外网实测仍不通。' 'WARN'
        return $false
    }

    Write-Log ("登录失败：result=$result  msg=$msg") 'WARN'
    if ($obj | Get-Member -Name 'ret_code' -ErrorAction SilentlyContinue) {
        Write-Log ('  ret_code=' + $obj.ret_code) 'WARN'
    }
    if ("$msg" -match '无法获取用户认证账号') {
        Write-Log '  ↑ 这个报错=服务端没收到账号参数。检查 user_account 参数名与 $WlanUserIp。' 'WARN'
    }
    return $false
}

# ------------------------------ 检测并登录 ----------------------------------
function Invoke-CheckAndLogin {
    param([switch]$SkipProbe)

    if (-not $SkipProbe -and (Test-NetOnline)) {
        return @{ Online = $true; Action = 'none' }
    }

    # 门户都连不上 -> 这不是「登录失败」，而是「压根不在校园网」
    # （刚开机 Wi-Fi 还没连上，或人在校外）。此时不尝试登录，更不弹失败通知。
    if (-not (Test-PortalReachable)) {
        return @{ Online = $false; Action = 'portal-unreachable' }
    }

    for ($attempt = 1; $attempt -le $LoginRetryCount; $attempt++) {
        if ($attempt -gt 1) { Write-Log ("—— 开始第 $attempt 轮尝试 ——") 'INFO' }

        $ok = Invoke-PortalLogin
        if (-not $ok) {
            if ($attempt -lt $LoginRetryCount) { Start-Sleep -Seconds 3 }
            continue
        }

        # 接口报成功后，轮询等待 AC 真正放行（这是 v1.0 缺失的关键一步）
        if (Wait-NetOnline -TimeoutSeconds $PostLoginWaitSec -PollSeconds $PostLoginPollSec) {
            Send-Notify -Title '校园网已自动登录' -Body ($fullAccount + ' 已重新上线')
            return @{ Online = $true; Action = 'login-ok' }
        }

        Write-Log ("第 $attempt 轮登录接口报成功，但 $PostLoginWaitSec 秒内 AC 仍未放行。") 'WARN'
        if ($attempt -lt $LoginRetryCount) { Start-Sleep -Seconds 3 }
    }

    Write-Log '多轮尝试后仍未恢复联网。请检查：账号是否被其它设备占用 / 套餐时长是否耗尽 / WLAN 是否已连接。' 'ERROR'
    # 一段离线期只弹一条失败通知，否则每 60 秒一条会把人烦死
    if (-not $script:LoginFailureNotified) {
        Send-Notify -Title '校园网自动登录失败' -Body '多次重试仍未联网，请查看 campus-login.log'
        $script:LoginFailureNotified = $true
    } else {
        Write-Log '（本段离线期内已发过失败通知，不再重复弹）' 'INFO'
    }
    return @{ Online = $false; Action = 'login-failed' }
}

# ================================ 主流程 ====================================
# ---------------------------- 必填项校验 ------------------------------------
# 没填完就别往下走 —— 否则会拿空账号去请求门户，报错还很难懂。
$missing = @()
if ([string]::IsNullOrWhiteSpace($Account))    { $missing += '  $Account    —— 你的学号 / 工号（不含运营商后缀）' }
if ([string]::IsNullOrWhiteSpace($PortalHost)) { $missing += '  $PortalHost —— 校园网认证门户的地址（IP 或域名）' }
if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host '  [X] 还没配置好，请先编辑本脚本顶部的「配置区」：' -ForegroundColor Yellow
    foreach ($m in $missing) { Write-Host $m -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '  $PortalHost 怎么找：' -ForegroundColor DarkGray
    Write-Host '    未登录时用浏览器打开任意 http 网站，会被跳转到认证页，' -ForegroundColor DarkGray
    Write-Host '    地址栏里那个 IP / 域名就是。' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  密码请写进同目录 password.txt（双击 1-填写密码.bat）。' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}
$fullAccount = Get-FullAccount
if (-not $Quiet) {
    Write-Host ''
    Write-Host '  校园网自动登录（Dr.COM ePortal） v2.3' -ForegroundColor Cyan
    Write-Host "  门户：http://$PortalHost/" -ForegroundColor DarkGray
    Write-Host "  接口：$($LoginUrls[0])" -ForegroundColor DarkGray
    Write-Host "  账号：$fullAccount" -ForegroundColor DarkGray
    Write-Host ''
}

if ($Diagnose) {
    Write-Log '=== 连通性诊断（只探测，不登录）===' 'INFO'
    foreach ($u in $ProbeUrls) {
        $r = Test-OneUrl -Url $u
        Write-Log ("$u => 在线=$($r.Online)  $($r.Reason)") 'INFO'
    }
    Write-Log ("综合判定：" + $(if (Test-NetOnline) { '在线' } else { '未在线' })) 'INFO'
    exit
}

if ($DryRun) {
    Write-Log '=== 预演：只打印请求，不提交 ===' 'INFO'
    $r = Invoke-PortalLogin -Preview
    if (-not $r) { exit 1 }
    exit
}

if ($Once -or $Force) {
    Write-Log ("单次运行开始（Force=$Force）") 'INFO'
    $r = Invoke-CheckAndLogin -SkipProbe:$Force
    if ($r.Action -eq 'none') {
        Write-Log '网络在线，无需登录。' 'OK'
    } elseif ($r.Action -eq 'portal-unreachable') {
        Write-Log ("校园网门户 ${PortalHost}:${PortalPort} 不可达，未尝试登录（Wi-Fi 没连上，或不在校园网）。") 'WARN'
    }
    exit
}

# 常驻守护模式：状态变化时才写日志，避免刷屏
$script:NotifyEnabled = $true      # 只有守护模式才弹通知
Write-Log ("守护模式启动，检测间隔 ${IntervalSeconds} 秒。通知已启用。") 'INFO'
$lastOnline = $null
while ($true) {
    try {
        $nowOnline = Test-NetOnline
        if ($nowOnline) {
            if ($lastOnline -eq $false) { Write-Log '网络已恢复。' 'OK' }
            $lastOnline = $true
            $script:LoginFailureNotified = $false     # 恢复联网，下次掉线可以再报一次
        } else {
            if ($lastOnline -ne $false) { Write-Log '检测到未登录状态，尝试自动登录...' 'WARN' }
            $r = Invoke-CheckAndLogin -SkipProbe
            if ($r.Action -eq 'portal-unreachable') {
                # 不在校园网（或 Wi-Fi 还没连上）：安静等着，不当作登录失败
                if ($lastOnline -ne 'unreachable') {
                    Write-Log '校园网门户不可达（Wi-Fi 未连接或不在校园网），暂不尝试登录。' 'INFO'
                }
                $lastOnline = 'unreachable'
            } else {
                $lastOnline = [bool]$r.Online
            }
        }
    } catch {
        Write-Log ('循环内异常：' + $_.Exception.Message) 'ERROR'
    }
    Start-Sleep -Seconds $IntervalSeconds
}
