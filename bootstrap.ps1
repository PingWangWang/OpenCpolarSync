<#
.SYNOPSIS
    OpenCpolarSync 一键启动器（免 clone 部署入口）。
.DESCRIPTION
    一条命令即可完成部署，用户无需安装 git 或手动 clone 仓库：
      1. 从 GitHub / Gitee / 本地归档下载仓库压缩包
      2. 解压到 %LOCALAPPDATA%\OpenCpolarSync\app
      3. 以管理员权限调用 setup.ps1 完成后续全部部署步骤

    配置文件固定存放在 %LOCALAPPDATA%\OpenCpolarSync\config，位于 app 目录之外，
    因此重复运行本脚本升级程序时不会覆盖已有配置（对齐 Win11Debloat 的做法）。

    典型用法（在 PowerShell 中粘贴执行）：
    # 国内网络（GitHub 不通）优先用 Gitee 镜像获取本脚本：
    irm https://gitee.com/pingwang1994/OpenCpolarSync/raw/main/bootstrap.ps1 | iex
    # 或 GitHub 源（默认会自动回退 Gitee / 代理镜像下载）：
    irm https://raw.githubusercontent.com/PingWangWang/OpenCpolarSync/main/bootstrap.ps1 | iex

    编码说明：本脚本刻意保存为【无 BOM】的 UTF-8。原因是 irm 返回的内容若带 BOM，
    BOM 字符会进入脚本字符串开头，Windows PowerShell 5.1 会解析失败（注释块失效、
    中文被当作语句）。去掉 BOM 后 irm|iex 在 5.1 与 7.x 下均正常，且中文正确显示
    （irm 返回的是内存中的 Unicode 字符串，不经过文件读取）。
    代价：不要以文件方式执行本脚本（5.1 按系统 ANSI 代码页读取无 BOM 文件会损坏中文），
    已 clone 仓库时请直接运行 setup.ps1。
.PARAMETER Source
    下载来源：GitHub（默认）、Gitee 或 Local（使用本地 zip）。
.PARAMETER RepoUrl
    自定义仓库归档地址，指定后忽略 -Source。
.PARAMETER Branch
    分支名，默认 main。
.PARAMETER InstallDir
    安装根目录，默认 %LOCALAPPDATA%\OpenCpolarSync；程序解压到其下的 app 子目录。
.PARAMETER LocalArchivePath
    -Source Local 时使用的本地 zip 路径。
.PARAMETER NoSetup
    只下载解压，不自动调用 setup.ps1。
.PARAMETER DryRun
    演练模式，只打印计划，不下载不解压不执行。
.PARAMETER WebhookUrl / CpolarUser / CpolarPassword / TunnelNames / AuthToken / Interval
    透传给 setup.ps1 的配置项，用于无人值守部署。
.PARAMETER Silent
    透传给 setup.ps1，使其以非交互方式运行。
.EXAMPLE
    .\bootstrap.ps1
    交互方式下载并部署。
.EXAMPLE
    .\bootstrap.ps1 -Source Gitee
    从 Gitee 镜像下载（GitHub 访问不畅时使用）。
.NOTES
    Version: 1.1
    Compatible: Windows 7 SP1+ / PowerShell 5.0+
                实测通过：Windows PowerShell 5.1.26100（Windows 预装版）、PowerShell 7.6.4
#>

param(
    [ValidateSet('GitHub', 'Gitee', 'Local')]
    [string]$Source = 'GitHub',

    [string]$RepoUrl,
    [string]$Branch = 'main',
    [string]$InstallDir,
    [string]$LocalArchivePath,

    [switch]$NoSetup,
    [switch]$DryRun,

    [string]$WebhookUrl,
    [string]$CpolarUser,
    [string]$CpolarPassword,
    [string[]]$TunnelNames,
    [string]$AuthToken,
    [int]$Interval,
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'

# 设置 UTF-8 输出编码以正确显示中文；非控制台环境下该属性可能不可用，做保护处理
try {
    # Windows PowerShell 5.1 的控制台默认使用系统 ANSI 代码页（简体中文为 936/GBK），
    # 此时强行改为 UTF-8 会让中文提示在控制台显示为乱码；因此仅在 PowerShell 6+
    # 或控制台本身已是 UTF-8(65001) 时才同步输出编码。
    if ($PSVersionTable.PSVersion.Major -ge 6 -or [Console]::OutputEncoding.CodePage -eq 65001) {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
    }
} catch { }

# ============================================================
# Function: Write-Log — 输出带级别着色的中文日志
# ============================================================
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'STEP', 'OK', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'STEP'  { 'Cyan' }
        default { 'Gray' }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}

# ============================================================
# Function: Resolve-ArchiveUrl — 按来源解析仓库归档地址
# 提供 GitHub / Gitee / GitHubProxy（ghproxy 代理镜像）三源，便于在国内网络环境下切换。
# ============================================================
function Resolve-ArchiveUrl {
    param(
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$RefBranch,
        [string]$Custom
    )

    if ($Custom) { return $Custom }

    switch ($From) {
        'GitHub'     { return "https://github.com/PingWangWang/OpenCpolarSync/archive/refs/heads/$RefBranch.zip" }
        'GitHubProxy'{ return "https://ghproxy.com/https://github.com/PingWangWang/OpenCpolarSync/archive/refs/heads/$RefBranch.zip" }
        'Gitee'      { return "https://gitee.com/pingwang1994/OpenCpolarSync/repository/archive/$RefBranch.zip" }
        default      { return $null }
    }
}

# ============================================================
# Function: Test-ZipFile — 校验下载内容是否为可解压的有效 ZIP
# 仅靠 Invoke-WebRequest 的“下载成功”不足以判断拿到的是压缩包：当镜像源返回
# 登录页/错误页/拦截页（HTTP 200 的 HTML）时，下载也会“成功”，但 Expand-Archive
# 会报“找不到中央目录结尾记录”。这里通过魔数 + 完整性打开做前置拦截。
# ============================================================
function Test-ZipFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) { return $false }

    # 魔数校验：合法的 ZIP 以 PK（0x50 0x4B）开头
    $buf = New-Object byte[] 4
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        if ($fs.Read($buf, 0, 4) -ne 4) { return $false }
    } finally {
        $fs.Close()
    }
    if (-not ($buf[0] -eq 0x50 -and $buf[1] -eq 0x4B)) { return $false }

    # 魔数通过即视为有效 ZIP。下方完整性打开为“尽力而为”：仅用于提前暴露截断/损坏，
    # 若运行环境缺少相应程序集或打开失败，一律信任魔数结果（返回 $true），
    # 避免把合法 zip 误判为无效；真正的损坏会由后续 Expand-Archive 清晰报错。
    try {
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        $fs2 = [System.IO.File]::OpenRead($Path)
        try {
            $za = New-Object System.IO.Compression.ZipArchive($fs2, [System.IO.Compression.ZipArchiveMode]::Read)
            $za.Dispose()
        } finally {
            $fs2.Close()
        }
    } catch { }

    return $true
}

# ============================================================
# Function: Get-RepoArchive — 下载仓库压缩包
# 部分 Windows 环境对 GitHub 的证书吊销检查会失败（CRYPT_E_NO_REVOCATION_CHECK），
# 这里放宽服务端证书校验以避免下载被无谓中断。下载完成后会校验内容是否为有效
# ZIP，拒绝登录页/错误页/被拦截的响应，使“所有来源失败”能优雅回退而非在解压时崩溃。
# ============================================================
function Get-RepoArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

    Write-Log 'STEP' "正在下载：$Url"
    $progressPreference = 'SilentlyContinue'

    # -PassThru 以读取响应头（Content-Type），识别 HTML 错误/登录页
    $resp = Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -PassThru

    # 校验 1：响应类型不应是 HTML（HTML 通常是登录页/拦截页，而非压缩包）
    $ct = ''
    try { $ct = $resp.Headers['Content-Type'] } catch { }
    if ($ct -and $ct -match 'text/html') {
        Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        throw "返回内容类型为 HTML（$ct）：来源可能返回了登录页或错误页，而非 ZIP 压缩包"
    }

    # 校验 2：ZIP 魔数（PK）+ 可打开完整性，拒绝被网络拦截/截断的响应（HTML/非压缩包）
    if (-not (Test-ZipFile -Path $Destination)) {
        Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        throw '下载内容不是有效的 ZIP 压缩包（魔数或完整性校验失败），来源可能返回了登录页/错误页'
    }

    $len = (Get-Item $Destination).Length
    Write-Log 'OK' "下载完成（$([math]::Round($len / 1MB, 2)) MB）"
}

# ============================================================
# 主流程
# ============================================================

# 清屏在非控制台环境下可能失败，做保护处理
try { Clear-Host } catch { }
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ' OpenCpolarSync 一键部署' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan

# --- 路径解析 -------------------------------------------------
if (-not $InstallDir) {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'OpenCpolarSync'
}
$appDir   = Join-Path $InstallDir 'app'
$configDir = Join-Path $InstallDir 'config'
$tempZip  = Join-Path $env:TEMP "OpenCpolarSync-$Branch.zip"

Write-Log 'INFO' "安装目录：$appDir"
Write-Log 'INFO' "配置目录：$configDir（不受升级影响）"

if ($DryRun) {
    Write-Host ' 演练模式：不会下载、解压或执行任何操作' -ForegroundColor Magenta
}

# --- 阶段 1：获取仓库文件 -------------------------------------
Write-Host ''
Write-Host '--- 阶段 1：获取程序文件 ---' -ForegroundColor Cyan

if ($DryRun) {
    if ($Source -eq 'Local') {
        Write-Log 'INFO' "计划使用本地归档：$LocalArchivePath"
    } else {
        $drySources = if ($Source -eq 'GitHub') { @('GitHub', 'GitHubProxy', 'Gitee') } else { @($Source) }
        foreach ($s in $drySources) {
            Write-Log 'INFO' "计划下载（$s）：$(Resolve-ArchiveUrl -From $s -RefBranch $Branch -Custom $RepoUrl)"
        }
        Write-Log 'INFO' '（GitHub 不通时自动回退 代理镜像 / Gitee）'
    }
    Write-Log 'INFO' "计划解压到：$appDir"
} elseif ($Source -eq 'Local') {
    # 本地兜底：直接使用已有的 zip，适用于完全离线的环境
    if (-not $LocalArchivePath -or -not (Test-Path $LocalArchivePath)) {
        Write-Log 'ERROR' "-Source Local 需要提供有效的 -LocalArchivePath"
        exit 1
    }
    if (-not (Test-ZipFile -Path $LocalArchivePath)) {
        Write-Log 'ERROR' "本地归档不是有效的 ZIP 压缩包：$LocalArchivePath"
        Write-Host '请用仓库归档（如 main.zip）而不是网页/日志等文件。' -ForegroundColor Yellow
        exit 1
    }
    Write-Log 'OK' "使用本地归档：$LocalArchivePath"
    $tempZip = $LocalArchivePath
} else {
    # 下载来源列表：默认 GitHub，失败时依次回退 代理镜像 / Gitee，让「irm | iex」一行命令
    # 在国内网络（GitHub 不通）也能跑通，无需用户手动追加 -Source Gitee。
    $trySources = if ($Source -eq 'GitHub') { @('GitHub', 'GitHubProxy', 'Gitee') } else { @($Source) }

    $downloaded = $false
    foreach ($trySrc in $trySources) {
        $url = Resolve-ArchiveUrl -From $trySrc -RefBranch $Branch -Custom $RepoUrl
        try {
            Write-Log 'INFO' "尝试来源：$trySrc"
            Get-RepoArchive -Url $url -Destination $tempZip
            $downloaded = $true
            break
        } catch {
            Write-Log 'WARN' "$trySrc 下载失败：$($_.Exception.Message)"
            if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
        }
    }

    if (-not $downloaded) {
        Write-Log 'ERROR' '所有来源均下载失败或返回了无效的压缩包'
        Write-Host ''
        Write-Host '排查建议：' -ForegroundColor Yellow
        Write-Host '  1) 若提示“不是有效的 ZIP / 返回 HTML”，说明镜像源返回了登录页或错误页，' -ForegroundColor Yellow
        Write-Host '     通常是该仓库为私有或被网络拦截。请改用本地归档离线部署：' -ForegroundColor Yellow
        Write-Host '     .\bootstrap.ps1 -Source Local -LocalArchivePath "D:\path\to\main.zip"' -ForegroundColor Yellow
        Write-Host '  2) 或先 clone 再运行（国内可用 Gitee 源）：' -ForegroundColor Yellow
        Write-Host '     git clone https://gitee.com/pingwang1994/OpenCpolarSync.git ; .\setup.ps1' -ForegroundColor Yellow
        Write-Host '  3) 也可手动下载 zip 后离线部署：' -ForegroundColor Yellow
        Write-Host '     https://gitee.com/pingwang1994/OpenCpolarSync/repository/archive/main.zip' -ForegroundColor Yellow
        exit 1
    }
}

# --- 阶段 2：解压 ---------------------------------------------
Write-Host ''
Write-Host '--- 阶段 2：解压程序文件 ---' -ForegroundColor Cyan

if (-not $DryRun) {
    if (-not (Test-Path $appDir)) {
        New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    }

    Write-Log 'STEP' "正在解压到 $appDir"
    Expand-Archive -Path $tempZip -DestinationPath $appDir -Force

    # 压缩包通常带一层 OpenCpolarSync-<branch> 目录，将其内容提升到 app 根目录
    $inner = Get-ChildItem -Path $appDir -Directory |
        Where-Object { $_.Name -like 'OpenCpolarSync-*' } |
        Select-Object -First 1

    if ($inner) {
        Get-ChildItem -Path $inner.FullName -Force | ForEach-Object {
            $target = Join-Path $appDir $_.Name
            if (Test-Path $target) { Remove-Item $target -Recurse -Force }
            Move-Item -Path $_.FullName -Destination $target -Force
        }
        Remove-Item $inner.FullName -Recurse -Force
    }

    Write-Log 'OK' '解压完成'

    # 清理临时归档（本地模式不删除用户提供的文件）
    if ($Source -ne 'Local' -and (Test-Path $tempZip)) {
        Remove-Item $tempZip -Force
        Write-Log 'OK' '已清理临时下载文件'
    }
}

# --- 阶段 3：调用部署向导 -------------------------------------
$setupPath = Join-Path $appDir 'setup.ps1'

if ($NoSetup) {
    Write-Host ''
    Write-Log 'INFO' "已指定 -NoSetup，程序已就绪于：$appDir"
    exit 0
}

if (-not $DryRun -and -not (Test-Path $setupPath)) {
    Write-Log 'ERROR' "解压后未找到 setup.ps1：$setupPath"
    exit 1
}

Write-Host ''
Write-Host '--- 阶段 3：执行部署向导 ---' -ForegroundColor Cyan

# 组装透传给 setup.ps1 的参数，保留用户在命令行上给出的全部配置
$setupArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$setupPath`"")

if ($WebhookUrl)     { $setupArgs += '-WebhookUrl';     $setupArgs += "`"$WebhookUrl`"" }
if ($CpolarUser)     { $setupArgs += '-CpolarUser';     $setupArgs += "`"$CpolarUser`"" }
if ($CpolarPassword) { $setupArgs += '-CpolarPassword'; $setupArgs += "`"$CpolarPassword`"" }
if ($TunnelNames)    { $setupArgs += '-TunnelNames';    $setupArgs += "`"$($TunnelNames -join ',')`"" }
if ($AuthToken)      { $setupArgs += '-AuthToken';      $setupArgs += "`"$AuthToken`"" }
if ($Interval -gt 0) { $setupArgs += '-Interval';       $setupArgs += $Interval }
if ($Silent)         { $setupArgs += '-Silent' }

# 优先使用当前宿主（5.1 用 powershell.exe，7.x 用 pwsh.exe），
# 避免硬编码 powershell.exe 导致在 PowerShell 7 下把 setup.ps1 降级到 5.1 执行
$psExe = 'powershell.exe'
try {
    $currentExe = [System.Diagnostics.Process]::GetCurrentProcess().Path
    if ($currentExe -and (Test-Path -LiteralPath $currentExe) -and ($currentExe -match 'powershell|pwsh')) {
        $psExe = $currentExe
    }
} catch { }

if ($DryRun) {
    Write-Log 'INFO' "计划以管理员权限执行：$psExe $($setupArgs -join ' ')"
    exit 0
}

Write-Log 'STEP' '正在以管理员权限启动部署向导'
Start-Process $psExe -Verb RunAs -ArgumentList $setupArgs -Wait

Write-Host ''
Write-Log 'OK' '部署向导已结束'
