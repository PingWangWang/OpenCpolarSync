<#
.SYNOPSIS
    OpenCpolarSync 一键部署向导。
.DESCRIPTION
    把原本需要手工完成的 5~6 个部署步骤收敛为一条命令：
      1. 检测并静默安装 Cpolar（未安装时自动安装仓库自带的 msi）
      2. 从 archive/openlist.zip 解压 openlist.exe 到 Openlist/ 目录
      3. 交互式收集配置并生成 config.json（持久化到用户目录，升级不丢失）
      4. 配置 Cpolar 内网穿透隧道（写入 cpolar.yml 并注册 authtoken）
      5. 注册 Watchdog 计划任务（S4U）并立即拉起 Cpolar / Openlist 两个 Guard
      6. 打开 Openlist Web 引导完成存储挂载（当前唯一需人工介入的步骤）

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
.PARAMETER NoElevate
    禁止自动请求管理员提权（供自测或已具备权限的场景使用）。
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

    [switch]$SkipCpolarInstall,
    [switch]$SkipOpenlist,
    [switch]$SkipTunnel,
    [switch]$SkipWatchdog,
    [switch]$NoBrowser,
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
# Function: Write-Log — 输出带级别着色的中文日志
# ============================================================
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'STEP', 'OK', 'WARN', 'ERROR', 'DRYRUN')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $color = switch ($Level) {
        'OK'     { 'Green' }
        'WARN'   { 'Yellow' }
        'ERROR'  { 'Red' }
        'STEP'   { 'Cyan' }
        'DRYRUN' { 'Magenta' }
        default  { 'Gray' }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
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
        [Parameter(Mandatory = $true)][string]$Title
    )

    Write-Host ''
    Write-Host "--- 阶段 $Number：$Title ---" -ForegroundColor Cyan
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
        Write-Log 'ERROR' "未找到 Cpolar 安装包：$MsiPath"
        return $false
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
        Write-Log 'DRYRUN' '计划执行：注册 cpolar authtoken'
        return $true
    }

    # authtoken 通过官方命令写入，比直接改 yml 更稳妥
    if ($Token) {
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
        [Parameter(Mandatory = $true)][string]$DefaultTunnel
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
    if (-not $Values.TunnelNames -or $Values.TunnelNames.Count -eq 0) {
        $default = if ($Existing -and $Existing.selectedTunnelNames) {
            $Existing.selectedTunnelNames -join ','
        } else { $DefaultTunnel }

        if ($Silent) {
            $Values.TunnelNames = @($default)
        } else {
            if ($default) {
                Write-Host "  当前值：$default" -ForegroundColor Gray
            }
            $prompt = '要监控的隧道名，多个用逗号分隔'
            if ($default) { $prompt += '（回车保留当前值）' }
            $input = Read-Host $prompt
            $Values.TunnelNames = if ($input) {
                @($input -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            } else { @($default) }
        }
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

    $tunnelsJson = ($Values.TunnelNames | ForEach-Object { ConvertTo-JsonEscapedString $_ }) -join ', '

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

# ============================================================
# Function: Show-FinalChecklist — 输出收尾引导与人工检查清单
# Openlist 的存储挂载依赖其自身数据库，跨版本格式不稳，因此这里
# 只做引导与校验，不自动写入，避免产生易碎的强耦合逻辑。
# ============================================================
function Show-FinalChecklist {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string[]]$Tunnels,
        [Parameter(Mandatory = $true)][string]$PrimaryConfigPath
    )

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ' 部署完成 — 还需你手动完成最后一步' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "1. 浏览器打开 http://localhost:$Port 登录 Openlist" -ForegroundColor White
    Write-Host '   （账号固定为 admin，密码为部署时设置的 Openlist 登录密码；若未设置则在首次启动日志中查看）' -ForegroundColor Gray
    Write-Host '2. 进入「存储」→「添加」，挂载你的本地目录或网盘' -ForegroundColor White
    Write-Host '3. 回到 Cpolar Web（http://localhost:9200）确认以下隧道已在线：' -ForegroundColor White
    foreach ($t in $Tunnels) { Write-Host "   - $t" -ForegroundColor Gray }
    Write-Host ''
    Write-Host "配置文件位置：$PrimaryConfigPath" -ForegroundColor Gray
    Write-Host '后续修改配置后无需重装，Guard 会在下一个轮询周期自动热加载。' -ForegroundColor Gray

    if ($NoBrowser -or $DryRun) {
        Write-Log 'DRYRUN' "计划打开浏览器：http://localhost:$Port"
        return
    }

    Start-Process "http://localhost:$Port" -ErrorAction SilentlyContinue
}

# ============================================================
# 主流程
# ============================================================

# 不清屏，直接在当前命令行输出
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ' OpenCpolarSync 一键部署向导' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
if ($DryRun) {
    Write-Host ' 演练模式：不会安装、注册或写入任何内容' -ForegroundColor Magenta
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
    $argList += '-NoElevate'

    Start-Process 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait
    exit 0
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

$defaultTunnel = 'OpenListHC'
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
} else {
    [void](Set-CpolarTunnel -Tunnels $values.TunnelNames -Port $OpenlistPort -TunnelRegion $Region -Token $AuthToken)
}

# --- 阶段 6：Watchdog 注册 ------------------------------------
Write-Stage -Number 6 -Title '守护与自启'
if ($SkipWatchdog) {
    Write-Log 'INFO' '已指定 -SkipWatchdog，跳过计划任务注册'
} else {
    [void](Register-WatchdogTasks -ManagerPath $managerPath)
}

# --- 收尾引导 -------------------------------------------------
Show-FinalChecklist -Port $OpenlistPort -Tunnels $values.TunnelNames -PrimaryConfigPath $primaryConfig

Write-Host ''
Write-Log 'OK' '全部阶段执行完毕'
