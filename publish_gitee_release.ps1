# publish_gitee_release.ps1
# Publish OpenCpolarSync release to Gitee (pure-Gitee single source).
# Creates/updates Release <Tag> on gitee.com/<Owner>/<Repo> and uploads assets:
#   bootstrap.ps1, bootstrap-core.ps1, and the built OpenCpolarSync_<Tag>.zip
# Token: pass via -Token, env GITEE_TOKEN, or -TokenFile. Treat token as password:
#   never commit it, never paste it in logs. Delete the token file after use.

param(
    [string]$Token,
    [string]$TokenFile,
    [string]$Owner = 'pingwang1994',
    [string]$Repo  = 'OpenCpolarSync',
    [string]$Tag   = 'v1.1.15',
    [string]$TargetCommitish = 'main',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- resolve token ---
if (-not $Token) {
    if ($env:GITEE_TOKEN) { $Token = $env:GITEE_TOKEN }
    elseif ($TokenFile -and (Test-Path $TokenFile)) { $Token = (Get-Content $TokenFile -Raw).Trim() }
}
if (-not $Token) { throw 'No Gitee token provided. Use -Token, $env:GITEE_TOKEN, or -TokenFile.' }

$apiBase = "https://gitee.com/api/v5/repos/$Owner/$Repo"
$headers = @{ Authorization = "token $Token" }

if ($DryRun) {
    Write-Output "[DryRun] Would create/reuse Release $Tag on $apiBase and upload 3 assets."
    exit 0
}

# --- build release zip (optional: continue with ps1 assets if build fails) ---
$zip = Join-Path $env:TEMP ("OpenCpolarSync_" + $Tag + ".zip")
try {
    Write-Output "Building release zip..."
    & "$PSScriptRoot\build_release_zip.ps1" -Tag $Tag | Out-Null
    Write-Output ("Built: $zip")
} catch {
    Write-Warning ("Release zip build failed (continuing with ps1 assets only): $($_.Exception.Message)")
}

# --- create or reuse release ---
# NOTE: Gitee returns HTTP 200 with body "null" (not 404) for a missing tag,
# so we must explicitly test the returned object/id instead of relying on an exception.
$releaseId = $null
try { $existing = Invoke-RestMethod -Uri "$apiBase/releases/tags/$Tag" -Headers $headers -TimeoutSec 20 } catch { $existing = $null }

if ($existing -and $existing.id) {
    $releaseId = $existing.id
    Write-Output ("Reusing existing Release id=$releaseId (tag $Tag)")
} else {
    # target_commitish is REQUIRED when the tag does not yet exist, else Gitee returns 400 Bad Request.
    $body = @{ tag_name = $Tag; name = $Tag; target_commitish = $TargetCommitish; body = "OpenCpolarSync $Tag (Gitee primary source)"; prerelease = $false } | ConvertTo-Json -Compress
    $rel = Invoke-RestMethod -Uri "$apiBase/releases" -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 20
    $releaseId = $rel.id
    Write-Output ("Created Release id=$releaseId (tag $Tag)")
}

# --- upload assets (dedupe by name) ---
$files = @(
    (Join-Path $PSScriptRoot 'bootstrap.ps1'),
    (Join-Path $PSScriptRoot 'bootstrap-core.ps1'),
    $zip
)
$cli = New-Object System.Net.Http.HttpClient
$cli.Timeout = [TimeSpan]::FromMinutes(10)
$cli.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('token', $Token)

# list existing assets for dedupe
$existingAssets = @()
try { $existingAssets = @(Invoke-RestMethod -Uri "$apiBase/releases/$releaseId" -Headers $headers -TimeoutSec 20).assets } catch { }

foreach ($f in $files) {
    if (-not (Test-Path $f)) { Write-Warning "Skip missing file: $f"; continue }
    $name = [System.IO.Path]::GetFileName($f)
    # delete existing asset with same name so re-runs are idempotent
    $dup = $existingAssets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($dup) {
        Invoke-RestMethod -Uri "$apiBase/releases/$releaseId/attach_files/$($dup.id)" -Method Delete -Headers $headers -TimeoutSec 20 | Out-Null
        Write-Output ("Removed existing asset: $name")
    }
    $bytes = [System.IO.File]::ReadAllBytes($f)
    # Use ::new() (not New-Object) so a byte[] is passed as ONE arg, not splatted into N args.
    $mp = [System.Net.Http.MultipartFormDataContent]::new()
    $bc = [System.Net.Http.ByteArrayContent]::new($bytes)
    $bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
    $mp.Add($bc, 'file', $name)
    $resp = $cli.PostAsync("$apiBase/releases/$releaseId/attach_files", $mp).GetAwaiter().GetResult()
    if ($resp.IsSuccessStatusCode) { Write-Output ("Uploaded asset: $name") }
    else {
        $txt = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        throw ("Upload failed for $name : $($resp.StatusCode) $txt")
    }
    $mp.Dispose()
}
$cli.Dispose()
Write-Output "Done. Release $Tag published with assets on Gitee."
