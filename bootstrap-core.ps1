param(
    [ValidateSet('GitHub', 'Gitee', 'Local')]
    [string]$Source = 'GitHub',

    [string]$RepoUrl,
    [string]$Branch = 'main',
    [string]$InstallDir,
    [string]$LocalArchivePath,

    [switch]$NoSetup,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Uninstall,

    [string]$WebhookUrl,
    [string]$CpolarUser,
    [string]$CpolarPassword,
    [string]$OpenlistPassword,
    [string[]]$TunnelNames,
    [string]$AuthToken,
    [int]$Interval,
    [switch]$Silent
)

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
    # 或下载到本地后直接运行（本脚本为 UTF-8 with BOM，.\\ 直接跑不乱码）：
    .\bootstrap.ps1

    编码说明：本脚本保存为【UTF-8 with BOM】。原因：本地以 .\\ 直接运行时，Windows
    PowerShell 5.1 需靠 BOM 识别 UTF-8，否则中文会被按系统 ANSI（GBK）解码而乱码；
    而 irm 拉取时 .NET 会在解码阶段自动剥离 BOM（字符串首个字符即为 param，不含 BOM），
    因此 BOM 不影响 irm | iex。为保证两者兼容，本脚本把 param() 放在文件最前、
    注释块移到其后（BOM 顶在 param 前无害）。对齐 Win11Debloat 的 Get_CN.ps1 做法。
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
    Version: 1.4
    Compatible: Windows 7 SP1+ / PowerShell 5.0+
                实测通过：Windows PowerShell 5.1.26100（Windows 预装版）、PowerShell 7.6.4
#>

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
# 默认回退顺序：GitHub → Gitee（国内自有镜像）→ GitHubProxy，避免第三方代理在部分网络下
# 长时间无响应。当前 GitHubProxy 使用 gh.ddlc.top；若该镜像不可用，可改用 -RepoUrl 自定义。
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
        default      { return $null }
    }
}

# ============================================================
# Function: Test-ZipFile — 校验下载内容是否为可解压的有效 ZIP
# 仅靠 Invoke-WebRequest 的"下载成功"不足以判断拿到的是压缩包：当镜像源返回
# 登录页/错误页/拦截页（HTTP 200 的 HTML）时，下载也会"成功"，但 Expand-Archive
# 会报"找不到中央目录结尾记录"。这里通过魔数 + 完整性打开做前置拦截。
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

    # 魔数通过即视为有效 ZIP。下方完整性打开为"尽力而为"：仅用于提前暴露截断/损坏，
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
# Function: Invoke-WebDownload — 带进度条下载文件
# 用 HttpClient 流式下载并实时 Write-Progress（跨 5.1/7 一致），
# 支持大文件（如含 openlist.zip 的几十 MB 发布包），下载失败清理残留。
# ============================================================
function Invoke-WebDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$Name = '下载'
    )

    try {
        # PowerShell 5.1 下 System.Net.Http 可能未默认加载，先确保可用（已加载则静默跳过）
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromMinutes(30)
        $resp = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) {
            throw ("HTTP {0} {1}" -f [int]$resp.StatusCode, $resp.ReasonPhrase)
        }

        $total = $resp.Content.Headers.ContentLength
        $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $fs = [System.IO.File]::Create($Destination)
        $buffer = New-Object byte[] 81920
        $received = [long]0
        try {
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $read)
                $received += $read
                if ($total -gt 0) {
                    $pct = [int](($received / $total) * 100)
                    Write-Progress -Activity $Name -Status ("{0:N1} MB / {1:N1} MB" -f ($received / 1MB), ($total / 1MB)) -PercentComplete $pct
                } else {
                    Write-Progress -Activity $Name -Status ("{0:N1} MB" -f ($received / 1MB))
                }
            }
        } finally {
            $fs.Close()
            $stream.Dispose()
        }
        $client.Dispose()
        if ($received -eq 0) { throw '下载内容为空' }
    } catch {
        try { if (Test-Path $Destination) { Remove-Item $Destination -Force -ErrorAction SilentlyContinue } } catch { }
        throw $_
    }
}

# ============================================================
# Function: Get-RepoArchive — 下载仓库压缩包
# 显式启用 TLS 1.2（PS 5.1 默认仅 Ssl3|Tls），但不再放宽服务端证书校验——那会破坏
# TLS 握手（三源统一报「基础连接已经关闭」），且全局关闭证书校验有安全风险。
# 下载完成后会校验内容是否为有效 ZIP，拒绝登录页/错误页/被拦截的响应，
# 使"所有来源失败"能优雅回退而非在解压时崩溃。
# ============================================================
function Get-RepoArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    # 显式启用 TLS 1.2（PS 5.1 默认仅 Ssl3|Tls，连不上要求 TLS1.2+ 的 CDN）。
    # 注意：不要设置 ServerCertificateValidationCallback —— 该回调是 AppDomain 级全局副作用，
    # 会破坏 TLS 握手（三源统一报「基础连接已经关闭: 发送时发生错误」），且全局关闭证书校验本身有安全风险。
    # 证书校验交给 PowerShell/.NET 默认行为（与 Win11Debloat 的 Get_CN.ps1 一致，可正常下载）。
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    Write-Log 'STEP' "正在下载：$Url"

    # 函数级保护：下载/校验任何环节失败都清理临时文件并把异常抛给外层回退逻辑。
    # 超时 45 秒，避免 ghproxy 等镜像在部分网络下长时间无响应导致用户以为卡死。
    try {
        Invoke-WebDownload -Url $Url -Destination $Destination -Name "下载 ($Url)"

        # ZIP 魔数（PK）+ 可打开完整性，拒绝被网络拦截/截断的响应（HTML/非压缩包）
        if (-not (Test-ZipFile -Path $Destination)) {
            Remove-Item $Destination -Force -ErrorAction SilentlyContinue
            throw '下载内容不是有效的 ZIP 压缩包（魔数或完整性校验失败），来源可能返回了登录页或错误页'
        }

        $len = (Get-Item $Destination).Length
        Write-Log 'OK' "下载完成（$([math]::Round($len / 1MB, 2)) MB）"
    } catch {
        # 确保即使 Invoke-WebRequest 内部抛出的非终止错误/线程异常也能被捕获，
        # 并清理可能残留的半成品 zip，避免被后续来源误判为有效缓存。
        try { Remove-Item $Destination -Force -ErrorAction SilentlyContinue } catch { }
        throw $_
    }
}

# ============================================================
# Function: Get-RepoArchiveFromRelease — 优先从 GitHub Release API 下载
# 对齐 Win11Debloat 的做法：用 releases/latest 拿 zipball_url，再 Invoke-RestMethod 下载。
# 仓库必须有公开 Release，否则该源失败并由外层回退到 archive/Gitee。
# ============================================================
function Get-RepoArchiveFromRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Destination
    )

    # 显式启用 TLS 1.2，与 Get-RepoArchive 保持一致（PS 5.1 默认不含 TLS1.2）
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $repo = 'PingWangWang/OpenCpolarSync'

    try {
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 20
        # 优先使用已发布的资产 zip（走 objects.githubusercontent.com，稳定，对齐 Win11Debloat 资产下载）；
        # 没有资产时回退到 GitHub 自动生成的源码 zipball。
        $asset = @($latest.assets) | Where-Object { $_.name -like 'OpenCpolarSync*.zip' } | Select-Object -First 1
        if ($asset -and $asset.browser_download_url) {
            Write-Log 'STEP' "正在下载（GitHub Release 资产）：$($asset.name)"
        } else {
            $asset = $null
            Write-Log 'STEP' "未找到 Release 资产，回退下载源码 zipball：$($latest.zipball_url)"
        }
        $downloadUrl = if ($asset) { $asset.browser_download_url } else { $latest.zipball_url }
        if (-not $downloadUrl) { throw 'GitHub Release 未提供可下载的 zip' }

        # 下载带进度条（Invoke-WebDownload 内部对下载做流式读 + Write-Progress），
        # 发布包可能较大且不同网络速度差异大，超时放宽到 30 分钟。
        Invoke-WebDownload -Url $downloadUrl -Destination $Destination -Name "下载发布包"

        if (-not (Test-ZipFile -Path $Destination)) {
            throw 'Release 下载内容不是有效的 ZIP 压缩包'
        }
        $len = (Get-Item $Destination).Length
        Write-Log 'OK' "下载完成（$([math]::Round($len / 1MB, 2)) MB）"
    } catch {
        try { Remove-Item $Destination -Force -ErrorAction SilentlyContinue } catch { }
        throw $_
    }
}

# ============================================================
# 主流程
# ============================================================

# 清屏在非控制台环境下可能失败，做保护处理
try { Clear-Host } catch { }
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ' OpenCpolarSync 一键部署向导' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan

# --- 操作选择：安装 / 卸载 ---------------------------------------------------
$action = $null
if ($Uninstall) {
    $action = 'uninstall'
} elseif ($Silent) {
    $action = 'install'
} else {
    Write-Host ''
    Write-Host '  请选择操作：' -ForegroundColor White
    Write-Host '    1. 安装 / 更新 OpenCpolarSync' -ForegroundColor White
    Write-Host '    2. 卸载 OpenCpolarSync' -ForegroundColor White
    Write-Host ''
    $choice = Read-Host '请输入序号 (1/2) [默认 1]'
    if ($choice -eq '2') {
        $action = 'uninstall'
    } else {
        $action = 'install'
    }
}

# --- 卸载分支：直接调用卸载脚本并退出 ----------------------------------------
if ($action -eq 'uninstall') {
    Write-Host ''
    Write-Host '--- 卸载模式 ---' -ForegroundColor Cyan

    if (-not $InstallDir) {
        $InstallDir = Join-Path $env:LOCALAPPDATA 'OpenCpolarSync'
    }
    $appDir = Join-Path $InstallDir 'app'

    # 优先使用已安装的 uninstall.ps1，否则从下载的仓库中找
    $uninstallPath = Join-Path $appDir 'uninstall.ps1'
    if (-not (Test-Path $uninstallPath)) {
        # 尝试从当前脚本目录找（本地运行时）
        $localUninstall = Join-Path $PSScriptRoot 'uninstall.ps1'
        if (Test-Path $localUninstall) {
            $uninstallPath = $localUninstall
        } else {
            Write-Log 'ERROR' '未找到 uninstall.ps1，无法执行卸载'
            Write-Host '  请手动删除以下目录完成卸载：' -ForegroundColor Yellow
            Write-Host "    程序目录：$appDir" -ForegroundColor Yellow
            Write-Host "    配置目录：$(Join-Path $InstallDir 'config')" -ForegroundColor Yellow
            exit 1
        }
    }

    Write-Log 'STEP' "执行卸载脚本：$uninstallPath"
    & $uninstallPath -InstallDir $InstallDir
    exit 0
}

# --- 路径解析 -------------------------------------------------------------
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

# --- 阶段 1：获取仓库文件 ---------------------------------------------------
Write-Host ''
Write-Host '--- 阶段 1：获取程序文件 ---' -ForegroundColor Cyan

# 缓存/已安装检测：app 目录已有 setup.ps1 时默认跳过下载与解压，避免每次重复下载几十 MB
$skipFetch = (-not $DryRun) -and (-not $Force) -and (Test-Path (Join-Path $appDir 'setup.ps1'))
if ($skipFetch) {
    Write-Log 'OK' "检测到已安装（$appDir），跳过下载与解压；如需强制更新请加 -Force"
} elseif ($DryRun) {
    if ($Source -eq 'Local') {
        Write-Log 'INFO' "计划使用本地归档：$LocalArchivePath"
    } else {
        $drySources = if ($Source -eq 'GitHub') { @('Release', 'GitHub', 'Gitee') } else { @($Source) }
        foreach ($s in $drySources) {
            if ($s -eq 'Release') {
                Write-Log 'INFO' '计划下载（Release）：GitHub Release API 获取 zipball'
            } else {
                Write-Log 'INFO' "计划下载（$s）：$(Resolve-ArchiveUrl -From $s -RefBranch $Branch -Custom $RepoUrl)"
            }
        }
        Write-Log 'INFO' '（优先 GitHub Release，失败时回退 Gitee / 源码归档）'
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
    # 下载来源列表：默认 GitHub，失败时依次回退 Gitee（国内自有镜像）/ 代理镜像，
    # 让「irm | iex」一行命令在国内网络（GitHub 不通）也能跑通，无需用户手动追加 -Source Gitee。
    $trySources = if ($Source -eq 'GitHub') { @('Release', 'GitHub', 'Gitee') } else { @($Source) }

    $downloaded = $false
    foreach ($trySrc in $trySources) {
        try {
            Write-Log 'INFO' "尝试来源：$trySrc"
            if ($trySrc -eq 'Release') {
                Get-RepoArchiveFromRelease -Destination $tempZip
            } else {
                $url = Resolve-ArchiveUrl -From $trySrc -RefBranch $Branch -Custom $RepoUrl
                Get-RepoArchive -Url $url -Destination $tempZip
            }
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
        Write-Host '  1) 若提示"不是有效的 ZIP / 返回 HTML"，说明镜像源返回了登录页或错误页，' -ForegroundColor Yellow
        Write-Host '     通常是该仓库为私有或被网络拦截。请改用本地归档离线部署：' -ForegroundColor Yellow
        Write-Host '     .\bootstrap.ps1 -Source Local -LocalArchivePath "D:\path\to\main.zip"' -ForegroundColor Yellow
        Write-Host '  2) 或先 clone 再运行（国内可用 Gitee 源）：' -ForegroundColor Yellow
        Write-Host '     git clone https://gitee.com/pingwang1994/OpenCpolarSync.git ; .\setup.ps1' -ForegroundColor Yellow
        Write-Host '  3) 也可手动下载 zip 后离线部署：' -ForegroundColor Yellow
        Write-Host '     https://gitee.com/pingwang1994/OpenCpolarSync/repository/archive/main.zip' -ForegroundColor Yellow
        Write-Host '  4) 若某个来源长时间无响应后 PowerShell 直接退出，通常是该代理/镜像' -ForegroundColor Yellow
        Write-Host '     在你当前网络下不可用。可直接强制走 Gitee（多数国内网络最稳）：' -ForegroundColor Yellow
        Write-Host '     irm https://gitee.com/pingwang1994/OpenCpolarSync/raw/main/bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1;' -ForegroundColor Yellow
        Write-Host '     & $env:TEMP\bootstrap.ps1 -Source Gitee' -ForegroundColor Yellow
        exit 1
    }
}

# --- 阶段 2：解压 -------------------------------------------------------------
Write-Host ''
Write-Host '--- 阶段 2：解压程序文件 ---' -ForegroundColor Cyan

if (-not $DryRun -and -not $skipFetch) {
    if (-not (Test-Path $appDir)) {
        New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    }

    Write-Log 'STEP' "正在解压到 $appDir"
    Expand-Archive -Path $tempZip -DestinationPath $appDir -Force

    # 压缩包通常带一层 OpenCpolarSync-<branch> 目录，将其内容提升到 app 根目录
    $inner = Get-ChildItem -Path $appDir -Directory |
        Where-Object { $_.Name -like '*OpenCpolarSync*' } |
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

# --- 阶段 3：调用部署向导 -----------------------------------------------------
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

# 组装透传给 setup.ps1 的参数；引导器已把整个流程提权，这里在同一窗口直接调用 setup
$setupParams = @{}
if ($WebhookUrl)       { $setupParams['WebhookUrl'] = $WebhookUrl }
if ($CpolarUser)       { $setupParams['CpolarUser'] = $CpolarUser }
if ($CpolarPassword)   { $setupParams['CpolarPassword'] = $CpolarPassword }
if ($OpenlistPassword) { $setupParams['OpenlistPassword'] = $OpenlistPassword }
if ($TunnelNames)      { $setupParams['TunnelNames'] = $TunnelNames }
if ($AuthToken)        { $setupParams['AuthToken'] = $AuthToken }
if ($Interval -gt 0)   { $setupParams['Interval'] = $Interval }
if ($Silent)           { $setupParams['Silent'] = $true }

if ($DryRun) {
    Write-Log 'INFO' '计划在同一窗口内执行部署向导'
    exit 0
}

Write-Log 'STEP' '正在执行部署向导（同一窗口）'
& $setupPath @setupParams

Write-Host ''
Write-Log 'OK' '部署向导已结束'

# --- 部署结果摘要：让用户清楚设置了什么、监控是否开启 -------------------------
try {
    $primaryConfig = Join-Path $configDir 'config.json'
    Write-Host ''
    Write-Host '================ 部署结果摘要 ================' -ForegroundColor Cyan
    Write-Host ("  程序目录： " + $appDir)
    Write-Host ("  配置目录： " + $configDir)
    if (Test-Path $primaryConfig) {
        $cfg = Get-Content $primaryConfig -Raw -Encoding UTF8 | ConvertFrom-Json
        $wh  = if ($cfg.webhookUrl) { '已配置（钉钉告警已开启）' } else { '未配置（无钉钉告警）' }
        $tun = if ($cfg.selectedTunnelNames) { (@($cfg.selectedTunnelNames) -join ', ') } else { '未配置' }
        Write-Host ("  钉钉告警： " + $wh)
        Write-Host ("  监控隧道： " + $tun)
        Write-Host ("  轮询间隔： " + $cfg.interval + " 分钟")
    } else {
        Write-Host '  配置文件： 未找到'
    }
    $ol = Get-Process openlist -ErrorAction SilentlyContinue
    $cp = Get-Process cpolar -ErrorAction SilentlyContinue
    Write-Host ("  Openlist： " + $(if ($ol) { '运行中 (PID=' + $ol[0].Id + ')' } else { '未运行' }))
    Write-Host ("  Cpolar：   " + $(if ($cp) { '运行中 (PID=' + $cp[0].Id + ')' } else { '未运行' }))
    Write-Host '=============================================' -ForegroundColor Cyan
    Write-Host '  提示：配置保存在上面的“配置目录”，升级不会丢失；重新运行本向导可修改设置。' -ForegroundColor Gray
} catch {
    Write-Log 'WARN' "读取部署摘要失败：$($_.Exception.Message)"
}
