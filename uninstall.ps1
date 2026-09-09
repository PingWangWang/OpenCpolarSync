<#
.SYNOPSIS
    OpenCpolarSync 一键卸载脚本。
.DESCRIPTION
    移除通过 bootstrap.ps1 / setup.ps1 部署的全部组件：
      1. 停止 Cpolar / Openlist 进程及 Guard 守护进程
      2. 调用 WatchdogManager.bat teardown all 移除计划任务
      3. 删除程序目录 %LOCALAPPDATA%\OpenCpolarSync\app
      4. 可选：删除配置目录 %LOCALAPPDATA%\OpenCpolarSync\config
      5. 可选：删除 Cpolar 隧道配置 %USERPROFILE%\.cpolar\cpolar.yml
      6. 可选：卸载 Cpolar 客户端（仅当通过本工具安装时）
.PARAMETER Silent
    非交互模式，全部使用默认行为（保留配置、不卸载 Cpolar）。
.PARAMETER RemoveConfig
    非交互模式下删除配置目录。
.PARAMETER RemoveCpolar
    非交互模式下卸载 Cpolar 客户端。
.PARAMETER InstallDir
    安装根目录，默认 %LOCALAPPDATA%\OpenCpolarSync。
.EXAMPLE
    .\uninstall.ps1
    交互式卸载。
.NOTES
    Version: 1.0
    Compatible: Windows 7 SP1+ / PowerShell 5.0+
#>

param(
    [switch]$Silent,
    [switch]$RemoveConfig,
    [switch]$RemoveCpolar,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

# UTF-8 输出编码保护
try {
    if ($PSVersionTable.PSVersion.Major -ge 6 -or [Console]::OutputEncoding.CodePage -eq 65001) {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
    }
} catch { }

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('INFO', 'STEP', 'OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message
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

function Confirm-Action {
    param([Parameter(Mandatory = $true)][string]$Message, [bool]$Default = $false)
    if ($Silent) { return $Default }
    $defaultChar = if ($Default) { 'Y' } else { 'N' }
    $choice = Read-Host "$Message (Y/N) [$defaultChar]"
    if ([string]::IsNullOrWhiteSpace($choice)) { return $Default }
    return $choice -match '^[Yy]'
}

# ============================================================
# 主流程
# ============================================================
# 不清屏，直接在当前命令行输出
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ' OpenCpolarSync 卸载向导' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan

if (-not $InstallDir) {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'OpenCpolarSync'
}
$appDir    = Join-Path $InstallDir 'app'
$configDir = Join-Path $InstallDir 'config'

Write-Log 'INFO' "程序目录：$appDir"
Write-Log 'INFO' "配置目录：$configDir"

# 检测是否已安装
if (-not (Test-Path $appDir)) {
    Write-Log 'WARN' "未检测到 OpenCpolarSync 安装（$appDir 不存在）"
    if (-not (Confirm-Action -Message '是否继续清理可能的残留项')) {
        Write-Host '已取消卸载。' -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ''

# --- 阶段 1：停止进程 ---------------------------------------------------------
Write-Host '--- 阶段 1：停止运行中的进程 ---' -ForegroundColor Cyan

$processes = @('openlist', 'cpolar', 'powershell')
$stopped = @()
foreach ($procName in $processes) {
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        # 只停止与 OpenCpolarSync 相关的 powershell（Guard 脚本）
        if ($procName -eq 'powershell') {
            $cmdLine = $null
            try {
                $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).CommandLine
            } catch { }
            if ($cmdLine -and ($cmdLine -match 'CpolarGuard|OpenlistGuard|GuardCheck')) {
                Write-Log 'STEP' "停止守护进程：$($p.ProcessName) (PID=$($p.Id))"
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                $stopped += $p.Id
            }
        } else {
            Write-Log 'STEP' "停止进程：$($p.ProcessName) (PID=$($p.Id))"
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $stopped += $p.Id
        }
    }
}
if ($stopped.Count -gt 0) {
    Write-Log 'OK' "已停止 $($stopped.Count) 个进程，等待文件句柄释放..."
    # 等待进程完全退出并释放文件句柄，最多等 15 秒
    for ($i = 0; $i -lt 15; $i++) {
        $stillRunning = $false
        foreach ($procName in @('openlist', 'cpolar')) {
            if (Get-Process -Name $procName -ErrorAction SilentlyContinue) { $stillRunning = $true; break }
        }
        if (-not $stillRunning) { break }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 2
} else {
    Write-Log 'OK' '没有运行中的相关进程'
}

# --- 阶段 2：移除 Watchdog 计划任务 -------------------------------------------
Write-Host ''
Write-Host '--- 阶段 2：移除 Watchdog 计划任务 ---' -ForegroundColor Cyan

$watchdogMgr = Join-Path $appDir 'Watchdog\WatchdogManager.bat'
if (Test-Path $watchdogMgr) {
    Write-Log 'STEP' '调用 WatchdogManager.bat teardown all'
    try {
        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$watchdogMgr`" teardown all" -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -eq 0) {
            Write-Log 'OK' 'Watchdog 计划任务已移除'
        } else {
            Write-Log 'WARN' "WatchdogManager 返回退出码 $($proc.ExitCode)，尝试直接删除计划任务"
        }
    } catch {
        Write-Log 'WARN' "WatchdogManager 执行失败：$($_.Exception.Message)"
    }
}

# 兜底：直接删除已知的计划任务
$taskNames = @('OpenCpolarSync_CpolarGuard_Watchdog', 'OpenCpolarSync_OpenlistGuard_Watchdog')
foreach ($taskName in $taskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Log 'STEP' "删除计划任务：$taskName"
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log 'OK' "已删除：$taskName"
    }
}

# 清理旧版开机自启（如果存在）
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (Test-Path $runKey) {
    $runVal = Get-ItemProperty -Path $runKey -Name 'OpenCpolarSync' -ErrorAction SilentlyContinue
    if ($runVal) {
        Write-Log 'STEP' '移除开机自启动项'
        Remove-ItemProperty -Path $runKey -Name 'OpenCpolarSync' -Force -ErrorAction SilentlyContinue
        Write-Log 'OK' '已移除开机自启动项'
    }
}

# --- 阶段 3：删除程序目录 -----------------------------------------------------
Write-Host ''
Write-Host '--- 阶段 3：删除程序文件 ---' -ForegroundColor Cyan

if (Test-Path $appDir) {
    Write-Log 'STEP' "删除程序目录：$appDir"
    # 重试 3 次，每次间隔 3 秒，应对文件句柄延迟释放
    $deleted = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            # 先尝试逐个删除文件，遇到被占用的文件跳过，避免整体失败
            Get-ChildItem -Path $appDir -Recurse -Force -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object {
                    try { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop }
                    catch { }
                }
            Remove-Item -Path $appDir -Recurse -Force -ErrorAction Stop
            $deleted = $true
            break
        } catch {
            if ($attempt -lt 3) {
                Write-Log 'WARN' "第 $attempt 次删除失败，3 秒后重试：$($_.Exception.Message)"
                Start-Sleep -Seconds 3
            } else {
                Write-Log 'ERROR' "删除程序目录失败（已重试 3 次）：$($_.Exception.Message)"
            }
        }
    }
    if ($deleted) {
        Write-Log 'OK' '程序目录已删除'
    } else {
        Write-Host '  仍有文件被占用，重启电脑后可手动删除该目录。' -ForegroundColor Yellow
    }
} else {
    Write-Log 'INFO' '程序目录不存在，跳过'
}

# --- 阶段 4：配置目录（可选） -------------------------------------------------
Write-Host ''
Write-Host '--- 阶段 4：配置文件 ---' -ForegroundColor Cyan

$doRemoveConfig = if ($Silent) { $RemoveConfig.IsPresent } else { Confirm-Action -Message '是否删除配置文件（config.json、钉钉Webhook、密码等）' -Default $false }

if ($doRemoveConfig) {
    if (Test-Path $configDir) {
        Write-Log 'STEP' "删除配置目录：$configDir"
        Remove-Item -Path $configDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log 'OK' '配置目录已删除'
    }
    # 删除 Cpolar 隧道配置
    $cpolarYml = Join-Path $env:USERPROFILE '.cpolar\cpolar.yml'
    if (Test-Path $cpolarYml) {
        Write-Log 'STEP' "删除 Cpolar 隧道配置：$cpolarYml"
        Remove-Item -Path $cpolarYml -Force -ErrorAction SilentlyContinue
        Write-Log 'OK' 'Cpolar 隧道配置已删除'
    }
} else {
    Write-Log 'INFO' "配置目录已保留：$configDir"
}

# --- 阶段 5：卸载 Cpolar（可选） ----------------------------------------------
Write-Host ''
Write-Host '--- 阶段 5：Cpolar 客户端 ---' -ForegroundColor Cyan

$cpolarInstalled = $false
try {
    $cpolarKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*cpolar*' } | Select-Object -First 1
    if ($cpolarKey) { $cpolarInstalled = $true }
} catch { }

if ($cpolarInstalled) {
    $doRemoveCpolar = if ($Silent) { $RemoveCpolar.IsPresent } else { Confirm-Action -Message '是否同时卸载 Cpolar 客户端' -Default $false }
    if ($doRemoveCpolar) {
        Write-Log 'STEP' '卸载 Cpolar 客户端'
        try {
            $uninstallString = $cpolarKey.UninstallString
            if ($uninstallString) {
                if ($uninstallString -match 'msiexec') {
                    $productCode = [regex]::Match($uninstallString, '\{[^}]+\}').Value
                    if ($productCode) {
                        Start-Process 'msiexec.exe' -ArgumentList "/x $productCode /qn /norestart" -Wait
                        Write-Log 'OK' 'Cpolar 客户端已卸载'
                    }
                } else {
                    Start-Process $uninstallString -Wait
                    Write-Log 'OK' 'Cpolar 卸载程序已执行'
                }
            }
        } catch {
            Write-Log 'ERROR' "卸载 Cpolar 失败：$($_.Exception.Message)"
        }
    } else {
        Write-Log 'INFO' 'Cpolar 客户端已保留'
    }
} else {
    Write-Log 'INFO' '未检测到 Cpolar 客户端安装'
}

# --- 完成 ---------------------------------------------------------------------
Write-Host ''
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host ' 卸载完成' -ForegroundColor Green
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host "  程序目录：$appDir $(if (Test-Path $appDir) { '(仍存在，可能有文件被占用)' } else { '(已删除)' })"
Write-Host "  配置目录：$configDir $(if (Test-Path $configDir) { '(已保留)' } else { '(已删除)' })"
Write-Host ''
Write-Host '  如有残留文件被占用，重启电脑后可手动删除上述目录。' -ForegroundColor Gray

if (-not $Silent) {
    Write-Host ''
    Read-Host '按回车键退出' | Out-Null
}
