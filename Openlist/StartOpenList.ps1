# Wait 15 seconds for network and system services to be ready
Start-Sleep -Seconds 15

$workDir = $PSScriptRoot
$exePath = Join-Path $workDir "openlist.exe"
$log = Join-Path $workDir "start_log.txt"

# Function to append log messages (UTF-8 with BOM)
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] $Message"
    [System.IO.File]::AppendAllText($log, $line + "`r`n", [System.Text.Encoding]::UTF8)
}

Write-Log "Script started, working directory: $workDir"

if (-not (Test-Path $exePath)) {
    Write-Log "ERROR: openlist.exe not found"
    exit 1
}

# Start openlist.exe with 'server' argument
$arguments = "server"
$proc = Start-Process -FilePath $exePath -ArgumentList $arguments -WorkingDirectory $workDir -PassThru -WindowStyle Hidden

# Wait 2 seconds to check if process exits immediately (crash)
if (-not $proc.WaitForExit(2000)) {
    Write-Log "openlist started successfully, PID=$($proc.Id)"
} else {
    $exitCode = $proc.ExitCode
    Write-Log "openlist exited immediately with exit code: $exitCode"
    Write-Log "Suggestion: manually run '$exePath server' in CMD to see detailed error"
}

exit 0