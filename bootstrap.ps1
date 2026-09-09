# OpenCpolarSync bootstrap launcher.
# ASCII-only on purpose: Windows PowerShell 5.1 decodes HTTP text responses as
# Latin1/ANSI, so a UTF-8 script fetched via "irm <url> | iex" gets garbled.
# This launcher stays pure ASCII and re-launches everything in ONE elevated
# window, so the whole deployment (download + extract + setup wizard) runs in a
# single window instead of opening a second one later.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$coreName = 'bootstrap-core.ps1'
$coreUrl  = 'https://github.com/PingWangWang/OpenCpolarSync/releases/download/v1.1.14/' + $coreName

# Materialize the real script to a temp file so it can run in a new elevated process.
$coreFile = Join-Path $env:TEMP 'OpenCpolarSync-bootstrap-core.ps1'
$localCore = $null
if ($PSScriptRoot) { $localCore = Join-Path $PSScriptRoot $coreName }

if ($localCore -and (Test-Path $localCore)) {
    Copy-Item $localCore $coreFile -Force
} else {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'OpenCpolarSync-bootstrap')
    $bytes = $wc.DownloadData($coreUrl)
    [System.IO.File]::WriteAllBytes($coreFile, $bytes)
}

$isAdmin = $false
try {
    $wid = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal($wid)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

# -DryRun / -NoElevate are used for testing; they run in-place without elevation.
# -Uninstall triggers uninstall mode instead of install.
$noElevate = ($args -contains '-NoElevate') -or ($args -contains '-DryRun')

if ($isAdmin -or $noElevate) {
    & $coreFile @args
} else {
    Write-Host 'OpenCpolarSync: requesting administrator privileges; the whole deployment will continue in one elevated window...' -ForegroundColor Yellow
    $psExe = (Get-Process -Id $PID).Path
    $argList = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $coreFile + '"')) + $args
    Start-Process $psExe -Verb RunAs -ArgumentList $argList | Out-Null
}
