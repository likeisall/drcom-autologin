<#
.SYNOPSIS
    校园网（Dr.COM ePortal）自动登录 / 保活脚本  v3.4

.DESCRIPTION
    工作流程：
      1. 探测外网连通性（多目标，任一通过即算在线）
      2. 若被重定向到认证门户或响应含门户特征 => 判定为「未登录」
      3. 自动向真实登录接口提交账号密码
      4. 登录接口报成功后，轮询等待 AC 真正放行（默认最多 45 秒）
      5. 仍不通过则自动重试登录（默认最多 3 轮）

    ★ v3.4 新增：换号成功改用蓝色徽章 ★

    2026-10-01 定：换号成功与「主账号被拒」原先共用黄色，两件事一个色容易混，
    换号成功改**蓝底白对号**（icons\blue.png）。四档颜色各司其职：

         green  绿✓  校园网 · 已自动登录       用当前账号正常登回
         blue   蓝✓  校园网 · 已切换账号上网   主账号被拒、已换到下一个账号并成功
         yellow 黄!  校园网 · 主账号登录失败   主账号被拒，单独提醒（主号自己的坏消息）
         red    红✗  校园网 · 所有账号都登不上 全部失败，需要人工处理

    另外明确：**若设置里只有主账号（没有备选），就直接弹红色的「都登不上」**，
    不再来一条黄色的主账号失败 —— 只有一个账号时红色那条本来就把原因列全了。
    对应代码里的 `$accts.Count -gt 1` 这个条件，不是优化，是规则。

    ★ v3.3 新增：通知上色 + 主账号失败单独提醒 ★

    ① 四种通知（文案用「要点式」，颜色见上面 v3.4 那张表）：

        ⚠️ Windows 的 Toast **没有「整条通知着色」的接口**，卡片底色由系统主题决定。
           能上色的只有卡片左侧那张大图：icons\ 下的同色徽章
           （green|blue|yellow|red.png：绿✓ / 蓝✓ / 黄! / 红✗）。
           标题保持干净 —— 看过实物后说「有了大图标，那些小圆点就去掉吧」。
           唯独图标文件丢失时才退回标题圆点垫一下，免得整条通知没颜色。

    ② 「主账号登录失败」是单独一条：
       · 只在表里**还有别的账号可换**时弹（明确约定的规则，见 v3.4 那段）
       · 同一段离线期内只弹一次（`$script:PrimaryFailureNotified`），联网恢复后重置

    ★ v3.2 新增：手动测试也弹通知 + 账号表热重载 ★

    ① 以前双击 2-测试登录.bat（-Once / -Force）刻意不弹通知，理由是「控制台看得到就行」。
       有人反映这样没法验证通知本身，现在手动测试同样弹 —— 反正只有**真发生登录**
       才会有通知（「网络在线，无需登录」时依旧安静）。
       -Diagnose / -DryRun 不涉及登录，始终不弹。

    ② 守护进程每次要重登前都会重读 accounts.txt：
       改密码 / 加账号 / 换运营商，**保存即生效**，不必重启电脑或守护进程。

    ★ v3.1 新增：账号和密码合到一个文件 ★

    以前「账号在脚本配置区、密码在 password.txt」，改一个账号要动两处。
    现在账号密码都在同目录的 accounts.txt 里，一行一个：

        学号|运营商|密码|名字(可选)

    双击「1-填写账号和密码.bat」编辑；文件不在时会自动生成带说明的模板。
    脚本本体不再存放任何账号信息。格式说明见「配置区」。

    ⚠️ 运营商是**逐行独立**的，不同账号可以走不同运营商，不要照抄上一行。
       例：主账号走校园网(无后缀)，备选账号走中国联通(@unicom)。

    ★ v3.0 新增：多账号 + 欠费停机自动换号 ★

    账号表按优先级从上到下。
    平时用「当前账号」（每次开机时 = 表里第 1 行 = 主账号）：

        · 当前账号被服务端「硬拒绝」（欠费停机 / 密码错误 / 账号被锁 /
          时长耗尽 / 账号不存在……）-> 立刻改用列表里的下一个账号，并弹通知
        · 网络类临时故障（超时、接口报成功但 AC 不放行）-> 不换号，只重试
        · 换成备选账号后，**本机重启前一直用它**（2026-10-01 定的规则）：
          不再回头撞主账号，免得停机期间每 60 秒白试一次；
          充完值重启电脑，就从主账号重新开始

    判定依据是服务端返回的 msg 字段是否命中 $HardFailurePatterns 里的关键词。
    怕误判就把关键词往宽了写 —— 命中只是「换个账号试试」，并不会注销任何东西。

    ★ v3.0：通知内容重写 ★

    三种时机各弹一条，正文写全「是谁、为什么、换成了谁、什么时候」：

        自动登录成功   -> 标题「校园网 · 已自动登录」
                          正文 账号 / 状态 / 时间
        换号后成功     -> 标题「校园网 · 已切换账号上网」
                          正文 原账号 / 失败原因 / 改用账号 / 生效范围 / 时间
        所有账号都失败 -> 标题「校园网 · 所有账号都登不上」
                          正文 逐个账号列出失败原因 + 处理建议 + 时间

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
        => prefixAccount = '' + 账号 + 运营商后缀，即 20230001@unicom
           （只有当 account_prefix = 1 时才需要 ',0,' 前缀）
    密码形式：en_md5 = 0 => 明文提交，不做 MD5
        若将来变为 1，upass 需为 MD5(PID + 密码 + CALG) + CALG + PID
                          = MD5('1' + 密码 + '12345678') + '12345678' + '1'

    成功判定：JSONP 响应里 result == 1 或 result == 'ok'

    ★ v2.3：区分「不在校园网」与「登录被拒」★
    开机那一刻 Wi-Fi 往往还没连上，或人根本不在学校 —— 这时若照样重试登录，
    就会每次弹一条「登录失败」，既误报又刷屏。现在：
        · 门户(TCP 801)连不上 -> 判定为「不在校园网」，不尝试登录、不弹通知，
                                  安静等下一轮（日志只在状态变化时记一笔）
        · 门户连得上但登录被拒 -> 才算真失败，弹一条通知
        · 同一段离线期内失败通知只弹一条，联网恢复后才允许再报

    门户地址：脚本顶部 $PortalHost（怎么找见 README 第一节）
    认证系统：Dr.COM（城市热点）ePortal

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
    · 账号与密码只保存在本机 accounts.txt 里，不上传、不打印。
    · 版本 3.4
    · 本脚本最初为作者本校的校园网而写，现整理开源。
#>
[CmdletBinding()]
param(
    [switch]$Once,
    [switch]$Force,
    [switch]$Diagnose,
    [switch]$DryRun,
    [int]$IntervalSeconds = 60,
    [switch]$Quiet,
    [switch]$InitAccountFile
)

# ============================================================================
#  配置区 —— 第一次使用只需要改这一段
# ============================================================================

# ---------------------- 账号与密码（同一个文件里）---------------------------
# ★ v3.1：账号和密码不再分家，统统写在同一个文件 accounts.txt 里。
#         双击「1-填写账号和密码.bat」就能编辑它。
#
#   一行一个账号，格式：   学号|运营商|密码|名字(可选)
#
#   例如：
#       20230001|校园网|你的密码|主账号
#       20230002|中国联通|另一个密码|备选账号   ← 运营商逐行自己填，可以不一样
#
#   · 以 # 开头的是注释行，空行忽略
#   · 运营商：校园网 / 中国联通 / 中国移动 / 中国电信
#             （简称也认：campus / 联通 / unicom / 移动 / cmcc / 电信 / telecom）
#   · ⚠️ 每个账号的运营商**可以各不相同**，逐行自己填，不要照抄上一行！
#         本机实际是：主账号走中国联通(@unicom)，备选账号走校园网(无后缀)
#   · 从上到下就是使用优先级：第 1 行是主账号，后面都是备选账号
#   · 名字可以省略；省略时通知里显示「账号1」「账号2」
#   · 只想用一个账号？只写一行就行
#   · 文件名不能改；文件不在的话，脚本会提示你双击那个 .bat 生成
#
#   ⚠️ 密码里不能含 | 这个竖线（它是分隔符）。
$AccountFileName = 'accounts.txt'

# 登录时上报的本机地址（一般留空，脚本自动探测）
#   自动探测逻辑：把本机每个候选 IPv4 依次绑定为源地址去连门户 801 端口，
#   第一个连得通的，就是 AC 那边看到的地址。
#   只有在自动探测失准时（比如挂了 TUN 模式的代理）才需要手工钉死，
#   写成 '172.16.0.100' 这种形式。
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
$LoginRetryCount   = 3      # 每个账号最多尝试几轮
$PostLoginWaitSec  = 45     # 每轮登录后最多等待多少秒放行
$PostLoginPollSec  = 5      # 轮询间隔秒数

# ============================================================================


# ------------------------------ 固定参数 ------------------------------------
# （$PortalHost / $PortalPort 在「配置区」，请在那里填写）

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
$AccountFile  = Join-Path $ScriptDir $AccountFileName
$LogFile      = Join-Path $ScriptDir 'campus-login.log'
$NotifyScript = Join-Path $ScriptDir 'notify.ps1'
$MaxLogBytes  = 1MB

# 通知开关：默认关，进入「守护模式」或手动 -Once / -Force 时打开。
# （-Diagnose / -DryRun 不涉及登录，始终不弹）
# ★ v3.2：以前手动测试刻意不弹（「控制台看得到就行」），结果没法用它验证通知本身，
#         现在手动测试同样弹 —— 反正只有真发生登录才会有通知。
$script:NotifyEnabled = $false

# 失败通知去重：同一段「离线期」内只弹一条失败通知，否则每 60 秒一条会把人烦死。
# 联网恢复后会重置，允许下次掉线再报一次。
$script:LoginFailureNotified = $false

# ★ v3.3：「主账号登录失败」单独提醒的去重标志。
#   同样是一段离线期内只弹一条 —— 主账号多半是停机，每 60 秒弹一次会疯。
$script:PrimaryFailureNotified = $false

# 当前生效的账号（在内存里，进程结束即失效 —— v3.0 的「重启后重试主账号」就靠这个）
$script:ActiveAccounts     = @()
$script:ActiveAccountIndex = 0

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

# ★ 硬拒绝关键词（v3.0）★
#   服务端 msg 命中任意一个 => 这个账号本身不能用了 => 立刻换下一个账号，
#   不再把剩下的重试轮次浪费在它身上。
#   依据：README 记录的实测报错「该账号已停机」等。
#   ⚠️ 故意不含「已经在线」：那说的是本机地址，不是账号问题（见 Invoke-PortalLogin 里的特殊分支）。
$HardFailurePatterns = @(
    '停机', '欠费', '余额不足', '缴费',
    '已过期', '过期', '到期',
    '时长耗尽', '时长已用完', '时长不足',
    '流量耗尽', '流量已用完', '流量不足',
    '密码错误', '密码不正确', '密码有误', '认证失败',
    '账号不存在', '用户不存在', '未注册', '未开通',
    '已锁定', '被锁定', '已停用', '已禁用', '已销户'
)

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
# $Body 可以传多行（字符串数组），每一行在通知里单独成行。
# $Accent 是颜色标记（v3.4）：green=正常登回 / blue=换号成功 / yellow=主账号被拒 / red=全失败
function Send-Notify {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string[]]$Body = @(),
        [ValidateSet('none', 'green', 'blue', 'yellow', 'red')][string]$Accent = 'none'
    )
    if (-not $script:NotifyEnabled)     { return }
    if (-not (Test-Path $NotifyScript)) { return }

    try {
        # ★ PS7 加载不了 WinRT 类型，弹通知必须交给 Windows PowerShell 5.1
        $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path $ps51)) { $ps51 = 'powershell.exe' }

        # ★ v3.0：标题与正文用 Base64 传递。
        #   正文是多行中文，若照老办法手工加引号拼参数，
        #   Start-Process 只会用空格拼接，换行/空格/引号都可能被拆坏。
        #   Base64 只含 A-Za-z0-9+/=，没有任何空格，绝对不会被拆。
        $titleB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Title))
        $bodyB64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Body -join "`n")))

        $argList = @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', ('"' + $NotifyScript + '"'),
            '-TitleB64', $titleB64,
            '-BodyB64',  $bodyB64,
            '-Accent',   $Accent
        )
        Start-Process -FilePath $ps51 -ArgumentList $argList -WindowStyle Hidden | Out-Null
        Write-Log ("已发出通知[$Accent]：$Title") 'INFO'
    } catch {
        Write-Log ('通知发送失败（不影响登录）：' + $_.Exception.Message) 'WARN'
    }
}

# ---------------- 读取账号密码表 accounts.txt（v3.1 枪弹合一）---------------
# 一行一个账号：学号|运营商|密码|名字(可选)
# 返回规范化对象数组；解析不了的行走日志里说明，不中断整个脚本。
function Read-Accounts {
    $list = @()
    if (-not (Test-Path $AccountFile)) {
        Write-Log ("找不到账号文件：$AccountFile") 'ERROR'
        Write-Log '请双击同目录的「1-填写账号和密码.bat」，它会自动生成模板并打开记事本。' 'ERROR'
        return ,$list
    }

    $lines = @(Get-Content -Path $AccountFile -ErrorAction SilentlyContinue)
    $no     = 0
    $lineNo = 0
    foreach ($raw in $lines) {
        $lineNo++
        $line = ([string]$raw).Trim().TrimStart([char]0xFEFF)   # 去空白与可能的 BOM
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }                 # 注释行

        $parts = @($line -split '\|')
        if ($parts.Count -lt 3) {
            Write-Log ("accounts.txt 第 $lineNo 行字段不足（应为 学号|运营商|密码|名字），已跳过：$line") 'WARN'
            continue
        }
        if ($parts.Count -gt 4) {
            Write-Log ("accounts.txt 第 $lineNo 行出现 $($parts.Count) 段（多出 $($parts.Count - 4) 个 |）—— 密码里若含 | 请改掉，本行按前 4 段解析。") 'WARN'
        }

        $acc = ([string]$parts[0]).Trim()
        if ([string]::IsNullOrWhiteSpace($acc)) {
            Write-Log ("accounts.txt 第 $lineNo 行没写学号，已跳过。") 'WARN'
            continue
        }
        $no++

        $carrier = '校园网'
        if ($parts[1] -and -not [string]::IsNullOrWhiteSpace([string]$parts[1])) {
            $carrier = ([string]$parts[1]).Trim()
        }

        $pwd = ''
        if ($parts[2]) { $pwd = ([string]$parts[2]).Trim() }

        $name = ''
        if ($parts.Count -ge 4 -and $parts[3]) { $name = ([string]$parts[3]).Trim() }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = "账号$no" }

        # 拼运营商后缀；账号里已经写了 @ 就原样使用
        $suffix = ''
        if ($acc -match '@') {
            $suffix = ''
        } elseif ($CarrierMap.ContainsKey($carrier)) {
            $suffix = $CarrierMap[$carrier]
        } else {
            Write-Log ("[$name] 运营商 '$carrier' 无法识别，按『校园网』(无后缀) 处理。可选：校园网 / 联通 / 移动 / 电信") 'WARN'
        }

        $list += [pscustomobject]@{
            Index    = $list.Count
            LineNo   = $lineNo
            Name     = $name
            Account  = $acc
            Carrier  = $carrier
            Full     = ($acc + $suffix)
            Password = $pwd
        }
    }
    return ,$list
}

# 通知/日志里统一用这个标签，一眼看出是哪个账号
function Get-AccountLabel {
    param([Parameter(Mandatory)]$Acct)
    return ('{0}（{1} / {2}）' -f $Acct.Name, $Acct.Full, $Acct.Carrier)
}

# --------------------- 判断服务端拒绝是不是「账号本身废了」------------------
# 返回 'hard'（账号不可用，该换号）或 'soft'（临时故障，重试同一账号）
function Get-LoginFailureKind {
    param([string]$Msg)
    $m = [string]$Msg
    if ([string]::IsNullOrWhiteSpace($m)) { return 'soft' }
    foreach ($p in $HardFailurePatterns) {
        if ($m -like ('*' + $p + '*')) { return 'hard' }
    }
    return 'soft'
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
    param(
        [Parameter(Mandatory)]$Acct,
        [Parameter(Mandatory)][string]$PlainPassword
    )

    $ip  = Get-PortalLocalIp
    $mac = Get-LocalMacForIp -Ip $ip

    # 顺序与门户一致；
    # util._jsonp 会把 callback 提到最前，并在末尾追加 v=<随机数> 与 lang=zh
    [ordered]@{
        'callback'       = 'jsonpReturn'
        'login_method'   = '1'
        'user_account'   = $Acct.Full
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
# 返回值：@{ Ok = <bool>; Kind = 'ok'|'hard'|'soft'|'config'; Msg = <服务端原因> }
function Invoke-PortalLogin {
    param(
        [Parameter(Mandatory)]$Acct,
        [switch]$Preview
    )

    $pwd = [string]$Acct.Password
    if ([string]::IsNullOrWhiteSpace($pwd)) {
        Write-Log ("[$($Acct.Name)] 密码是空的。请打开 accounts.txt，把第 $($Acct.LineNo) 行的密码补上（格式：学号|运营商|密码|名字）。") 'ERROR'
        return @{ Ok = $false; Kind = 'config'; Msg = '密码未填写' }
    }

    $full   = $Acct.Full
    $fields = New-LoginFields -Acct $Acct -PlainPassword $pwd
    $qs     = ConvertTo-QueryString -Fields $fields

    if ($Preview) {
        # 只把密码遮掉，其余原样打印，方便肉眼核对参数名
        $masked = $qs -replace ('user_password=' + [regex]::Escape([System.Uri]::EscapeDataString($pwd))), 'user_password=***'
        Write-Log ("账号=$full  名称=$($Acct.Name)  运营商=$($Acct.Carrier)  密码长度=$($pwd.Length)") 'INFO'
        Write-Log "wlan_user_ip=$($fields['wlan_user_ip'])  wlan_user_mac=$($fields['wlan_user_mac'])" 'INFO'
        Write-Host ''
        Write-Host ("  GET " + $LoginUrls[0] + '?' + $masked) -ForegroundColor Cyan
        Write-Host ''
        return @{ Ok = $true; Kind = 'preview'; Msg = '' }
    }

    # 只记录长度，绝不打印密码
    Write-Log ("提交登录(GET JSONP)：[$($Acct.Name)] 账号=$full  运营商=$($Acct.Carrier)  密码长度=$($pwd.Length)  wlan_user_ip=$($fields['wlan_user_ip'])") 'INFO'

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
        return @{ Ok = $false; Kind = 'soft'; Msg = "登录接口无响应（HTTP $code）" }
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
        return @{ Ok = $false; Kind = 'soft'; Msg = '响应无法解析' }
    }

    $result = $obj.result
    $msg    = [string]$obj.msg

    if ($result -eq 1 -or $result -eq 'ok') {
        Write-Log ('登录接口报成功（result=' + $result + '），等待 AC 放行...') 'INFO'
        return @{ Ok = $true; Kind = 'ok'; Msg = '' }
    }

    # 服务端说本机地址「已经在线」：多半是网络在我们探测之后自己恢复了。
    # 这不该算登录失败 —— 否则会白发一条失败通知。复检外网再定论。
    if ($msg -match '已经在线') {
        if (Test-NetOnline) {
            Write-Log '服务端报本机地址已在线，且外网实测已通 —— 视为已登录。' 'OK'
            return @{ Ok = $true; Kind = 'ok'; Msg = '' }
        }
        Write-Log '服务端报本机地址已在线，但外网实测仍不通。' 'WARN'
        return @{ Ok = $false; Kind = 'soft'; Msg = '本机地址已在线但外网不通' }
    }

    $kind = Get-LoginFailureKind -Msg $msg
    Write-Log ("[$($Acct.Name)] 登录失败：result=$result  msg=$msg") 'WARN'
    if ($obj | Get-Member -Name 'ret_code' -ErrorAction SilentlyContinue) {
        Write-Log ('  ret_code=' + $obj.ret_code) 'WARN'
    }
    if ($msg -match '无法获取用户认证账号') {
        Write-Log '  ↑ 这个报错=服务端没收到账号参数。检查 user_account 参数名与 $WlanUserIp。' 'WARN'
    }
    if ($kind -eq 'hard') {
        Write-Log ("  ↑ 命中硬拒绝关键词，判定该账号不可用，不再重试它。") 'WARN'
    }
    return @{ Ok = $false; Kind = $kind; Msg = $msg }
}

# ------------------------------ 检测并登录 ----------------------------------
# v3.0：从「当前账号」开始逐个试；硬拒绝立刻换号，临时故障重试完再换号。
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

    # ★ v3.2：每次真要登录前重新读一遍账号表 —— 这样改完 accounts.txt
    #   （改密码 / 加账号 / 改运营商）立刻生效，不必重启电脑或守护进程。
    #   只在「掉线要登录」这条路径上读，每分钟的常规探测不受影响。
    #
    # ⚠️ 这里**不能**写 @(Read-Accounts)！
    #    Read-Accounts 内部是 `return ,$list`（故意把整张表当成**一个**数组对象吐出来，
    #    防止单行表被 PowerShell 拆成裸对象）。函数输出的「流」里因此只有 1 个元素，
    #    外面再套 @() 会把整张表包成「1 个账号」，$accts[0] 变成一个数组，
    #    $_.Name / $_.Password 退化成数组拼接（实测日志出现
    #    「现在有 1 个账号 —— System.Object[]」、密码长度变成 "pwd-a pwd-b" 的 11）。
    $fresh = Read-Accounts
    if ($null -eq $fresh) { $fresh = @() }
    if ($fresh.Count -gt 0) {
        if ($fresh.Count -ne $script:ActiveAccounts.Count) {
            $names = ($fresh | ForEach-Object { '{0}({1})' -f $_.Name, $_.Full }) -join '、'
            Write-Log ("账号表已重载：现在有 $($fresh.Count) 个账号 —— $names") 'INFO'
        }
        $script:ActiveAccounts = $fresh
    } elseif ($script:ActiveAccounts.Count -eq 0) {
        Write-Log 'accounts.txt 里没有任何可用账号，无法登录。' 'ERROR'
        return @{ Online = $false; Action = 'no-account' }
    } else {
        Write-Log 'accounts.txt 这次没读出任何账号（可能正在编辑保存中），暂沿用上一次的账号表。' 'WARN'
    }

    $accts = $script:ActiveAccounts
    if ($accts.Count -eq 0) {
        Write-Log 'accounts.txt 里没有任何可用账号，无法登录。' 'ERROR'
        return @{ Online = $false; Action = 'no-account' }
    }

    $startIdx  = [Math]::Min($script:ActiveAccountIndex, $accts.Count - 1)
    $startAcct = $accts[$startIdx]
    $attempted = @()      # 本轮逐个账号的失败记录，供通知使用

    for ($i = $startIdx; $i -lt $accts.Count; $i++) {
        $a = $accts[$i]

        if ($i -gt $startIdx) {
            $prev = $attempted[$attempted.Count - 1]
            Write-Log ("→ 换用账号『$($a.Name)』：上一个账号 $($prev.Acct.Full) 不可用（$($prev.Reason)）") 'WARN'
        }

        $reason = ''
        for ($attempt = 1; $attempt -le $LoginRetryCount; $attempt++) {
            if ($attempt -gt 1) { Write-Log ("[$($a.Name)] —— 第 $attempt 轮尝试 ——") 'INFO' }

            $r = Invoke-PortalLogin -Acct $a

            if (-not $r.Ok) {
                $reason = [string]$r.Msg
                if ($r.Kind -eq 'hard') {
                    # 账号本身废了：省下其余重试轮次，直接换下一个账号
                    break
                }
                if ($r.Kind -eq 'config') {
                    # 本地问题（没填密码）：重试也没意义，换下一个账号
                    Write-Log ("[$($a.Name)] 本地配置问题（$reason），换下一个账号。") 'WARN'
                    break
                }
                # 临时故障：重试同一个账号
                if ($attempt -lt $LoginRetryCount) { Start-Sleep -Seconds 3 }
                continue
            }

            # 接口报成功后，轮询等待 AC 真正放行（这是 v1.0 缺失的关键一步）
            if (Wait-NetOnline -TimeoutSeconds $PostLoginWaitSec -PollSeconds $PostLoginPollSec) {
                $script:ActiveAccountIndex = $i
                $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                if ($i -gt $startIdx) {
                    # ★ 换号成功：通知写全「原来是谁、为什么换、换成了谁」—— 蓝色（v3.4）
                    #   换号成功用蓝底对号，跟「主账号被拒」的黄色区分开
                    Send-Notify -Accent 'blue' -Title '校园网 · 已切换账号上网' -Body @(
                        ('原账号：{0}'   -f (Get-AccountLabel -Acct $startAcct)),
                        ('失败原因：{0}' -f $attempted[0].Reason),
                        ('改用账号：{0}' -f (Get-AccountLabel -Acct $a)),
                        '生效范围：本次开机期间一直使用该账号',
                        ('时间：{0}'     -f $now)
                    )
                    Write-Log ("已换号并登录成功：现在使用『$($a.Name)』$($a.Full)") 'OK'
                    return @{ Online = $true; Action = 'switch-ok' }
                }
                Send-Notify -Accent 'green' -Title '校园网 · 已自动登录' -Body @(
                    ('账号：{0}' -f (Get-AccountLabel -Acct $a)),
                    '状态：网络已恢复，掉线后会自动重登',
                    ('时间：{0}' -f $now)
                )
                Write-Log ("登录成功并已放行，当前使用『$($a.Name)』$($a.Full)") 'OK'
                return @{ Online = $true; Action = 'login-ok' }
            }

            $reason = "接口报成功，但 $PostLoginWaitSec 秒内 AC 未放行"
            Write-Log ("[$($a.Name)] $reason") 'WARN'
            if ($attempt -lt $LoginRetryCount) { Start-Sleep -Seconds 3 }
        }

        if ([string]::IsNullOrWhiteSpace($reason)) { $reason = '未知原因' }
        $attempted += [pscustomobject]@{ Acct = $a; Reason = $reason }

        # ★ 主账号（表里第 1 行）登录失败 -> 单独提醒一条（黄色）★
        #   之所以要单独一条：换号成功那条通知里虽然也写了「失败原因」，
        #   但它出现在换号之后；使用者也想第一时间知道「主号坏了」，好去充值。
        #
        #   ⚠️ 触发条件就一条：**表里还有别的账号可换**（$accts.Count -gt 1）。
        #      规则：若设置里只有主账号，就直接弹「都登不上」那条
        #      （下面那个红色通知），不要再来一条黄色的主账号失败 —— 只有一个账号时
        #      红色那条本来就把主账号的失败原因列出来了，弹两条是啰嗦。
        #      所以这里的 $accts.Count -gt 1 不是可有可无的优化，是约定好的规则。
        #
        #   另外：同一段离线期内只弹一次，免得主账号停机时每 60 秒响一声；
        #         联网恢复后由 $script:PrimaryFailureNotified 重置。
        if ($i -eq 0 -and $accts.Count -gt 1 -and -not $script:PrimaryFailureNotified) {
            $nextAcct = $accts[1]
            Send-Notify -Accent 'yellow' -Title '校园网 · 主账号登录失败' -Body @(
                ('账号：{0}'     -f (Get-AccountLabel -Acct $a)),
                ('失败原因：{0}' -f $reason),
                ('后续动作：改用下一个账号「{0}」' -f $nextAcct.Name),
                ('时间：{0}'     -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
            )
            Write-Log ("主账号『$($a.Name)』登录失败已单独提醒（原因：$reason）") 'WARN'
            $script:PrimaryFailureNotified = $true
        }
    }

    # ------------------------- 所有账号都失败 -------------------------------
    Write-Log 'accounts.txt 里所有可用账号都没能登录成功。' 'ERROR'
    $lines = @(('已尝试 {0} 个账号：' -f $attempted.Count))
    foreach ($t in $attempted) {
        $lines += ('· {0} —— {1}' -f (Get-AccountLabel -Acct $t.Acct), $t.Reason)
    }
    if ($startIdx -gt 0) {
        $lines += ('说明：本次开机已切到后续账号，主账号「{0}」要等重启电脑后才会再试' -f $accts[0].Name)
    }
    $lines += '建议：给主账号充值后重启电脑即可自动切回；或双击「1-填写账号和密码.bat」核对 accounts.txt'
    $lines += ('时间：{0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))

    # 一段离线期只弹一条失败通知，否则每 60 秒一条会把人烦死
    if (-not $script:LoginFailureNotified) {
        Send-Notify -Accent 'red' -Title '校园网 · 所有账号都登不上' -Body $lines
        $script:LoginFailureNotified = $true
    } else {
        Write-Log '（本段离线期内已发过失败通知，不再重复弹）' 'INFO'
    }
    return @{ Online = $false; Action = 'login-failed' }
}

# ================================ 主流程 ====================================

# --- 生成账号文件模板（由「1-填写账号和密码.bat」在文件不存在时调用）---
if ($InitAccountFile) {
    if (Test-Path $AccountFile) {
        Write-Host ("  账号文件已存在，未覆盖：" + $AccountFile) -ForegroundColor Yellow
        exit 0
    }
    $tpl = @'
# ============================================================
#  校园网自动登录 —— 账号密码表（账号和密码都写在这里）
# ============================================================
#
#  一行一个账号，格式：
#
#      学号|运营商|密码|名字
#
#  ── 说明 ────────────────────────────────────────────────
#   · 以 # 开头的是注释行，空行会被忽略
#   · 运营商可写：校园网 / 中国联通 / 中国移动 / 中国电信
#                 （简称也认：campus / 联通 / unicom / 移动 / cmcc / 电信 / telecom）
#   · 从上到下就是使用优先级：第 1 行是主账号，后面都是备选账号
#   · 主账号被停机 / 欠费 / 密码错等硬拒绝时，自动改用下一行的账号
#   · 名字可以省略，省略时通知里显示「账号1」「账号2」
#   · 只想用一个账号？只写一行就行
#   · 密码里不能含 | 这个竖线
#
#  ── 下面两行把密码补上就能用了 ───────────────────────────
#
#   格式示例：  20230001|中国联通|mypassword|主账号
#
# ============================================================

20230001|校园网||主账号
20230002|中国联通||备选账号
'@
    [System.IO.File]::WriteAllText($AccountFile, $tpl, [System.Text.UTF8Encoding]::new($true))
    Write-Host ("  已生成账号文件模板：" + $AccountFile) -ForegroundColor Green
    Write-Host '  请照着里面的示例，把密码补上（学号已预填）。' -ForegroundColor Yellow
    exit 0
}

# ---------------------------- 必填项校验 ------------------------------------
# 没填完就别往下走 —— 否则会拿空门户地址去请求，报错还很难懂。
# （放在 -InitAccountFile 之后：生成账号表模板时还不需要门户地址）
if ([string]::IsNullOrWhiteSpace($PortalHost)) {
    Write-Host ''
    Write-Host '  [X] 还没配置好，请先编辑本脚本顶部的「配置区」：' -ForegroundColor Yellow
    Write-Host '      $PortalHost —— 校园网认证门户的地址（IP 或域名）' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  $PortalHost 怎么找：' -ForegroundColor DarkGray
    Write-Host '    未登录时用浏览器打开任意 http 网站，会被跳转到认证页，' -ForegroundColor DarkGray
    Write-Host '    地址栏里那个 IP / 域名就是。' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  账号与密码请写进同目录 accounts.txt（双击 1-填写账号和密码.bat）。' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

$script:ActiveAccounts     = Read-Accounts
$script:ActiveAccountIndex = 0

if ($script:ActiveAccounts.Count -eq 0) {
    Write-Host ''
    Write-Host '  [X] accounts.txt 里没有任何可用账号，脚本无法工作。' -ForegroundColor Red
    Write-Host ("      账号文件：$AccountFile") -ForegroundColor Yellow
    Write-Host '      请双击「1-填写账号和密码.bat」，按里面的示例填写。' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

$fullAccount = $script:ActiveAccounts[0].Full

if (-not $Quiet) {
    Write-Host ''
    Write-Host '  校园网自动登录（Dr.COM ePortal） v3.4' -ForegroundColor Cyan
    Write-Host "  门户：http://$PortalHost/" -ForegroundColor DarkGray
    Write-Host "  接口：$($LoginUrls[0])" -ForegroundColor DarkGray
    Write-Host "  账号表：$AccountFile" -ForegroundColor DarkGray
    Write-Host '  账号（按优先级）：' -ForegroundColor DarkGray
    foreach ($a in $script:ActiveAccounts) {
        $tag = '备选'
        if ($a.Index -eq 0) { $tag = '当前' }
        Write-Host ("    [{0}] {1}" -f $tag, (Get-AccountLabel -Acct $a)) -ForegroundColor DarkGray
    }
    if ($script:ActiveAccounts.Count -eq 1) {
        Write-Host '    （只有 1 个账号：主账号停机会无号可切；想加备选就往 accounts.txt 里再加一行）' -ForegroundColor Yellow
    }
    Write-Host ''
}

if ($Diagnose) {
    Write-Log '=== 连通性诊断（只探测，不登录）===' 'INFO'
    foreach ($u in $ProbeUrls) {
        $r = Test-OneUrl -Url $u
        Write-Log ("$u => 在线=$($r.Online)  $($r.Reason)") 'INFO'
    }
    Write-Log ("门户 $PortalHost`:$PortalPort 可达=" + (Test-PortalReachable)) 'INFO'
    Write-Log ("综合判定：" + $(if (Test-NetOnline) { '在线' } else { '未在线' })) 'INFO'
    exit
}

if ($DryRun) {
    Write-Log '=== 预演：只打印请求，不提交 ===' 'INFO'
    $r = Invoke-PortalLogin -Acct $script:ActiveAccounts[$script:ActiveAccountIndex] -Preview
    if (-not $r.Ok) { exit 1 }
    exit
}

if ($Once -or $Force) {
    # ★ v3.2：手动测试也弹通知 ★
    #   以前这里刻意不弹（「控制台看得到就行」），结果双击 2-测试登录.bat
    #   明明登录成功了却收不到通知，没法验证通知功能本身。
    #   现在开着：真发生了登录才有通知，「网络在线，无需登录」时依旧安静。
    $script:NotifyEnabled = $true
    Write-Log ("单次运行开始（Force=$Force，当前账号=$($script:ActiveAccounts[$script:ActiveAccountIndex].Name)）通知已启用") 'INFO'
    $r = Invoke-CheckAndLogin -SkipProbe:$Force
    switch ($r.Action) {
        'none'               { Write-Log '网络在线，无需登录。' 'OK' }
        'portal-unreachable' { Write-Log ("校园网门户 ${PortalHost}:${PortalPort} 不可达，未尝试登录（Wi-Fi 没连上，或不在校园网）。") 'WARN' }
        'switch-ok'          { Write-Log ("已自动切换到『$($script:ActiveAccounts[$script:ActiveAccountIndex].Name)』并登录成功。") 'OK' }
        'login-ok'           { Write-Log '登录成功。' 'OK' }
        'login-failed'       { Write-Log '所有可用账号都没登录成功，原因见上面的日志。' 'ERROR' }
        default              { }
    }
    exit
}

# 常驻守护模式：状态变化时才写日志，避免刷屏
$script:NotifyEnabled = $true      # 守护模式与手动测试都弹通知（--Diagnose / -DryRun 除外）
Write-Log ("守护模式启动，检测间隔 ${IntervalSeconds} 秒，账号数 $($script:ActiveAccounts.Count)。通知已启用。") 'INFO'
$lastOnline = $null
while ($true) {
    try {
        $nowOnline = Test-NetOnline
        if ($nowOnline) {
            if ($lastOnline -eq $false) { Write-Log '网络已恢复。' 'OK' }
            $lastOnline = $true
            $script:LoginFailureNotified = $false     # 恢复联网，下次掉线可以再报一次
            $script:PrimaryFailureNotified = $false   # 主账号失败提醒同理
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
