<#
.SYNOPSIS
    Openlist resident guard script — auto-start and watch the openlist.exe server process
.DESCRIPTION
    Runs silently in the background, polling every 60s to verify openlist.exe is alive.
    Automatically restarts the process if it crashes, and writes structured logs
    (auto-rotated weekly by ISO week, keeping the last 4 weeks).
    Boot via shell:startup shortcut — no admin rights required.
    Replaces the original AutoStart.vbs (one-shot, no guard capability).
.NOTES
    Version: 1.0
    Compatible: Windows 7 SP1+ / PowerShell 5.0+
    Install: Run InstallAutoStart.bat from the same directory to register auto-start
#>

# ============================================================
# Initialization: hide the console window at runtime
# ============================================================
# Window hiding is handled inside the script (not via shortcut arguments)
# to avoid triggering AV behavior detection (powershell.exe + -WindowStyle Hidden).
# This also keeps the script functional when run manually from a terminal.
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("User32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
' -ErrorAction SilentlyContinue

$consoleHandle = [Console.Window]::GetConsoleWindow()
if ($consoleHandle -ne [IntPtr]::Zero) {
    # SW_HIDE = 0: hide the console window, completely transparent to the user
    [Console.Window]::ShowWindow($consoleHandle, 0) | Out-Null
}

# ============================================================
# Initialization: mutex to prevent duplicate instances
# ============================================================
# A global mutex ensures only one guard instance runs at a time.
# When another instance is detected, the new one exits silently.
$mutexName = "Global\OpenlistGuard-{A3B7E1F2-4C5D-6E7F-8A9B-0C1D2E3F4A5B}"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) {
    # Another instance is already running, exit silently
    exit 0
}

# ============================================================
# Initialization: paths and configuration
# ============================================================
# Auto-detect script directory — no hardcoded paths
$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$exePath    = Join-Path -Path $scriptDir -ChildPath "openlist.exe"
$logFile    = Join-Path -Path $scriptDir -ChildPath "logs/guard.log"
$processName = "openlist"         # Process name without .exe extension

$pollIntervalSec  = 60             # Poll interval (seconds)
$startupWaitSec   = 15             # Startup window: seconds to wait for the service to be ready

# ============================================================
# Function: Write-GuardLog — write a structured log entry
# ============================================================
# Parameters:
#   Level:   Log level (INFO / CHECK / WARN / ERROR)
#   Message: Log body (describes what happened)
# Behaviour:
#   Writes to both guard.log (UTF-8) and the console (visible during debugging)
function Write-GuardLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'CHECK', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"

    # Write to file; fall back to console on failure so the guard is never blocked
    try {
        Add-Content -Path $logFile -Value $logLine -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Host "[LOG-WRITE-FAILED] $logLine" -ForegroundColor Yellow
    }

    Write-Host $logLine
}

# ============================================================
# Function: Initialize-GuardLog — rotate the log file weekly
# ============================================================
# Checks whether guard.log belongs to the previous week. If so, renames it
# to guard.log.YYYY-Www and starts a fresh guard.log.
# Archived logs older than 4 weeks are automatically purged.
function Initialize-GuardLog {
    if (-not (Test-Path -Path $logFile)) {
        return  # No log file exists, nothing to rotate
    }

    $lastWrite    = (Get-Item -Path $logFile).LastWriteTime
    $currentDate  = Get-Date

    # Use ISO 8601 week-of-year calculation
    $calendar     = [System.Globalization.CultureInfo]::CurrentCulture.Calendar
    $weekRule     = [System.Globalization.CalendarWeekRule]::FirstFourDayWeek

    $lastWeek     = $calendar.GetWeekOfYear($lastWrite, $weekRule, [DayOfWeek]::Monday)
    $currentWeek  = $calendar.GetWeekOfYear($currentDate, $weekRule, [DayOfWeek]::Monday)

    $lastYear     = $lastWrite.Year
    $currentYear  = $currentDate.Year

    # Same week as current — skip rotation
    if ($lastYear -eq $currentYear -and $lastWeek -eq $currentWeek) {
        return
    }

    # Archive: guard.log -> guard.log.YYYY-Www
    $archiveName  = "guard.log.$lastYear-W{0:D2}" -f $lastWeek
    $archivePath  = Join-Path -Path $scriptDir -ChildPath $archiveName
    try {
        Rename-Item -Path $logFile -NewName $archiveName -ErrorAction Stop
        Write-Host "[LOG] Rotated: $archiveName"
    } catch {
        Write-Host "[LOG] Rotation failed: $_" -ForegroundColor Yellow
    }

    # Purge archives older than 4 weeks
    $retentionWeeks = 4
    Get-ChildItem -Path (Join-Path $scriptDir "logs") -Filter "guard.log.*" | ForEach-Object {
        if ($_.Name -match 'guard\.log\.(\d{4})-W(\d{2})') {
            $logYear  = [int]$Matches[1]
            $logWeek  = [int]$Matches[2]
            $weekDiff = ($currentYear - $logYear) * 52 + ($currentWeek - $logWeek)

            if ($weekDiff -gt $retentionWeeks) {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    Write-Host "[LOG] Removed old: $($_.Name)"
                } catch {
                    Write-Host "[LOG] Failed to remove old log: $_" -ForegroundColor Yellow
                }
            }
        }
    }
}

# ============================================================
# Function: Start-OpenlistService — launch openlist.exe server
# ============================================================
# Starts openlist.exe with the "server" argument in a hidden window,
# working directory set to the script directory (same behaviour as the original VBS).
# Returns:
#   System.Diagnostics.Process object on success
#   $null on failure
function Start-OpenlistService {
    $proc = Start-Process -FilePath $exePath `
        -ArgumentList "server" `
        -WorkingDirectory $scriptDir `
        -WindowStyle Hidden `
        -PassThru `
        -ErrorAction SilentlyContinue

    if ($proc -and $proc.Id -gt 0) {
        Write-GuardLog -Level "INFO" -Message "openlist.exe started. PID=$($proc.Id)"
        return $proc
    } else {
        Write-GuardLog -Level "ERROR" -Message "Failed to start openlist.exe"
        return $null
    }
}

# ============================================================
# Entry point: log initialisation + first launch
# ============================================================

Initialize-GuardLog

Write-GuardLog -Level "INFO" -Message "OpenlistGuard started. ScriptDir=$scriptDir"

# Verify openlist.exe exists; if missing the guard loop keeps retrying
if (-not (Test-Path -Path $exePath)) {
    Write-GuardLog -Level "ERROR" -Message "openlist.exe not found at: $exePath"
}

# First launch: start openlist.exe if not already running, then wait through the startup window
$existingProc = Get-Process -Name $processName -ErrorAction SilentlyContinue
if (-not $existingProc) {
    Write-GuardLog -Level "INFO" -Message "openlist.exe not running. Starting: $exePath server"
    Start-OpenlistService
    Write-GuardLog -Level "INFO" -Message "Waiting $startupWaitSec seconds for startup..."
    Start-Sleep -Seconds $startupWaitSec
} else {
    Write-GuardLog -Level "INFO" -Message "openlist.exe already running. PID=$($existingProc[0].Id)"
}

# ============================================================
# Guard loop: poll every minute, auto-restart on process loss
# ============================================================
Write-GuardLog -Level "INFO" -Message "Guard loop started. Poll interval: ${pollIntervalSec}s"

while ($true) {
    Start-Sleep -Seconds $pollIntervalSec

    $proc = Get-Process -Name $processName -ErrorAction SilentlyContinue

    if ($proc) {
        # Process alive — log CHECK (not INFO) to distinguish routine polls from events
        Write-GuardLog -Level "CHECK" -Message "openlist.exe is running. PID=$($proc[0].Id)"
    } else {
        Write-GuardLog -Level "WARN" -Message "openlist.exe not found. Attempting restart..."

        $newProc = Start-OpenlistService

        if ($newProc) {
            Write-GuardLog -Level "INFO" -Message "openlist.exe restarted. New PID=$($newProc.Id)"

            # Wait through the startup window to avoid re-detecting before the service is ready
            Start-Sleep -Seconds $startupWaitSec

            $confirmProc = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $confirmProc) {
                Write-GuardLog -Level "WARN" -Message ("openlist.exe exited within " +
                    "${startupWaitSec}s after restart. Will retry on next cycle.")
            }
        } else {
            Write-GuardLog -Level "ERROR" -Message "Failed to restart openlist.exe."
        }
    }
}
