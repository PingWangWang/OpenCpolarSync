<#
.SYNOPSIS
    OpenCpolarSync Watchdog — per-cycle health-check + auto-restart worker
.DESCRIPTION
    Invoked by Windows Task Scheduler at a fixed interval (default 5 min).
    Uses the same Global\ named Mutex as the target guard script to decide
    whether the guard is alive.  If the guard process has terminated
    abnormally the Mutex is abandoned and this script acquires it — it
    then re-launches the guard script and writes a restart event to the
    watchdog log.
    A single parameterised script serves both CpolarGuard and OpenlistGuard.
.PARAMETER GuardName
    Human-readable label used in log messages, e.g. "Cpolar" or "Openlist".
.PARAMETER MutexName
    Full Global\ mutex name, must match the one created by the guard script.
.PARAMETER GuardScriptPath
    Absolute path to the guard *.ps1 file that should be re-launched.
.PARAMETER LogPath
    Absolute path to the watchdog log file.
.NOTES
    Version: 1.0
    Compatible: Windows 7 SP1+ / PowerShell 5.0+
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$GuardName,

    [Parameter(Mandatory = $true)]
    [string]$MutexName,

    [Parameter(Mandatory = $true)]
    [string]$GuardScriptPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

# ============================================================
# Function: Write-WatchdogLog — append a timestamped line
# ============================================================
function Write-WatchdogLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'RESTART', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"

    try {
        $logDir = Split-Path -Parent $LogPath
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $LogPath -Value $logLine -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Best-effort: silently continue — the scheduler won't show console
    }
}

# ============================================================
# Function: Find-GuardProcess — 找出「以该 Guard 脚本为入口」的进程 PID
#
# 【必须要求 -File 与路径相邻，不能只看路径是否出现在命令行里】
# 计划任务给本脚本传的参数里带着 `-GuardScriptPath "<Guard 完整路径>"`，因此
# 本脚本**自己的**命令行就含有该路径。宽松匹配（-like "*路径*"）会把本脚本
# 自己当成 Guard —— 后果是永远判定「Guard 已存在、跳过拉起」，Guard 从此再也
# 不会被启动（现象：guard.log 根本不存在，watchdog.log 里却每 tick 都报一个
# 不断变化的「已存在 (PID=…)」，那其实是本脚本自己的 PID）。
# 所以这里要求 `-File` 直接跟着该脚本的完整路径，并显式排除自身 PID。
# 宁可漏检（多起一个会在 Mutex 处自行退出的 Guard）也不误判为「已存在」。
# ============================================================
function Find-GuardProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GuardPath
    )

    $pattern = '-File\s+"?' + [regex]::Escape($GuardPath) + '"?(\s|$)'

    try {
        $procs = Get-CimInstance Win32_Process `
            -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop
    } catch {
        # 拿不到 CIM（权限/精简系统）时返回 $null，退化为仅用 Mutex 判断，不阻断保活
        return $null
    }

    foreach ($p in @($procs)) {
        if ([int]$p.ProcessId -eq $PID) { continue }
        if ("$($p.CommandLine)" -match $pattern) {
            return [int]$p.ProcessId
        }
    }

    return $null
}

# ============================================================
# Main: try to acquire the guard's Mutex
# ============================================================

Write-WatchdogLog -Level "INFO" -Message "Watchdog tick for $GuardName"

$mutex = $null
$createdNew = $false

try {
    # Create-or-open the named mutex.  $createdNew = $true means NO other
    # process currently holds it → the guard has died.
    $mutex = New-Object System.Threading.Mutex($false, $MutexName, [ref]$createdNew)

    if ($createdNew) {
        # Mutex 显示 Guard 不在，但「创建 Mutex → 拉起 Guard」之间存在竞态窗口：
        # Guard 进程已经起来、还没来得及 WaitOne 时，下一次 tick 同样会看到
        # createdNew=$true，于是又拉起一个 —— 结果就是多个 Guard 实例。这里再加
        # 一道进程级检查兜住它：确实以该 Guard 脚本为入口启动的进程已存在就不拉。
        # （匹配规则与「为什么不能用宽松匹配」见上方 Find-GuardProcess 的注释。）
        $existingGuardPid = Find-GuardProcess -GuardPath $GuardScriptPath

        if ($existingGuardPid) {
            Write-WatchdogLog -Level "INFO" -Message "$GuardName Guard 进程已存在 (PID=$existingGuardPid)，跳过拉起"
        } else {
            # Guard is NOT running — attempt restart
            Write-WatchdogLog -Level "RESTART" -Message "$GuardName Guard 不在运行，正在尝试拉起..."

            # 用绝对路径，避免 S4U 非交互会话里 PATH 不含 WindowsPowerShell\v1.0
            $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if (-not (Test-Path $psExe)) { $psExe = 'powershell.exe' }

            $proc = Start-Process -FilePath $psExe `
                -ArgumentList "-ExecutionPolicy Bypass -File `"$GuardScriptPath`"" `
                -WindowStyle Hidden `
                -PassThru `
                -ErrorAction SilentlyContinue

            if (-not $proc -or $proc.Id -le 0) {
                Write-WatchdogLog -Level "ERROR" -Message "$GuardName Guard 拉起失败（Start-Process 未返回进程）"
            } else {
                # 【为什么必须回头确认一次】Start-Process 返回 PID 只说明「进程创建
                # 成功」，不代表 Guard 活下来了：抢不到 Mutex、脚本自身报错，都会在
                # 毫秒级退出。只看 Start-Process 就写「已拉起」会留下一条骗人的日志
                # —— 本项目正是被这种「假成功日志」误导过整整一轮排查。
                Start-Sleep -Seconds 3
                $stillAlive = $null -ne (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)

                if ($stillAlive) {
                    Write-WatchdogLog -Level "RESTART" -Message "$GuardName Guard 已拉起 (PID=$($proc.Id))"
                } else {
                    # 刚起来就退出，两种可能：另一实例抢到了 Mutex（正常竞态），
                    # 或者 Guard 真的起不来（需要看 Guard 自己的日志）。
                    $nowGuardPid = Find-GuardProcess -GuardPath $GuardScriptPath
                    if ($nowGuardPid) {
                        Write-WatchdogLog -Level "INFO" -Message "$GuardName 新实例 (PID=$($proc.Id)) 已退出，但已有 Guard (PID=$nowGuardPid) 在运行，无需处理"
                    } else {
                        $guardLogHint = Join-Path (Split-Path -Parent $GuardScriptPath) 'logs\guard.log'
                        Write-WatchdogLog -Level "ERROR" -Message "$GuardName Guard 拉起后 3 秒内即退出，且无 Guard 在运行 —— 请查看 $guardLogHint"
                    }
                }
            }
        }
    } else {
        # Guard is alive — nothing to do
        # Do NOT write a log line here to avoid noise (every tick would log)
    }
} catch {
    Write-WatchdogLog -Level "ERROR" -Message "Mutex 检测异常: $_"
} finally {
    if ($mutex) {
        $mutex.Dispose()
    }
}
