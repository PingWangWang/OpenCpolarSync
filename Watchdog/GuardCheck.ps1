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
        # 一道进程级检查兜住它：命令行里带该 Guard 脚本路径的进程已存在就不拉。
        $existingGuardPid = $null
        try {
            $procs = Get-CimInstance Win32_Process `
                -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop
            foreach ($p in @($procs)) {
                if ("$($p.CommandLine)" -like "*$GuardScriptPath*") {
                    $existingGuardPid = [int]$p.ProcessId
                    break
                }
            }
        } catch {
            # 拿不到 CIM（权限/精简系统）时退化为仅用 Mutex 判断，不阻断保活
        }

        if ($existingGuardPid) {
            Write-WatchdogLog -Level "INFO" -Message "$GuardName Guard 进程已存在 (PID=$existingGuardPid)，跳过拉起"
        } else {
            # Guard is NOT running — attempt restart
            Write-WatchdogLog -Level "RESTART" -Message "$GuardName Guard 不在运行，正在尝试拉起..."

            $proc = Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-ExecutionPolicy Bypass -File `"$GuardScriptPath`"" `
                -WindowStyle Hidden `
                -PassThru `
                -ErrorAction SilentlyContinue

            if ($proc -and $proc.Id -gt 0) {
                Write-WatchdogLog -Level "RESTART" -Message "$GuardName Guard 已拉起 (PID=$($proc.Id))"
            } else {
                Write-WatchdogLog -Level "ERROR" -Message "$GuardName Guard 拉起失败"
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
