param(
    [string]$Tag = "v1.1.14"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stage = Join-Path $env:TEMP ("ocx_pkg_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage | Out-Null

Copy-Item "$root\setup.ps1" $stage
Copy-Item "$root\bootstrap.ps1" $stage
Copy-Item "$root\bootstrap-core.ps1" $stage

New-Item -ItemType Directory -Force -Path `
    "$stage\Cpolar\installer", "$stage\Cpolar\config", `
    "$stage\Openlist\archive", "$stage\Watchdog" | Out-Null

Copy-Item "$root\Cpolar\installer\cpolar_amd64.msi" "$stage\Cpolar\installer\"
Copy-Item "$root\Cpolar\config\config.json" "$stage\Cpolar\config\"
Copy-Item "$root\Openlist\archive\openlist.zip" "$stage\Openlist\archive\"
Copy-Item "$root\Watchdog\WatchdogManager.bat" "$stage\Watchdog\"

$zip = Join-Path $env:TEMP ("OpenCpolarSync_" + $Tag + ".zip")
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$stage\*" -DestinationPath $zip -CompressionLevel Optimal -Force

$len = (Get-Item $zip).Length
Write-Output "发布包: $zip  $([math]::Round($len / 1MB, 2))MB"
