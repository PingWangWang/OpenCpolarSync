<#
.SYNOPSIS
    OpenCpolarSync 一键部署向导。
.DESCRIPTION
    把原本需要手工完成的 5~6 个部署步骤收敛为一条命令：
      1. 检测并静默安装 Cpolar（未安装时自动安装仓库自带的 msi）
      2. 从 archive/openlist.zip 解压 openlist.exe 到 Openlist/ 目录
      3. 交互式收集配置并生成 config.json（持久化到用户目录，升级不丢失）
      4. 配置 Cpolar 内网穿透隧道（写入 cpolar.yml 并注册 authtoken）
      5. 注册 Watchdog 计划任务（S4U）并立即触发一次，由 GuardCheck 拉起
         Cpolar / Openlist 两个 Guard，再等 Openlist 就绪（有上限）后才继续
      6. 在桌面创建「配置向导」快捷方式（以管理员身份运行）——以后双击即可重开本向导
      7. 自动打开 Openlist Web 与 Cpolar Web 两个页面（前者用于完成存储挂载）
         ——只打开「端口确实已在监听」的页面，避免首次部署打开一个空白页

    独立运行（如双击桌面快捷方式）时会先询问操作类型：
      1) 安装 / 更新   2) 卸载
    由 bootstrap-core.ps1 调用时不会重复询问（引导器已提供同样的菜单）。

    设计上遵循「配置与程序分离」：config.json 的主副本存放在
    %LOCALAPPDATA%\OpenCpolarSync\config，每次运行都会同步一份到仓库的
    Cpolar\config\ 目录，保证 Guard 与 Watchdog 无需改造即可读取到最新配置。

    支持 -DryRun 演练模式：只打印将要执行的操作，不产生任何副作用。
.PARAMETER DryRun
    演练模式，不实际安装、注册或写入任何文件，仅输出执行计划。
.PARAMETER Silent
    非交互模式，全部配置由参数提供，缺失项直接使用默认值而不询问。
.PARAMETER RootDir
    仓库根目录，默认为本脚本所在目录。
.PARAMETER ConfigDir
    配置持久化目录，默认为 %LOCALAPPDATA%\OpenCpolarSync\config。
.PARAMETER WebhookUrl
    钉钉机器人 Webhook 地址。
.PARAMETER CpolarUser
    Cpolar Web 登录邮箱。
.PARAMETER CpolarPassword
    Cpolar Web 登录密码。
.PARAMETER TunnelNames
    需要监控的隧道名称列表。
.PARAMETER Interval
    隧道轮询间隔（分钟），最小 1。
.PARAMETER AuthToken
    Cpolar 账号的 authtoken，用于免登录创建隧道。
.PARAMETER Region
    Cpolar 隧道区域，默认 cn。
.PARAMETER OpenlistPort
    Openlist 服务端口，默认 5244。
.PARAMETER OpenlistReadyTimeout
    注册 Watchdog 后等待 Openlist 就绪的最长秒数，默认 30。超时不视为失败，
    Guard 会在后续轮询周期继续重试；该值只影响收尾摘要与自动打开页面的时机。
.PARAMETER SkipCpolarInstall
    跳过 Cpolar 安装检测与安装。
.PARAMETER SkipOpenlist
    跳过 openlist.exe 解压部署。
.PARAMETER SkipTunnel
    跳过 Cpolar 隧道配置。
.PARAMETER SkipWatchdog
    跳过 Watchdog 计划任务注册。
.PARAMETER NoBrowser
    不自动打开浏览器引导页面。
.PARAMETER SkipShortcut
    跳过在桌面创建「配置向导」快捷方式。
.PARAMETER NoElevate
    禁止自动请求管理员提权（供自测或已具备权限的场景使用）。
.PARAMETER NoMenu
    不询问「安装 / 卸载」操作类型，直接进入安装流程。
    由 bootstrap-core.ps1 调用时自动传入，避免与引导器的菜单重复询问。
.EXAMPLE
    .\setup.ps1
    交互式完成全部部署。
.EXAMPLE
    .\setup.ps1 -DryRun
    演练模式，仅查看执行计划。
.EXAMPLE
    .\setup.ps1 -Silent -WebhookUrl 'https://oapi.dingtalk.com/...' -CpolarUser 'a@b.com' -CpolarPassword 'pwd' -TunnelNames 'OpenListHC'
    无人值守部署。
.NOTES
    Version: 1.0
    Compatible: Windows 7 SP1+ / PowerShell 5.0+
                实测通过：Windows PowerShell 5.1.26100（Windows 预装版）、PowerShell 7.6.4
#>

param(
    [switch]$DryRun,
    [switch]$Silent,

    # bootstrap-core.ps1 调用本脚本时置位：引导器已提供「安装 / 卸载」菜单，
    # 这里不再重复询问。双击桌面快捷方式独立运行时不带此开关，因此会显示菜单。
    [switch]$NoMenu,

    [string]$RootDir,
    [string]$ConfigDir,

    [string]$WebhookUrl,
    [string]$CpolarUser,
    [string]$CpolarPassword,
    [string]$OpenlistPassword,
    [string[]]$TunnelNames,
    [int]$Interval = 1,
    [string]$AuthToken,
    [string]$Region = 'cn',
    [int]$OpenlistPort = 5244,
    [int]$OpenlistReadyTimeout = 30,

    [switch]$SkipCpolarInstall,
    [switch]$SkipOpenlist,
    [switch]$SkipTunnel,
    [switch]$SkipWatchdog,
    [switch]$NoBrowser,
    [switch]$SkipShortcut,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

# 设置 UTF-8 输出编码以正确显示中文。计划任务、管道调用等非控制台环境下
# 该属性可能不可用，此处做保护，避免脚本因缺少控制台而中断。
try {
    # Windows PowerShell 5.1 的控制台默认使用系统 ANSI 代码页（简体中文为 936/GBK），
    # 此时强行改为 UTF-8 会让中文提示在控制台显示为乱码；因此仅在 PowerShell 6+
    # 或控制台本身已是 UTF-8(65001) 时才同步输出编码。
    if ($PSVersionTable.PSVersion.Major -ge 6 -or [Console]::OutputEncoding.CodePage -eq 65001) {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
    }
} catch { }

# ============================================================
# Function: Write-Log — 输出带级别符号与着色的中文日志
# 符号刻意限定在 GB2312 字符集内（√ × → · ~ !），这样在 Windows
# PowerShell 5.1 的 GBK 控制台下也能正常显示，不会出现方块或问号。
# ============================================================
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'STEP', 'OK', 'WARN', 'ERROR', 'DRYRUN')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $style = switch ($Level) {
        'OK'     { @{ Mark = '√'; Color = 'Green' } }
        'WARN'   { @{ Mark = '!'; Color = 'Yellow' } }
        'ERROR'  { @{ Mark = '×'; Color = 'Red' } }
        'STEP'   { @{ Mark = '→'; Color = 'Cyan' } }
        'DRYRUN' { @{ Mark = '~'; Color = 'Magenta' } }
        default  { @{ Mark = '·'; Color = 'DarkGray' } }
    }

    Write-Host ("   {0} {1}" -f $style.Mark, $Message) -ForegroundColor $style.Color
}

# ============================================================
# Function: Write-Rule — 输出横向分隔线
# 与 Write-Log 同理，只用 GB2312 内的制表符（─ ═），保证 GBK 控制台可显示。
# ============================================================
function Write-Rule {
    param(
        [int]$Width = 58,
        [ValidateSet('Single', 'Double')][string]$Style = 'Single',
        [string]$Color = 'DarkCyan'
    )

    $ch = if ($Style -eq 'Double') { '═' } else { '─' }
    Write-Host ('  ' + ($ch * $Width)) -ForegroundColor $Color
}

# ============================================================
# Function: Write-Banner — 输出脚本顶部横幅
# ============================================================
function Write-Banner {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Subtitle
    )

    Write-Host ''
    Write-Rule -Width 58 -Style Double
    Write-Host ("    " + $Title) -ForegroundColor Cyan
    if ($Subtitle) { Write-Host ("    " + $Subtitle) -ForegroundColor DarkGray }
    Write-Rule -Width 58 -Style Double
}

# ============================================================
# Function: Get-SpecialFolder — 安全获取系统目录路径
# 计划任务、非交互宿主等场景下环境变量可能未加载，直接 Join-Path 会因
# 收到 null 而中断。这里在环境变量缺失时回退到 .NET API 获取系统目录。
# ============================================================
function Get-SpecialFolder {
    param(
        [Parameter(Mandatory = $true)][string]$VariableName,
        [Parameter(Mandatory = $true)][string]$FolderName
    )

    $envValue = Get-Item "Env:$VariableName" -ErrorAction SilentlyContinue
    if ($envValue -and $envValue.Value) { return $envValue.Value }

    return [Environment]::GetFolderPath([Environment+SpecialFolder]::$FolderName)
}

# ============================================================
# Function: Write-Stage — 打印阶段分隔标题
# ============================================================
function Write-Stage {
    param(
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Title,
        [int]$Total = 7
    )

    Write-Host ''
    Write-Rule -Width 58
    Write-Host ("   阶段 $Number/$Total  ·  $Title") -ForegroundColor Cyan
}

# ============================================================
# Function: Invoke-Action — 统一的副作用执行包装
# DryRun 模式下只打印计划，不执行动作，保证演练零副作用。
# 返回 $true 表示成功（或已演练），$false 表示执行失败。
# ============================================================
function Invoke-Action {
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    if ($DryRun) {
        Write-Log 'DRYRUN' "计划执行：$Description"
        return $true
    }

    Write-Log 'STEP' $Description
    try {
        & $Action | Out-Null
        Write-Log 'OK' "$Description 完成"
        return $true
    } catch {
        Write-Log 'ERROR' "$Description 失败：$($_.Exception.Message)"
        return $false
    }
}

# ============================================================
# Function: Test-IsAdmin — 判断当前是否具备管理员权限
# ============================================================
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================================
# Function: Get-ProcessList — 安全获取同名进程，统一成数组
# Get-Process 无匹配时返回 $null，直接取 .Count 会报错；此函数总是返回数组，
# 并统一成 { Id, Label, StartTime } 结构，便于与 Guard 进程一起处理。
# ============================================================
function Get-ProcessList {
    param([Parameter(Mandatory = $true)][string]$Name)

    $result = @()
    foreach ($p in @(Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        $started = $null
        try { $started = $p.StartTime } catch { }
        $result += [pscustomobject]@{ Id = [int]$p.Id; Label = $Name; StartTime = $started }
    }
    return $result
}

# ============================================================
# Function: Get-ToolProcesses — 找出「本工具自己」的 Guard 进程
#
# 双重限定，避免误判（误判的后果是 Stop-Process 直接结束用户的进程）：
#   1) 命令行里必须是 `-File` **直接跟着**该脚本的完整路径 —— 即真的以该脚本
#      为入口启动的进程（根目录由调用方传入，不做文件名通配）；
#   2) 排除自身 PID。
# 宁可漏检也不误杀。
#
# 【为什么不能「路径出现在命令行里就算命中」】计划任务给 GuardCheck.ps1 传的参数里
# 带着 `-GuardScriptPath "<Guard 脚本完整路径>"`（见 WatchdogManager.bat），因此
# GuardCheck 自己的命令行也含该路径。宽松匹配会把 GuardCheck 误判成 Guard ——
# 在 GuardCheck.ps1 里这个误判曾导致「永远认为 Guard 已存在、从不拉起它」
# （详见该文件内的说明）。必须要求 `-File` 与路径相邻，才能区分
# 「以它启动」与「只是提到它」。
# ============================================================
function Get-ToolProcesses {
    param([string]$BaseDir)

    if ($BaseDir) {
        $candidates = @(
            (Join-Path $BaseDir 'Cpolar\CpolarGuard.ps1'),
            (Join-Path $BaseDir 'Openlist\OpenlistGuard.ps1'),
            (Join-Path $BaseDir 'Watchdog\GuardCheck.ps1')
        )
    } else {
        return @()
    }

    $patterns = @()
    foreach ($c in $candidates) {
        $patterns += @{
            Path    = $c
            Pattern = ('-File\s+"?' + [regex]::Escape($c) + '"?(\s|$)')
        }
    }

    $result = @()
    try {
        $procs = Get-CimInstance Win32_Process `
            -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop
    } catch {
        # 拿不到 CIM（权限/精简系统）时静默降级，不影响主流程
        return $result
    }

    foreach ($p in @($procs)) {
        if ([int]$p.ProcessId -eq $PID) { continue }
        $cmd = "$($p.CommandLine)"
        if (-not $cmd) { continue }
        foreach ($c in $patterns) {
            if ($cmd -match $c.Pattern) {
                $result += [pscustomobject]@{
                    Id        = [int]$p.ProcessId
                    Label     = (Split-Path $c.Path -Leaf)
                    StartTime = $p.CreationDate
                }
                break
            }
        }
    }

    return $result
}

# ============================================================
# Function: Select-DuplicateProcess — 挑出「同名但多于一个」的多余实例
#
# 分组键是 Label：CpolarGuard 与 OpenlistGuard 各一个属正常，
# 同名出现 2 个才是重复。保留启动最早的一个，其余判为多余。
# ============================================================
function Select-DuplicateProcess {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Procs)

    $byLabel = @{}
    foreach ($p in @($Procs)) {
        $key = "$($p.Label)"
        if (-not $byLabel.ContainsKey($key)) { $byLabel[$key] = New-Object System.Collections.ArrayList }
        [void]$byLabel[$key].Add($p)
    }

    $dupes = @()
    foreach ($key in $byLabel.Keys) {
        $group = @($byLabel[$key])
        if ($group.Count -le 1) { continue }
        # 取不到启动时间（权限不足）的排到最后，避免把有效实例当多余的处理
        $sorted = @($group | Sort-Object -Property `
            @{ Expression = { if ($_.StartTime) { $_.StartTime } else { [datetime]::MaxValue } } }, Id)
        $dupes += $sorted[1..($sorted.Count - 1)]
    }
    return $dupes
}

# ============================================================
# Function: Write-ProcessStatus — 输出单个组件的运行状态
# 0 个 = 未运行；1 个 = 运行中；≥2 个 = 告警（可能重复拉起）
# ============================================================
function Write-ProcessStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Procs
    )

    $list = @($Procs)
    if ($list.Count -eq 0) {
        Write-Log 'INFO' "$Label：未运行"
        return
    }

    $pids = ($list | ForEach-Object { $_.Id }) -join ', '
    if ($list.Count -eq 1) {
        Write-Log 'OK' "$Label：运行中（PID=$pids）"
    } else {
        Write-Log 'WARN' "$Label：检测到 $($list.Count) 个实例（PID=$pids），可能存在重复拉起"
    }
}

# ============================================================
# Function: Test-TcpPort — 探测本机 TCP 端口是否已在监听
#
# 为什么不能只看「进程存在」：openlist.exe 进程刚起来时端口往往还没开始监听，
# 此刻打开浏览器只会得到一个空白页。收尾要打开 Web 页面，就得先确认真在听。
# 不依赖 Add-Type（受限环境会拦），直接用 .NET BeginConnect 控制超时。
# ============================================================
function Test-TcpPort {
    param(
        [string]$ComputerName = '127.0.0.1',
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 800
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# ============================================================
# Function: Wait-ServiceReady — 等待服务「进程存在且端口已监听」
#
# 为什么需要它：openlist.exe 不是 setup.ps1 启动的，而是由 OpenlistGuard 启动，
# 而 Guard 由 Watchdog 计划任务拉起；注册任务的那一刻 openlist 还没起来。
# 若此时就打印摘要 / 打开网页，首次部署必然得到「Openlist 未运行」+ 一个空白页。
# 所以在触发计划任务后留一个有上限的等待窗口（TimeoutSec，0 表示只探测一次）。
#
# 返回 $true = 已就绪；$false = 超时（调用方应给提示而不是当成部署失败）。
# ============================================================
function Wait-ServiceReady {
    param(
        [Parameter(Mandatory = $true)][string]$ProcessName,
        [int]$Port = 0,
        [int]$TimeoutSec = 30,
        [string]$Label = ''
    )

    if (-not $Label) { $Label = $ProcessName }

    # 输出被重定向（写日志）或宿主没有控制台时不画动态省略号，
    # 避免把回车控制符写进日志文件。
    $canDraw = $false
    try { $canDraw = -not [Console]::IsOutputRedirected } catch { $canDraw = $false }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $frame = 0
    $frames = @('.  ', '.. ', '...')

    while ($true) {
        $ready = $false
        if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
            # 只要进程不要端口时（Port<=0）进程存在即视为就绪
            if ($Port -le 0 -or (Test-TcpPort -Port $Port)) { $ready = $true }
        }

        if ($ready -or (Get-Date) -ge $deadline) {
            # 抹掉等待中的省略号那一行
            if ($canDraw -and $frame -gt 0) { Write-Host ("`r" + (' ' * 44) + "`r") -NoNewline }
            return $ready
        }

        if ($canDraw) {
            Write-Host ("`r   等待 $Label 就绪" + $frames[$frame % 3]) -NoNewline
            $frame++
        }
        Start-Sleep -Milliseconds 1000
    }
}

# ============================================================
# Function: ConvertTo-JsonEscapedString — 生成 JSON 字符串字面量
# PowerShell 5.1 的 ConvertTo-Json 会把中文转义成 \uXXXX，这里手工
# 拼接 JSON 以保留中文注释行可读性（与现有 config.json 风格一致）。
# ============================================================
function ConvertTo-JsonEscapedString {
    param([string]$Value)

    if ($null -eq $Value) { return '""' }
    $escaped = $Value -replace '\\', '\\' -replace '"', '\"'
    return "`"$escaped`""
}

# ============================================================
# Function: Test-CpolarInstalled — 检测 Cpolar 是否已安装
# 依次检查卸载注册表项、默认安装路径与运行中的进程。
# ============================================================
function Test-CpolarInstalled {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        if (Test-Path $path) {
            $match = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*cpolar*' }
            if ($match) { return $true }
        }
    }

    $defaultExe = Join-Path (Get-SpecialFolder -VariableName 'ProgramFiles' -FolderName 'ProgramFiles') 'cpolar\cpolar.exe'
    if ($defaultExe -and (Test-Path $defaultExe)) { return $true }

    if (Get-Process -Name 'cpolar' -ErrorAction SilentlyContinue) { return $true }

    return $false
}

# ============================================================
# Function: Install-Cpolar — 静默安装仓库自带的 cpolar msi
# ============================================================
function Install-Cpolar {
    param([Parameter(Mandatory = $true)][string]$MsiPath)

    if (-not (Test-Path $MsiPath)) {
        Write-Log 'WARN' "未找到本地 Cpolar 安装包：$MsiPath"
        Write-Log 'STEP' '尝试从 cpolar 官网下载安装包...'
        $msiDir = Split-Path -Parent $MsiPath
        if (-not (Test-Path $msiDir)) {
            New-Item -ItemType Directory -Path $msiDir -Force | Out-Null
        }
        $downloadUrls = @(
            'https://www.cpolar.com/static/downloads/cpolar-stable-windows-amd64.msi',
            'https://www.cpolar.com/static/downloads/cpolar-windows-amd64.msi'
        )
        $downloaded = $false
        foreach ($url in $downloadUrls) {
            try {
                Write-Log 'INFO' "尝试下载：$url"
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add('User-Agent', 'OpenCpolarSync-Setup')
                $wc.DownloadFile($url, $MsiPath)
                if ((Test-Path $MsiPath) -and ((Get-Item $MsiPath).Length -gt 100000)) {
                    Write-Log 'OK' "下载完成（$([math]::Round((Get-Item $MsiPath).Length / 1MB, 2)) MB）"
                    $downloaded = $true
                    break
                }
            } catch {
                Write-Log 'WARN' "下载失败：$($_.Exception.Message)"
            }
        }
        if (-not $downloaded) {
            Write-Log 'ERROR' '无法下载 Cpolar 安装包，请手动安装 Cpolar 后重试'
            Write-Host '  下载地址：https://www.cpolar.com/download' -ForegroundColor Yellow
            return $false
        }
    }

    return (Invoke-Action -Description '静默安装 Cpolar' -Action {
        $arguments = "/i `"$MsiPath`" /qn /norestart"
        $process = Start-Process 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
        # 1641=成功且需重启，3010=成功需重启，0=成功
        if ($process.ExitCode -notin @(0, 1641, 3010)) {
            throw "msiexec 退出码 $($process.ExitCode)"
        }
    })
}

# ============================================================
# Function: Deploy-Openlist — 从 archive 解压出 openlist.exe
# 已存在 openlist.exe 时直接跳过，保证可重复执行。
# ============================================================
function Deploy-Openlist {
    param(
        [Parameter(Mandatory = $true)][string]$OpenlistDir,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )

    $targetExe = Join-Path $OpenlistDir 'openlist.exe'
    if (Test-Path $targetExe) {
        Write-Log 'OK' "openlist.exe 已存在，跳过解压"
        return $true
    }

    if (-not (Test-Path $ArchivePath)) {
        Write-Log 'ERROR' "未找到 openlist 压缩包：$ArchivePath"
        return $false
    }

    return (Invoke-Action -Description '解压 openlist.zip 到 Openlist 目录' -Action {
        if (-not (Test-Path $OpenlistDir)) {
            New-Item -ItemType Directory -Path $OpenlistDir -Force | Out-Null
        }

        # 使用 Expand-Archive 而非 .NET ZipFile：后者依赖 System.IO.Compression.FileSystem
        # 程序集，在 PowerShell 7（.NET Core）上不可用，用 cmdlet 可保证 5.1 与 7 行为一致。
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) 'ocs-openlist-extract'
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        Expand-Archive -Path $ArchivePath -DestinationPath $tempDir -Force

        # 压缩包内可能还包着一层目录，递归定位 openlist.exe
        $exe = Get-ChildItem -Path $tempDir -Filter 'openlist.exe' -Recurse |
            Select-Object -First 1
        if (-not $exe) { throw '压缩包内未找到 openlist.exe' }

        Move-Item -Path $exe.FullName -Destination $targetExe -Force
        Remove-Item $tempDir -Recurse -Force
    })
}

# ============================================================
# Function: Set-CpolarTunnel — 写入 cpolar.yml 并注册 authtoken
# 利用 cpolar 自身的 -config / authtoken 能力，免去在 Web 端手工建隧道。
# ============================================================
# ============================================================
# Function: Set-OpenlistAdminPassword — 设置 openlist(alist) 管理员密码
# 用户名固定为 admin；直接写入 openlist 数据目录，免去用户查初始随机密码。
# ============================================================
function Set-OpenlistAdminPassword {
    param(
        [Parameter(Mandatory = $true)][string]$OpenlistDir,
        [string]$Password
    )

    if (-not $Password) {
        Write-Log 'INFO' '未填写 Openlist 登录密码，跳过（可稍后用 openlist.exe admin random 查看/重置）'
        return $true
    }

    $exe = Join-Path $OpenlistDir 'openlist.exe'
    if (-not (Test-Path $exe)) {
        Write-Log 'WARN' "未找到 openlist.exe，跳过设置登录密码：$exe"
        return $false
    }

    if ($DryRun) {
        Write-Log 'DRYRUN' '计划设置 Openlist 管理员密码（用户名 admin）'
        return $true
    }

    try {
        $dataDir = Join-Path $OpenlistDir 'data'
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        # 不打印命令输出，避免密码明文出现在日志中
        & $exe admin set $Password --data $dataDir *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'OK' 'Openlist 登录密码已设置（用户名 admin）'
            return $true
        }
        Write-Log 'WARN' "设置 Openlist 登录密码失败（exit=$LASTEXITCODE）"
        return $false
    } catch {
        Write-Log 'WARN' "设置 Openlist 登录密码异常：$($_.Exception.Message)"
        return $false
    }
}

function Set-CpolarTunnel {
    param(
        [Parameter(Mandatory = $true)][string[]]$Tunnels,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$TunnelRegion,
        [string]$Token,
        # 用户目录，默认取 $HOME；暴露为参数便于在测试中注入临时目录
        [string]$UserProfilePath
    )

    # 未显式指定时优先使用 $HOME，宿主未提供则回退到 .NET API 获取用户目录
    if (-not $UserProfilePath) {
        $UserProfilePath = $HOME
        if (-not $UserProfilePath) {
            $UserProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        }
    }
    $cpolarDir = Join-Path $UserProfilePath '.cpolar'
    $ymlPath   = Join-Path $cpolarDir 'cpolar.yml'

    # 拼接 yml 内容：authtoken 与 tunnels 两段
    $lines = New-Object System.Collections.ArrayList
    if ($Token) { [void]$lines.Add("authtoken: $Token") }
    [void]$lines.Add('tunnels:')
    foreach ($name in $Tunnels) {
        [void]$lines.Add("  ${name}:")
        [void]$lines.Add("    proto: http")
        [void]$lines.Add("    addr: $Port")
        [void]$lines.Add("    region: $TunnelRegion")
    }
    $content = ($lines -join "`n") + "`n"

    $result = Invoke-Action -Description "写入 Cpolar 隧道配置 $ymlPath" -Action {
        if (-not (Test-Path $cpolarDir)) {
            New-Item -ItemType Directory -Path $cpolarDir -Force | Out-Null
        }
        # 覆盖前先备份，避免用户已有隧道配置被静默覆盖
        if (Test-Path $ymlPath) {
            Copy-Item $ymlPath "$ymlPath.bak" -Force
        }
        [System.IO.File]::WriteAllText($ymlPath, $content, (New-Object System.Text.UTF8Encoding($false)))
    }

    if (-not $result) { return $false }

    if ($DryRun) {
        Write-Log 'DRYRUN' '计划注册 cpolar authtoken（若 cpolar 已在运行则跳过，避免重复拉起实例）'
        return $true
    }

    # authtoken 通过官方命令写入，比直接改 yml 更稳妥。
    #
    # 但 cpolar.exe 是**常驻客户端**：在 cpolar 已经运行的情况下再执行一次
    # `cpolar.exe authtoken`，会额外拉起一个新的 cpolar 进程——这正是「多次运行
    # 本向导后出现多个 cpolar 实例」的原因（真机日志里同时存在两个 cpolar PID）。
    # 因此先检测：已在运行就只保留上面写好的 yml，跳过 CLI 调用。
    if ($Token) {
        $runningCpolar = @(Get-ProcessList -Name 'cpolar')
        if ($runningCpolar.Count -gt 0) {
            Write-Log 'INFO' "Cpolar 已在运行（PID=$($runningCpolar[0].Id)），跳过 authtoken 命令注册（yml 已写好，重启 Cpolar 后生效）"
            return $true
        }

        $cpolarExe = Get-Command 'cpolar.exe' -ErrorAction SilentlyContinue
        if ($cpolarExe) {
            return (Invoke-Action -Description '注册 cpolar authtoken' -Action {
                & $cpolarExe.Source authtoken $Token | Out-Null
            })
        }
        Write-Log 'WARN' '未找到 cpolar.exe，跳过 authtoken 命令注册（已写入 yml）'
    }

    return $true
}

# ============================================================
# Function: Read-ExistingConfig — 读取已存在的配置作为向导默认值
# 使脚本可重复运行，二次执行时不必重新输入全部字段。
# ============================================================
function Read-ExistingConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    try {
        return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Log 'WARN' "已有配置文件解析失败，将重新收集：$($_.Exception.Message)"
        return $null
    }
}

# ============================================================
# Function: Invoke-ConfigWizard — 交互式收集配置项
# 参数已提供的值不再询问；-Silent 时缺失项直接用默认值。
# ============================================================
function Invoke-ConfigWizard {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Values,
        # 首次运行时尚无历史配置，此处允许为 null
        [AllowNull()]$Existing,
        # 隧道名默认值允许为空字符串（表示不预填任何隧道名）。
        # 不加 AllowEmptyString 的话，传 '' 会触发参数绑定错误而中断整个向导。
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][string]$DefaultTunnel
    )

    # --- 钉钉 Webhook ---
    if (-not $Values.WebhookUrl) {
        $default = if ($Existing) { $Existing.webhookUrl } else { '' }
        if ($Silent) {
            $Values.WebhookUrl = $default
        } else {
            if ($default) {
                Write-Host "  当前值：$default" -ForegroundColor Gray
            }
            $prompt = '钉钉机器人 Webhook 地址'
            if ($default) { $prompt += '（回车保留当前值）' }
            $input = Read-Host $prompt
            $Values.WebhookUrl = if ($input) { $input } else { $default }
        }
    }

    # --- Cpolar 登录邮箱 ---
    if (-not $Values.CpolarUser) {
        $default = if ($Existing) { $Existing.username } else { '' }
        if ($Silent) {
            $Values.CpolarUser = $default
        } else {
            if ($default) {
                Write-Host "  当前值：$default" -ForegroundColor Gray
            }
            $prompt = 'Cpolar Web 登录邮箱'
            if ($default) { $prompt += '（回车保留当前值）' }
            $input = Read-Host $prompt
            $Values.CpolarUser = if ($input) { $input } else { $default }
        }
    }

    # --- Cpolar 登录密码（使用安全字符串读取，避免明文回显）---
    if (-not $Values.CpolarPassword) {
        $default = if ($Existing) { $Existing.password } else { '' }
        if ($Silent) {
            $Values.CpolarPassword = $default
        } else {
            if ($default) {
                Write-Host '  当前值：已保存（输入新密码则覆盖，回车保留）' -ForegroundColor Gray
            }
            $secure = Read-Host 'Cpolar Web 登录密码' -AsSecureString
            if ($secure.Length -gt 0) {
                $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
                $Values.CpolarPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            } else {
                $Values.CpolarPassword = $default
            }
        }
    }

    # --- Openlist 登录密码（用户名固定 admin，避免用户不知道初始随机密码）---
    if (-not $Values.OpenlistPassword) {
        $default = if ($Existing) { $Existing.openlistPassword } else { '' }
        if ($Silent) {
            $Values.OpenlistPassword = $default
        } else {
            if ($default) {
                Write-Host '  当前值：已保存（输入新密码则覆盖，回车保留）' -ForegroundColor Gray
            }
            $secure = Read-Host 'Openlist Web 登录密码（用户名固定 admin）' -AsSecureString
            if ($secure.Length -gt 0) {
                $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
                $Values.OpenlistPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            } else {
                $Values.OpenlistPassword = $default
            }
        }
    }

    # --- 监控隧道名 ---
    # 首次配置默认留空（不再预填 OpenListHC）：用户此时多半还没在 Cpolar 侧建好隧道，
    # 预填一个不存在的名字只会让 Guard 一直报「隧道未找到」。
    if (-not $Values.TunnelNames -or $Values.TunnelNames.Count -eq 0) {
        $default = if ($Existing -and $Existing.selectedTunnelNames) {
            $Existing.selectedTunnelNames -join ','
        } else { $DefaultTunnel }

        if ($Silent) {
            $Values.TunnelNames = if ($default) { @($default) } else { @() }
        } else {
            if ($default) {
                Write-Host "  当前值：$default" -ForegroundColor DarkGray
            } else {
                Write-Host '  当前值：（空）首次配置默认不监控任何隧道' -ForegroundColor DarkGray
            }
            $prompt = '要监控的隧道名，多个用逗号分隔'
            if ($default) {
                $prompt += '（回车保留当前值）'
            } else {
                $prompt += '（直接回车 = 暂不监控，可稍后在配置文件里补）'
            }
            $input = Read-Host $prompt
            if ($input) {
                $Values.TunnelNames = @($input -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            } elseif ($default) {
                $Values.TunnelNames = @($default)
            } else {
                $Values.TunnelNames = @()
            }
        }
    }

    # 统一兜底：过滤空字符串。否则 $DefaultTunnel 为空且用户直接回车时，
    # @($default) 会得到 @('')，最终写出 ["",] 这种无意义的隧道名。
    if ($Values.TunnelNames) {
        $Values.TunnelNames = @($Values.TunnelNames | Where-Object { $_ -and "$_".Trim() })
    } else {
        $Values.TunnelNames = @()
    }

    # --- 轮询间隔 ---
    if (-not $Values.Interval) {
        $default = if ($Existing -and $Existing.interval) { [int]$Existing.interval } else { 1 }
        if ($Silent) {
            $Values.Interval = $default
        } else {
            Write-Host "  当前值：$default 分钟" -ForegroundColor Gray
            $prompt = '轮询间隔（分钟）'
            if ($default) { $prompt += '（回车保留当前值）' }
            $input = Read-Host $prompt
            $Values.Interval = if ($input -match '^\d+$') { [int]$input } else { $default }
        }
    }
    if ($Values.Interval -lt 1) { $Values.Interval = 1 }

    return $Values
}

# ============================================================
# Function: New-GuardConfigFile — 生成 config.json（主副本 + 运行副本）
# ============================================================
function New-GuardConfigFile {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Values,
        [Parameter(Mandatory = $true)][string]$PrimaryPath,
        [string]$RuntimePath
    )

    # 先过滤空项再序列化：隧道默认留空时这里会得到空数组，写出 selectedTunnelNames: []
    $tunnelList  = @($Values.TunnelNames | Where-Object { $_ -and "$_".Trim() })
    $tunnelsJson = ($tunnelList | ForEach-Object { ConvertTo-JsonEscapedString $_ }) -join ', '

    # 手工拼接 JSON，保留 _key 形式的中文说明行，与仓库现有配置风格一致
    $json = @"
{
  "_webhookUrl": "钉钉机器人 Webhook 地址（必填），在钉钉群 → 智能群助手 → 添加机器人 → 复制 Webhook URL",
  "webhookUrl": $(ConvertTo-JsonEscapedString $Values.WebhookUrl),

  "_interval": "轮询检测间隔，单位分钟，最小 1 分钟",
  "interval": $($Values.Interval),

  "_selectedTunnelNames": "要监控的隧道名称列表，如 [\`"OpenListHC\`"]。留空 [] 则不监控任何隧道，运行中修改此文件会自动生效",
  "selectedTunnelNames": [$tunnelsJson],

  "_cpolarApiBase": "Cpolar Web 管理界面地址，一般不需要改",
  "cpolarApiBase": "http://localhost:9200",

  "_username": "Cpolar Web 登录邮箱",
  "username": $(ConvertTo-JsonEscapedString $Values.CpolarUser),

  "_password": "Cpolar Web 登录密码",
  "password": $(ConvertTo-JsonEscapedString $Values.CpolarPassword),

  "_openlistPassword": "Openlist Web 登录密码（用户名固定 admin）",
  "openlistPassword": $(ConvertTo-JsonEscapedString $Values.OpenlistPassword),

  "_keyword": "钉钉机器人安全关键词，需在钉钉群机器人安全设置中添加同名字符串",
  "keyword": "Cpolar",

  "_debug": "调试日志开关，true=输出详细 API 响应和运行日志",
  "debug": false
}
"@

    if ($DryRun) {
        Write-Log 'DRYRUN' "计划写入配置文件：$PrimaryPath"
        if ($RuntimePath) { Write-Log 'DRYRUN' "计划同步运行副本：$RuntimePath" }
        return $true
    }

    try {
        $primaryDir = Split-Path -Parent $PrimaryPath
        if (-not (Test-Path $primaryDir)) {
            New-Item -ItemType Directory -Path $primaryDir -Force | Out-Null
        }

        # 主副本用无 BOM UTF-8，避免部分解析器受 BOM 影响
        [System.IO.File]::WriteAllText($PrimaryPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Log 'OK' "配置主副本已写入：$PrimaryPath"

        # 同步一份到 Guard 默认读取路径，使 Watchdog 无需改造即可生效
        if ($RuntimePath) {
            $runtimeDir = Split-Path -Parent $RuntimePath
            if (-not (Test-Path $runtimeDir)) {
                New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
            }
            Copy-Item $PrimaryPath $RuntimePath -Force
            Write-Log 'OK' "配置运行副本已同步：$RuntimePath"
        }

        return $true
    } catch {
        Write-Log 'ERROR' "写入配置文件失败：$($_.Exception.Message)"
        return $false
    }
}

# ============================================================
# Function: Register-WatchdogTasks — 注册 Watchdog 计划任务并拉起 Guard
# ============================================================
function Register-WatchdogTasks {
    param([Parameter(Mandatory = $true)][string]$ManagerPath)

    if (-not (Test-Path $ManagerPath)) {
        Write-Log 'ERROR' "未找到 WatchdogManager.bat：$ManagerPath"
        return $false
    }

    $ok = Invoke-Action -Description '注册 Watchdog 计划任务（setup all）' -Action {
        $process = Start-Process -FilePath 'cmd.exe' `
            -ArgumentList "/c `"$ManagerPath`" setup all" `
            -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { throw "退出码 $($process.ExitCode)" }
    }

    return $ok
}

# Watchdog 计划任务名 —— 必须与 Watchdog/WatchdogManager.bat 里的
# TASK_CPOLAR / TASK_OPENLIST 保持一致（该 bat 是任务名的唯一定义处）。
$WatchdogTaskNames = @(
    'OpenCpolarSync_CpolarGuard_Watchdog',
    'OpenCpolarSync_OpenlistGuard_Watchdog'
)

# ============================================================
# Function: Start-WatchdogTicks — 立即触发一次 Watchdog 计划任务
#
# 为什么必须做：注册计划任务只是「排期」，并不会立刻运行。WatchdogManager.bat
# 用的触发器是 `-Once -At ((Get-Date).AddMinutes(1))`，也就是注册后 **1 分钟**
# 才第一次运行；而在这 1 分钟里没有任何组件会启动 openlist.exe —— 这正是
# 「首次部署收尾显示 Openlist 未运行、并自动打开一个空白页」的根本原因。
#
# 这里用 schtasks /Run 立刻触发，走的是 GuardCheck.ps1 同一条代码路径
# （Mutex + 进程双重去重），因此不会重复拉起 Guard。
# 触发失败不阻断部署：任务仍会按触发器在 1 分钟后自行运行。
# ============================================================
function Start-WatchdogTicks {
    if ($DryRun) {
        Write-Log 'DRYRUN' ("计划立即触发 Watchdog 计划任务：" + ($WatchdogTaskNames -join '、'))
        return $true
    }

    $allOk = $true
    foreach ($name in $WatchdogTaskNames) {
        $exit = 1
        try {
            $p = Start-Process -FilePath 'schtasks.exe' `
                -ArgumentList "/Run /TN `"$name`"" `
                -Wait -PassThru -WindowStyle Hidden
            $exit = $p.ExitCode
        } catch {
            $exit = 1
        }

        if ($exit -eq 0) {
            Write-Log 'OK' "已触发计划任务：$name"
        } else {
            Write-Log 'WARN' "触发计划任务失败（exit=$exit）：$name，将在 1 分钟后由计划任务自行运行"
            $allOk = $false
        }
    }
    return $allOk
}

# ============================================================
# Function: New-DesktopShortcut — 在桌面创建「配置向导」快捷方式
# 部署完成后在桌面放一个快捷方式，用户以后双击即可重新打开本向导，
# 不必再记/敲那一行 irm 命令。
#
# 为什么快捷方式要带「以管理员身份运行」：本向导需要安装 msi、注册计划任务，
# 都要求管理员权限。不带该标志的话，双击后要么因权限不足失败，要么由脚本自身
# 再弹一次 UAC 并另开一个窗口；带上后双击即弹 UAC、在原窗口内直接以管理员运行。
# 该标志位在 .lnk 头 LinkFlags 的 RunAsUser（0x00002000），即第 0x15 字节的
# bit5（0x20）——WScript.Shell 没有对应属性，只能创建后回写这一个字节。
#
# 创建失败不影响部署（返回 $false 并给出警告）。
# ============================================================
function New-DesktopShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$TargetScript,
        [string]$Name = 'OpenCpolarSync 配置向导'
    )

    $desktop = Get-SpecialFolder -VariableName 'Desktop' -FolderName 'Desktop'
    if (-not $desktop -or -not (Test-Path $desktop)) {
        Write-Log 'WARN' '未找到桌面目录，跳过创建快捷方式'
        return $false
    }

    $lnkPath = Join-Path $desktop ($Name + '.lnk')

    # 优先用 Windows PowerShell 5.1 的绝对路径，确保不继承 PATH 里的 pwsh/换行策略
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $psExe)) { $psExe = 'powershell.exe' }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnkPath)
        $sc.TargetPath       = $psExe
        # -NoExit：向导最后有一段人工检查清单，保留窗口便于阅读；关窗即结束
        $sc.Arguments        = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "' + $TargetScript + '"'
        $sc.WorkingDirectory = (Split-Path -Parent $TargetScript)
        $sc.Description      = 'OpenCpolarSync 配置向导 — 双击重新配置（以管理员身份运行）'
        $iconDll = Join-Path $env:SystemRoot 'System32\shell32.dll'
        if (Test-Path $iconDll) { $sc.IconLocation = "$iconDll,13" }
        $sc.Save()
        try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { }

        # 回写 RunAsUser 位（见上方说明）：让双击直接触发 UAC 提权
        if (Test-Path $lnkPath) {
            $bytes = [System.IO.File]::ReadAllBytes($lnkPath)
            if ($bytes.Length -gt 0x15) {
                $bytes[0x15] = $bytes[0x15] -bor 0x20
                [System.IO.File]::WriteAllBytes($lnkPath, $bytes)
            }
        }

        Write-Log 'OK' "已在桌面创建快捷方式：$Name"
        return $true
    } catch {
        Write-Log 'WARN' "创建桌面快捷方式失败（不影响使用）：$($_.Exception.Message)"
        return $false
    }
}

# ============================================================
# Function: Show-FinalChecklist — 输出收尾引导与人工检查清单
# Openlist 的存储挂载依赖其自身数据库，跨版本格式不稳，因此这里
# 只做引导与校验，不自动写入，避免产生易碎的强耦合逻辑。
# ============================================================
function Show-FinalChecklist {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Tunnels,
        [Parameter(Mandatory = $true)][string]$PrimaryConfigPath,
        [int]$CpolarWebPort = 9200,
        # 阶段 6 等待后的真实结果；仅用于文案，不决定是否打开页面（页面按端口实测）
        [bool]$OpenlistReady = $false,
        # Openlist 的日志目录，用于未就绪时给出可排查的位置
        [string]$OpenlistLogHint = '',
        # 用户显式跳过了 Openlist 部署：此时不该因「服务没起来」告警
        [switch]$SkipOpenlist
    )

    $openlistUrl = "http://localhost:$Port"
    $cpolarUrl   = "http://localhost:$CpolarWebPort"
    $hasTunnels  = ($Tunnels -and $Tunnels.Count -gt 0)

    Write-Host ''
    Write-Rule -Width 58 -Style Double
    Write-Host '   部署完成  ·  还需你手动完成最后一步' -ForegroundColor Cyan
    Write-Rule -Width 58 -Style Double
    Write-Host ''
    Write-Host ("   1. 登录 Openlist        " + $openlistUrl) -ForegroundColor White
    Write-Host '      账号固定为 admin，密码为部署时设置的 Openlist 登录密码' -ForegroundColor DarkGray
    Write-Host '      （若未设置，可在首次启动日志中查看随机初始密码）' -ForegroundColor DarkGray
    Write-Host '   2. 进入「存储」→「添加」，挂载你的本地目录或网盘' -ForegroundColor White
    if ($hasTunnels) {
        Write-Host ("   3. 确认隧道已在线      " + $cpolarUrl) -ForegroundColor White
        foreach ($t in $Tunnels) { Write-Host ("      · " + $t) -ForegroundColor DarkGray }
    } else {
        Write-Host ("   3. 查看隧道状态        " + $cpolarUrl) -ForegroundColor White
        Write-Host '      · 本次未配置监控隧道；需要时在配置文件的 selectedTunnelNames' -ForegroundColor DarkGray
        Write-Host '        补上隧道名，或重新运行本向导即可' -ForegroundColor DarkGray
    }
    Write-Host ''
    if (-not $OpenlistReady -and -not $DryRun -and -not $SkipOpenlist) {
        # 别让用户以为部署失败了：Openlist 未就绪只是「还没轮到它起来」。
        Write-Host '   注意：Openlist 服务尚未就绪' -ForegroundColor Yellow
        Write-Host '      它由 Watchdog 计划任务拉起（注册后 1 分钟内首次运行），稍等片刻刷新即可。' -ForegroundColor DarkGray
        if ($OpenlistLogHint) {
            Write-Host ("      若一直起不来，查看日志：" + $OpenlistLogHint) -ForegroundColor DarkGray
        }
        Write-Host ''
    }
    # 只有快捷方式确实存在时才提示，避免 -SkipShortcut / 创建失败时误导用户
    $scPath = Join-Path (Get-SpecialFolder -VariableName 'Desktop' -FolderName 'Desktop') 'OpenCpolarSync 配置向导.lnk'
    if (Test-Path $scPath) {
        Write-Host '   以后想改配置：双击桌面「OpenCpolarSync 配置向导」即可，无需再执行命令。' -ForegroundColor White
        Write-Host '   该向导同时提供「卸载」入口（运行后选择 2）。' -ForegroundColor DarkGray
        Write-Host ''
    }
    Write-Host ("   配置文件：$PrimaryConfigPath") -ForegroundColor DarkGray
    Write-Host '   后续修改配置无需重装，Guard 会在下一个轮询周期自动热加载。' -ForegroundColor DarkGray

    if ($NoBrowser) {
        Write-Log 'INFO' "已指定 -NoBrowser，跳过打开浏览器：Openlist $openlistUrl ；Cpolar $cpolarUrl"
        return
    }
    if ($DryRun) {
        Write-Log 'DRYRUN' "计划打开浏览器：Openlist $openlistUrl ；Cpolar $cpolarUrl"
        return
    }

    # Openlist 与 Cpolar 两个页面都拉起：前者用于完成存储挂载，后者用于确认隧道在线。
    # 但只打开「端口确实已在监听」的那个 —— 进程刚起时端口还没听，硬开只会得到空白页
    # （首次部署时 Openlist 尚未就绪，就是这种情况）。
    Write-Log 'STEP' '正在打开 Openlist 与 Cpolar 网页...'
    $opened = 0

    if ($SkipOpenlist) {
        Write-Log 'INFO' "已指定 -SkipOpenlist，跳过打开 $openlistUrl"
    } elseif (Test-TcpPort -Port $Port) {
        Start-Process $openlistUrl -ErrorAction SilentlyContinue
        $opened++
    } else {
        Write-Log 'WARN' "Openlist 端口 $Port 尚未监听，暂不打开页面；服务起来后访问 $openlistUrl"
    }

    # 稍作停顿，避免两个地址在同一瞬间抢夺默认浏览器实例导致只打开一个
    Start-Sleep -Milliseconds 400

    if (Test-TcpPort -Port $CpolarWebPort) {
        Start-Process $cpolarUrl -ErrorAction SilentlyContinue
        $opened++
    } else {
        Write-Log 'WARN' "Cpolar 端口 $CpolarWebPort 尚未监听，暂不打开页面；服务起来后访问 $cpolarUrl"
    }

    if ($opened -eq 0) {
        Write-Log 'INFO' '两个页面都还没就绪；稍后按上面的地址手动访问即可'
    }
}

# ============================================================
# 主流程
# ============================================================

# 不清屏，直接在当前命令行输出
Write-Banner -Title 'OpenCpolarSync  ·  一键部署向导' -Subtitle 'Cpolar 隧道监控  ·  Openlist 服务守护  ·  Watchdog 保活'
if ($DryRun) {
    Write-Host ''
    Write-Host '   演练模式：不会安装、注册或写入任何内容' -ForegroundColor Magenta
}

# --- 路径解析 -------------------------------------------------
if (-not $RootDir) {
    $RootDir = $PSScriptRoot
    if (-not $RootDir) { $RootDir = (Get-Location).Path }
}
if (-not $ConfigDir) {
    $ConfigDir = Join-Path (Get-SpecialFolder -VariableName 'LOCALAPPDATA' -FolderName 'LocalApplicationData') 'OpenCpolarSync\config'
}

$cpolarDir   = Join-Path $RootDir 'Cpolar'
$openlistDir = Join-Path $RootDir 'Openlist'
$watchdogDir = Join-Path $RootDir 'Watchdog'

$msiPath       = Join-Path $cpolarDir 'installer\cpolar_amd64.msi'
$archivePath   = Join-Path $openlistDir 'archive\openlist.zip'
$managerPath   = Join-Path $watchdogDir 'WatchdogManager.bat'
$runtimeConfig = Join-Path $cpolarDir 'config\config.json'
$primaryConfig = Join-Path $ConfigDir 'config.json'

Write-Log 'INFO' "仓库目录：$RootDir"
Write-Log 'INFO' "配置目录：$ConfigDir"

# --- 操作选择：安装 / 卸载 ------------------------------------
# 仅在「独立交互运行」（如双击桌面快捷方式）时询问：
#   -Silent 无人值守、-DryRun 演练、-NoMenu（由引导器传入）一律跳过。
# bootstrap-core.ps1 已提供同样的菜单，传 -NoMenu 可避免两层重复询问。
if (-not $Silent -and -not $DryRun -and -not $NoMenu) {
    Write-Host ''
    Write-Host '   请选择操作：' -ForegroundColor White
    Write-Host '     1. 安装 / 更新 OpenCpolarSync' -ForegroundColor White
    Write-Host '     2. 卸载 OpenCpolarSync' -ForegroundColor White
    Write-Host ''
    $choice = Read-Host '   请输入序号 (1/2) [默认 1]'

    if ($choice -eq '2') {
        Write-Host ''
        Write-Rule -Width 58
        Write-Host '   卸载 OpenCpolarSync' -ForegroundColor Cyan

        # 安装根目录 = 配置目录的上一层，即 %LOCALAPPDATA%\OpenCpolarSync
        $installRoot = Split-Path -Parent $ConfigDir
        $uninstallPath = Join-Path $RootDir 'uninstall.ps1'
        if (-not (Test-Path $uninstallPath)) {
            # 兜底：本脚本被单独复制到别处时，回到已安装目录里找
            $uninstallPath = Join-Path $installRoot 'app\uninstall.ps1'
        }
        if (-not (Test-Path $uninstallPath)) {
            Write-Log 'ERROR' "未找到 uninstall.ps1，无法卸载（已查找 $RootDir 与 $installRoot\app）"
            exit 1
        }

        Write-Log 'STEP' "调用卸载脚本：$uninstallPath"
        # 卸载同样需要管理员权限（停进程、删计划任务），未提权时经 RunAs 拉起
        if (Test-IsAdmin) {
            & $uninstallPath -InstallDir $installRoot
        } else {
            Start-Process 'powershell.exe' -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
                '-File', "`"$uninstallPath`"",
                '-InstallDir', "`"$installRoot`""
            ) -Wait
        }
        exit 0
    }
}

# --- 权限检查与自动提权 ---------------------------------------
# 注册计划任务与安装 msi 都需要管理员权限。未提权时自动以管理员重启自身，
# 并透传全部参数；-NoElevate 用于自测或已具备权限的场景。
$needsAdmin = (-not $SkipWatchdog) -or (-not $SkipCpolarInstall)
if ($needsAdmin -and -not (Test-IsAdmin) -and -not $NoElevate -and -not $DryRun) {
    Write-Log 'WARN' '需要管理员权限，正在请求提权...'

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value) { $argList += "-$($kv.Key)" }
        } elseif ($kv.Value -is [array]) {
            $argList += "-$($kv.Key)"
            $argList += "`"$($kv.Value -join ',')`""
        } else {
            $argList += "-$($kv.Key)"
            $argList += "`"$($kv.Value)`""
        }
    }
    # 提权重启后不能再弹一次操作菜单（用户已经选过了）；-NoElevate 防止二次提权死循环。
    $argList += '-NoElevate'
    $argList += '-NoMenu'

    Start-Process 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait
    exit 0
}

# --- 运行状态检查（幂等性预检） --------------------------------
# 多次运行本向导时必须能识别「已经启动过」的组件，否则会重复拉起进程。
# 本工具的 Guard 进程能通过命令行精确识别，重复即为错误 → 自动去重；
# cpolar / openlist 属于第三方进程，这里只报告数量，不擅自结束。
Write-Host ''
Write-Rule -Width 58
Write-Host '   运行状态检查' -ForegroundColor Cyan

$cpolarProcs   = @(Get-ProcessList -Name 'cpolar')
$openlistProcs = @(Get-ProcessList -Name 'openlist')
$guardProcs    = @(Get-ToolProcesses -BaseDir $RootDir)

Write-ProcessStatus -Label 'Cpolar'   -Procs $cpolarProcs
Write-ProcessStatus -Label 'Openlist' -Procs $openlistProcs

# Guard 按脚本名分组：CpolarGuard + OpenlistGuard 各一个属正常，同名 2 个才是异常
if ($guardProcs.Count -eq 0) {
    Write-Log 'INFO' 'Guard：未运行'
} else {
    foreach ($g in ($guardProcs | Group-Object -Property Label | Sort-Object Name)) {
        Write-ProcessStatus -Label ("Guard（" + $g.Name + "）") -Procs $g.Group
    }
}

# Guard 是本工具自己的进程，同名重复一定是错误 → 直接去重，保留启动最早的一个
$dupGuards = @(Select-DuplicateProcess -Procs $guardProcs)
if ($dupGuards.Count -gt 0) {
    if ($DryRun) {
        Write-Log 'DRYRUN' "计划结束 $($dupGuards.Count) 个多余的 Guard 进程（PID=$(($dupGuards | ForEach-Object { $_.Id }) -join ', ')）"
    } else {
        foreach ($d in $dupGuards) {
            try {
                Stop-Process -Id $d.Id -Force -ErrorAction Stop
                Write-Log 'OK' "已结束多余的 Guard 进程 $($d.Label)（PID=$($d.Id)）"
            } catch {
                Write-Log 'WARN' "结束 $($d.Label)（PID=$($d.Id)）失败：$($_.Exception.Message)"
            }
        }
    }
}

# 第三方进程重复时只给建议，不动手：cpolar / openlist 的进程模型不完全可控
if ($cpolarProcs.Count -gt 1) {
    Write-Log 'WARN' 'Cpolar 存在多个实例，可能互相抢占 9200 端口；确认后可手动结束多余实例'
}
if ($openlistProcs.Count -gt 1) {
    Write-Log 'WARN' 'Openlist 存在多个实例，可能互相抢占 5244 端口；确认后可手动结束多余实例'
}

# --- 阶段 1：Cpolar 安装 --------------------------------------
Write-Stage -Number 1 -Title 'Cpolar 客户端'
if ($SkipCpolarInstall) {
    Write-Log 'INFO' '已指定 -SkipCpolarInstall，跳过'
} elseif (Test-CpolarInstalled) {
    Write-Log 'OK' '检测到 Cpolar 已安装，跳过'
} else {
    Write-Log 'WARN' '未检测到 Cpolar，准备安装'
    [void](Install-Cpolar -MsiPath $msiPath)
}

# --- 阶段 2：Openlist 部署 ------------------------------------
Write-Stage -Number 2 -Title 'Openlist 服务程序'
if ($SkipOpenlist) {
    Write-Log 'INFO' '已指定 -SkipOpenlist，跳过'
} else {
    [void](Deploy-Openlist -OpenlistDir $openlistDir -ArchivePath $archivePath)
}

# --- 阶段 3：配置收集 -----------------------------------------
Write-Stage -Number 3 -Title '配置收集'
$existing = Read-ExistingConfig -Path $primaryConfig
if ($existing) { Write-Log 'INFO' '已载入现有配置作为默认值' }

# 首次配置的隧道名默认留空：见 Invoke-ConfigWizard 中的说明。
$defaultTunnel = ''
$values = @{
    WebhookUrl     = $WebhookUrl
    CpolarUser     = $CpolarUser
    CpolarPassword = $CpolarPassword
    OpenlistPassword = $OpenlistPassword
    TunnelNames    = $TunnelNames
    Interval       = $Interval
}

$values = Invoke-ConfigWizard -Values $values -Existing $existing -DefaultTunnel $defaultTunnel

if (-not $values.WebhookUrl) {
    Write-Log 'WARN' '未配置钉钉 Webhook，部署后推送告警将不可用（可稍后补填配置文件）'
}
if (-not $values.CpolarUser -or -not $values.CpolarPassword) {
    Write-Log 'WARN' '未配置 Cpolar 登录凭据，隧道状态将无法获取（可稍后补填配置文件）'
}

# --- 阶段 4：写入配置 -----------------------------------------
Write-Stage -Number 4 -Title '生成配置文件'
$configOk = New-GuardConfigFile -Values $values -PrimaryPath $primaryConfig -RuntimePath $runtimeConfig
if (-not $configOk -and -not $DryRun) {
    Write-Log 'ERROR' '配置写入失败，后续步骤已中止'
    exit 1
}

# --- 阶段 4.5：设置 Openlist 登录密码 -------------------------
if (-not $SkipOpenlist) {
    [void](Set-OpenlistAdminPassword -OpenlistDir $openlistDir -Password $values.OpenlistPassword)
}

# --- 阶段 5：Cpolar 隧道 --------------------------------------
Write-Stage -Number 5 -Title 'Cpolar 内网穿透隧道'
if ($SkipTunnel) {
    Write-Log 'INFO' '已指定 -SkipTunnel，跳过'
} elseif (-not $values.TunnelNames -or $values.TunnelNames.Count -eq 0) {
    # 首次配置默认留空，此时不必写 cpolar.yml（写了也是空的 tunnels 段）
    Write-Log 'INFO' '未配置监控隧道，跳过隧道写入（可稍后在配置文件中补充后重跑本向导）'
} else {
    [void](Set-CpolarTunnel -Tunnels $values.TunnelNames -Port $OpenlistPort -TunnelRegion $Region -Token $AuthToken)
}

# --- 阶段 6：Watchdog 注册 ------------------------------------
Write-Stage -Number 6 -Title '守护与自启'
# 收尾判断用：Openlist 此刻是否真的可用（不是「有没有配置」，是「起来没有」）
$openlistReady = $false

if ($SkipWatchdog) {
    Write-Log 'INFO' '已指定 -SkipWatchdog，跳过计划任务注册'
    # 服务可能在本轮之前就已经在跑：这里只做一次非阻塞探测，供收尾判断用
    if (-not $SkipOpenlist) {
        $openlistReady = Wait-ServiceReady -ProcessName 'openlist' -Port $OpenlistPort -TimeoutSec 0
    }
} else {
    $registered = Register-WatchdogTasks -ManagerPath $managerPath
    if ($registered) {
        # 注册只是排期（触发器为「+1 分钟」），必须立刻触发一次，否则 openlist.exe
        # 要等到 1 分钟后才由 Guard 拉起 —— 见 Start-WatchdogTicks 的说明。
        [void](Start-WatchdogTicks)

        if ($DryRun) {
            Write-Log 'DRYRUN' "计划等待 Openlist 就绪（最多 $OpenlistReadyTimeout 秒）后再输出收尾引导"
        } elseif ($SkipOpenlist) {
            Write-Log 'INFO' '已指定 -SkipOpenlist，跳过等待 Openlist 就绪'
        } else {
            Write-Log 'STEP' "等待 Openlist 就绪（最多 $OpenlistReadyTimeout 秒）..."
            if (Wait-ServiceReady -ProcessName 'openlist' -Port $OpenlistPort `
                    -TimeoutSec $OpenlistReadyTimeout -Label 'Openlist') {
                $olProcs = @(Get-ProcessList -Name 'openlist')
                $olPids = ($olProcs | ForEach-Object { $_.Id }) -join ', '
                Write-Log 'OK' "Openlist 已就绪：http://localhost:$OpenlistPort（PID=$olPids）"
                $openlistReady = $true
            } else {
                Write-Log 'WARN' '等待超时：Openlist 尚未就绪，Guard 会在后续轮询周期自动重试'
                Write-Log 'INFO' "排查日志：$(Join-Path $openlistDir 'logs\guard.log')"
            }
        }
    }
}

# --- 阶段 7：桌面快捷方式 --------------------------------------
Write-Stage -Number 7 -Title '桌面快捷方式'
$setupSelf = Join-Path $RootDir 'setup.ps1'
if ($SkipShortcut) {
    Write-Log 'INFO' '已指定 -SkipShortcut，跳过创建桌面快捷方式'
} elseif ($DryRun) {
    Write-Log 'DRYRUN' "计划在桌面创建「OpenCpolarSync 配置向导」快捷方式（以管理员身份运行，指向 $setupSelf）"
} elseif (-not (Test-Path $setupSelf)) {
    Write-Log 'WARN' "未找到 setup.ps1（$setupSelf），跳过创建快捷方式"
} else {
    [void](New-DesktopShortcut -TargetScript $setupSelf)
}

# --- 收尾引导 -------------------------------------------------
Show-FinalChecklist -Port $OpenlistPort -Tunnels $values.TunnelNames -PrimaryConfigPath $primaryConfig -CpolarWebPort 9200 -OpenlistReady $openlistReady -OpenlistLogHint (Join-Path $openlistDir 'logs\guard.log') -SkipOpenlist:$SkipOpenlist

Write-Host ''
Write-Rule -Width 58 -Style Double
Write-Log 'OK' '部署向导执行完毕'
Write-Rule -Width 58 -Style Double
