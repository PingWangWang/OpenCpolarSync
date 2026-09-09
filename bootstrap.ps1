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
    irm https://raw.githubusercontent.com/PingWangWang/OpenCpolarSync/main/bootstrap.ps1 | iex
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
    Version: 1.0
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
# 提供 GitHub / Gitee 双源，便于在国内网络环境下切换。
# ============================================================
function Resolve-ArchiveUrl {
    param(
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$RefBranch,
        [string]$Custom
    )

    if ($Custom) { return $Custom }

    switch ($From) {
        'GitHub' { return "https://github.com/PingWangWang/OpenCpolarSync/archive/refs/heads/$RefBranch.zip" }
        'Gitee'  { return "https://gitee.com/pingwang1994/OpenCpolarSync/repository/archive/$RefBranch.zip" }
        default  { return $null }
    }
}

# ============================================================
# Function: Get-RepoArchive — 下载仓库压缩包
# 部分 Windows 环境对 GitHub 的证书吊销检查会失败（CRYPT_E_NO_REVOCATION_CHECK），
# 这里放宽服务端证书校验以避免下载被无谓中断。
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
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    Write-Log 'OK' "下载完成（$([math]::Round((Get-Item $Destination).Length / 1MB, 2)) MB）"
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
    $url = Resolve-ArchiveUrl -From $Source -RefBranch $Branch -Custom $RepoUrl
    if ($Source -eq 'Local') {
        Write-Log 'INFO' "计划使用本地归档：$LocalArchivePath"
    } else {
        Write-Log 'INFO' "计划下载：$url"
    }
    Write-Log 'INFO' "计划解压到：$appDir"
} elseif ($Source -eq 'Local') {
    # 本地兜底：直接使用已有的 zip，适用于完全离线的环境
    if (-not $LocalArchivePath -or -not (Test-Path $LocalArchivePath)) {
        Write-Log 'ERROR' "-Source Local 需要提供有效的 -LocalArchivePath"
        exit 1
    }
    Write-Log 'OK' "使用本地归档：$LocalArchivePath"
    $tempZip = $LocalArchivePath
} else {
    $url = Resolve-ArchiveUrl -From $Source -RefBranch $Branch -Custom $RepoUrl
    try {
        Get-RepoArchive -Url $url -Destination $tempZip
    } catch {
        Write-Log 'ERROR' "下载失败：$($_.Exception.Message)"
        Write-Host ''
        Write-Host '若当前网络无法访问 GitHub，可改用 Gitee 镜像：' -ForegroundColor Yellow
        Write-Host '  .\bootstrap.ps1 -Source Gitee' -ForegroundColor Yellow
        Write-Host '或使用本地归档包：' -ForegroundColor Yellow
        Write-Host '  .\bootstrap.ps1 -Source Local -LocalArchivePath "D:\path\to\main.zip"' -ForegroundColor Yellow
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
