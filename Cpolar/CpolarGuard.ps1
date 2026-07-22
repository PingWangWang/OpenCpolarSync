<#
.SYNOPSIS
    Cpolar tunnel status guard script — poll Cpolar API and push changes via DingTalk webhook
.DESCRIPTION
    Runs as a resident background script, polling the Cpolar backend API
    (http://localhost:9200/api/v1/tunnels) at a configurable interval.
    Detects tunnel changes (added / updated / offline) and pushes Markdown
    notifications through a DingTalk robot webhook.
    Designed as a standalone alternative to the Tampermonkey userscript —
    no browser or extension required.
.NOTES
    Version: 1.0
    Compatible: Windows 7 SP1+ / PowerShell 5.0+
    API: Cpolar Web backend at localhost:9200 (JWT token auth)
#>

# ============================================================
# Initialization: hide the console window at runtime
# ============================================================
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("User32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
' -ErrorAction SilentlyContinue

$consoleHandle = [Console.Window]::GetConsoleWindow()
if ($consoleHandle -ne [IntPtr]::Zero) {
    [Console.Window]::ShowWindow($consoleHandle, 0) | Out-Null
}

# ============================================================
# Initialization: mutex to prevent duplicate instances
# ============================================================
$mutexName = "Global\CpolarGuard-{B4C8D2E3-5F6A-7B8C-9D0E-1F2A3B4C5D6E}"
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) {
    exit 0
}

# ============================================================
# Initialization: paths and configuration
# ============================================================
$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$configPath       = Join-Path -Path $scriptDir -ChildPath "config/config.json"
$sentCachePath    = Join-Path -Path $scriptDir -ChildPath "config/last-sent.json"
$logFile          = Join-Path -Path $scriptDir -ChildPath "logs/guard.log"
$pollIntervalSec  = 300              # Default 5 minutes, overridden by config
$apiTunnelsPath   = "/api/v1/tunnels"

# ============================================================
# Function: Write-GuardLog — write a structured log entry
# ============================================================
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

    try {
        Add-Content -Path $logFile -Value $logLine -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Host "[LOG-WRITE-FAILED] $logLine" -ForegroundColor Yellow
    }

    if ($Level -eq 'ERROR') {
        Write-Host $logLine -ForegroundColor Red
    } elseif ($Level -eq 'WARN') {
        Write-Host $logLine -ForegroundColor Yellow
    } else {
        Write-Host $logLine
    }
}

# ============================================================
# Function: Initialize-GuardLog — rotate the log file weekly
# ============================================================
function Initialize-GuardLog {
    if (-not (Test-Path -Path $logFile)) { return }

    $lastWrite    = (Get-Item -Path $logFile).LastWriteTime
    $currentDate  = Get-Date
    $calendar     = [System.Globalization.CultureInfo]::CurrentCulture.Calendar
    $weekRule     = [System.Globalization.CalendarWeekRule]::FirstFourDayWeek
    $lastWeek     = $calendar.GetWeekOfYear($lastWrite, $weekRule, [DayOfWeek]::Monday)
    $currentWeek  = $calendar.GetWeekOfYear($currentDate, $weekRule, [DayOfWeek]::Monday)
    $lastYear     = $lastWrite.Year
    $currentYear  = $currentDate.Year

    if ($lastYear -eq $currentYear -and $lastWeek -eq $currentWeek) { return }

    $archiveName  = "guard.log.$lastYear-W{0:D2}" -f $lastWeek
    $archivePath  = Join-Path -Path $scriptDir -ChildPath $archiveName
    try {
        Rename-Item -Path $logFile -NewName $archiveName -ErrorAction Stop
        Write-Host "[LOG] Rotated: $archiveName"
    } catch {
        Write-Host "[LOG] Rotation failed: $_" -ForegroundColor Yellow
    }

    $retentionWeeks = 4
    Get-ChildItem -Path (Join-Path $scriptDir "logs") -Filter "guard.log.*" | ForEach-Object {
        if ($_.Name -match 'guard\.log\.(\d{4})-W(\d{2})') {
            $logYear  = [int]$Matches[1]
            $logWeek  = [int]$Matches[2]
            $weekDiff = ($currentYear - $logYear) * 52 + ($currentWeek - $logWeek)
            if ($weekDiff -gt $retentionWeeks) {
                try { Remove-Item -Path $_.FullName -Force -ErrorAction Stop; Write-Host "[LOG] Removed old: $($_.Name)" }
                catch { Write-Host "[LOG] Failed to remove old log: $_" -ForegroundColor Yellow }
            }
        }
    }
}

# ============================================================
# Function: Read-Config — load and validate config.json
# ============================================================
function Read-Config {
    if (-not (Test-Path -Path $configPath)) {
        Write-GuardLog -Level "ERROR" -Message "config.json not found at: $configPath"
        return $null
    }

    try {
        $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-GuardLog -Level "ERROR" -Message "Failed to parse config.json: $_"
        return $null
    }

    # Apply defaults for missing fields
    if (-not $config.webhookUrl)       { $config.webhookUrl = "" }
    if (-not $config.interval)         { $config.interval = 1 }
    if (-not $config.selectedTunnelNames){ $config.selectedTunnelNames = @() }
    if (-not $config.cpolarApiBase)    { $config.cpolarApiBase = "http://localhost:9200" }
    if (-not $config.username)         { $config.username = "" }
    if (-not $config.password)         { $config.password = "" }
    if (-not $config.keyword)          { $config.keyword = "Cpolar" }
    if ($config.debug -ne $true)       { $config.debug = $false }

    # Clamp interval to minimum 5 minutes
    if ($config.interval -lt 1) { $config.interval = 1 }

    return $config
}

# ============================================================
# Function: Get-TunnelId — compute a stable unique ID for a tunnel
# ============================================================
function Get-TunnelId {
    param($tunnel)
    # Use name|protocol as the composite key (same as the userscript)
    $name = if ($tunnel.name) { $tunnel.name } else { "" }
    $proto = if ($tunnel.protocol) { $tunnel.protocol } else { "" }
    return "$name|$proto"
}

# ============================================================
# Function: Invoke-CpolarApi — call Cpolar backend API with token query param
# ============================================================
function Invoke-CpolarApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $false)]
        [string]$Method = "query"
    )

    $fullUrl = $Url
    $headers = @{}

    if ($Method -eq "query") {
        $fullUrl = "$Url`?token=$Token"
    } else {
        $headers["Authorization"] = "Bearer $Token"
    }

    try {
        if ($Method -eq "query") {
            $webResponse = Invoke-WebRequest -Uri $fullUrl -Method Get -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
        } else {
            $webResponse = Invoke-WebRequest -Uri $fullUrl -Method Get -Headers $headers -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
        }
        $rawJson = $webResponse.Content
        $result = $rawJson | ConvertFrom-Json
        return @{ Parsed = $result; Raw = $rawJson }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $body = $reader.ReadToEnd()
            $reader.Close()
        } catch { $body = "(无法读取响应体)" }
        Write-GuardLog -Level "WARN" -Message "API($Method) failed: $statusCode - $body"
        return $null
    }
}

# ============================================================
# Function: Login-Cpolar — login to Cpolar and get token
# ============================================================
function Login-Cpolar {
    param($Config)

    $loginUrl = "$($Config.cpolarApiBase)/api/v1/user/login"

    # Try different field combinations since Cpolar may use email as login name
    $loginAttempts = @(
        @{ username = $Config.username; password = $Config.password },
        @{ email    = $Config.username; password = $Config.password },
        @{ account  = $Config.username; password = $Config.password }
    )

    foreach ($bodyObj in $loginAttempts) {
        $body = $bodyObj | ConvertTo-Json
        Write-GuardLog -Level "INFO" -Message "Attempting login with fields: $($bodyObj.Keys -join ', ')"

        try {
            $response = Invoke-RestMethod -Uri $loginUrl `
                -Method Post `
                -ContentType "application/json;charset=utf-8" `
                -Body $body `
                -TimeoutSec 15 `
                -UseBasicParsing `
                -ErrorAction Stop

            # Check for token in various response formats
            $token = $null
            if ($response.code -eq 0 -and $response.data -and $response.data.token) {
                $token = $response.data.token
            } elseif ($response.data -and $response.data.token) {
                $token = $response.data.token
            } elseif ($response.token) {
                $token = $response.token
            }

            if ($token) {
                Write-GuardLog -Level "INFO" -Message "Login successful"
                return $token
            }

            # If response has code but no token, log and try next format
            if ($response.code) {
                Write-GuardLog -Level "INFO" -Message "Login responded: code=$($response.code) msg=$($response.message)"
            } else {
                Write-GuardLog -Level "INFO" -Message "Login responded: $($response | ConvertTo-Json -Compress)"
            }
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errBody = $reader.ReadToEnd()
                $reader.Close()
            } catch { $errBody = "(无法读取)" }
            Write-GuardLog -Level "INFO" -Message "Login attempt failed: $statusCode - $errBody"
        }
    }

    Write-GuardLog -Level "ERROR" -Message "所有登录方式均失败"
    return $null
}

# ============================================================
# Function: Get-ApiToken — login to Cpolar and get token
# ============================================================
$script:apiToken = $null
function Get-ApiToken {
    param($Config)

    if ($script:apiToken) { return $script:apiToken }

    if (-not $Config.username -or -not $Config.password) {
        Write-GuardLog -Level "ERROR" -Message "config.json 中未配置 username 和 password，请填写 Cpolar 登录邮箱和密码"
        return $null
    }

    $script:apiToken = Login-Cpolar -Config $Config
    return $script:apiToken
}

# ============================================================
# Function: Fetch-Tunnels — retrieve tunnel list from Cpolar API
# ============================================================
function Fetch-Tunnels {
    param($Config)

    # If no cached token, try to get one
    if (-not $script:apiToken) {
        $script:apiToken = Get-ApiToken -Config $Config
    }

    if (-not $script:apiToken) {
        Write-GuardLog -Level "WARN" -Message "获取 token 失败，请检查 config/config.json 中的 username 和 password"
        return $null
    }

    $apiUrl = "$($Config.cpolarApiBase)$apiTunnelsPath"
    Write-GuardLog -Level "CHECK" -Message "Fetching tunnels from: $apiUrl"

    $apiResponse = Invoke-CpolarApi -Url $apiUrl -Token $script:apiToken -Method "header"
    if (-not $apiResponse) {
        # Bearer header failed, try re-login (token may have expired)
        Write-GuardLog -Level "WARN" -Message "Token 可能已过期，尝试重新登录..."
        $script:apiToken = Login-Cpolar -Config $Config
        if ($script:apiToken) {
            $apiResponse = Invoke-CpolarApi -Url $apiUrl -Token $script:apiToken -Method "header"
        }
        if (-not $apiResponse) { return $null }
    }

    $result = $apiResponse.Parsed
    $rawJson = $apiResponse.Raw

    # Normalize response to tunnel array
    # Cpolar API returns: { code:20000, message:"", data:{ total:N, items:[...] } }
    $tunnels = $null
    $responseData = $result
    if ($result.PSObject.Properties.Name -contains 'data' -and $result.code -eq 20000) {
        $responseData = $result.data
    }
    if ($responseData.PSObject.Properties.Name -contains 'items') {
        $tunnels = $responseData.items
    } elseif ($responseData -is [System.Array]) {
        $tunnels = $responseData
    }

    if ($null -eq $tunnels) { $tunnels = @() }

    # Normalize: add computed display fields, keep ALL original API fields
    $tunnels = $tunnels | ForEach-Object {
        $t = $_
        $cfg = if ($t.configuration) { $t.configuration } else { $null }
        $pub = if ($t.publish_tunnels -and $t.publish_tunnels.Count -gt 0) { $t.publish_tunnels[0] } else { $null }

        # Compute display fields (PowerShell 5+ compatible — no inline if expressions)
        $protoVal = ""
        if ($pub -and $pub.proto) { $protoVal = $pub.proto }

        $pubUrlVal = ""
        if ($pub -and $pub.public_url) { $pubUrlVal = $pub.public_url }
        elseif ($t.public_url) { $pubUrlVal = $t.public_url }

        $localAddrVal = ""
        if ($pub -and $pub.addr) { $localAddrVal = $pub.addr }
        elseif ($cfg -and $cfg.addr) { $localAddrVal = "http://localhost:$($cfg.addr)" }

        $createTimeVal = ""
        if ($pub -and $pub.create_datetime) {
            try {
                $utcTime = [DateTime]::Parse($pub.create_datetime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
                $localTime = $utcTime.ToLocalTime()
                $createTimeVal = $localTime.ToString("yyyy年MM月dd日 HH时mm分ss秒")
            } catch {
                $createTimeVal = $pub.create_datetime
            }
        }

        # Add computed fields to the original object (preserves all API fields)
        $t | Add-Member -NotePropertyName "protocol"   -NotePropertyValue $protoVal -Force
        $t | Add-Member -NotePropertyName "publicUrl"  -NotePropertyValue $pubUrlVal -Force
        $t | Add-Member -NotePropertyName "localAddr"  -NotePropertyValue $localAddrVal -Force
        $t | Add-Member -NotePropertyName "createTime" -NotePropertyValue $createTimeVal -Force

        $t
    }

    $tunnelCount = $tunnels.Count

    Write-GuardLog -Level "CHECK" -Message "Fetched $tunnelCount tunnels"
    if ($Config.debug) {
        $rawPreview = $rawJson
        if ($rawPreview.Length -gt 800) { $rawPreview = $rawPreview.Substring(0, 800) + "..." }
        Write-GuardLog -Level "INFO" -Message "Raw API response: $rawPreview"
    }

    return $tunnels
}

# ============================================================
# Function: Detect-TunnelChanges — compare old and new tunnel data
# ============================================================
function Detect-TunnelChanges {
    param(
        $OldData,
        $NewData,
        $SelectedIds
    )

    $hasSelectedFilter = ($SelectedIds -and $SelectedIds.Count -gt 0)

    # Build lookup maps by tunnel name
    $oldMap = @{}
    if ($OldData) {
        foreach ($t in $OldData) {
            $name = if ($t.name) { $t.name } else { "" }
            $oldMap[$name] = $t
        }
    }

    $newMap = @{}
    foreach ($t in $NewData) {
        $name = if ($t.name) { $t.name } else { "" }
        $newMap[$name] = $t
    }

    # Filter by selected tunnel names if configured
    $relevantNewNames = if ($hasSelectedFilter) {
        $newMap.Keys | Where-Object { $_ -in $SelectedIds }
    } else {
        $newMap.Keys
    }

    $added       = @()
    $updated     = @()
    $reconnected = @()
    $removed     = @()

    # Detect added, updated, and reconnected
    foreach ($name in $relevantNewNames) {
        if (-not $oldMap.ContainsKey($name)) {
            $added += $newMap[$name]
        } elseif (-not (Test-TunnelEqual -a $newMap[$name] -b $oldMap[$name])) {
            $updated += $newMap[$name]
        } elseif ($newMap[$name].createTime -ne $oldMap[$name].createTime) {
            $reconnected += $newMap[$name]
        }
    }

    # Detect removed (only among previously relevant tunnels)
    $relevantOldNames = if ($hasSelectedFilter) {
        $oldMap.Keys | Where-Object { $_ -in $SelectedIds }
    } else {
        $oldMap.Keys
    }
    foreach ($name in $relevantOldNames) {
        if (-not $newMap.ContainsKey($name)) {
            $t = $oldMap[$name]
            $t | Add-Member -NotePropertyName "status" -NotePropertyValue "offline" -Force
            $removed += $t
        }
    }

    $hasChanges = ($added.Count -gt 0) -or ($updated.Count -gt 0) -or ($reconnected.Count -gt 0) -or ($removed.Count -gt 0)

    return @{
        added       = $added
        updated     = $updated
        reconnected = $reconnected
        removed     = $removed
        hasChanges  = $hasChanges
    }
}

# ============================================================
# Function: Test-TunnelEqual — compare two tunnel objects field by field
# ============================================================
function Test-TunnelEqual {
    param($a, $b)
    # Compare essential fields: name, protocol, publicUrl, localAddr, status
    $fields = @('name', 'protocol', 'publicUrl', 'localAddr', 'status')
    foreach ($f in $fields) {
        $va = if ($a.$f) { $a.$f } else { "" }
        $vb = if ($b.$f) { $b.$f } else { "" }
        if ($va -ne $vb) { return $false }
    }
    return $true
}

# ============================================================
# Function: Filter-SelectedTunnels — filter tunnel list to selected IDs
# ============================================================
function Filter-SelectedTunnels {
    param($Tunnels, $SelectedNames)

    # Empty list = 不监控任何隧道
    if (-not $SelectedNames -or $SelectedNames.Count -eq 0) { return @() }

    $result = @()
    foreach ($t in $Tunnels) {
        $name = if ($t.name) { $t.name } else { "" }
        if ($name -in $SelectedNames) {
            $result += $t
        }
    }
    return $result
}

# ============================================================
# Function: Build-DingTalkMessage — build DingTalk Markdown message body
# ============================================================
function Build-DingTalkMessage {
    param(
        $DiffResult,
        [string]$Keyword = "Cpolar"
    )

    $now = Get-Date
    $timeStr = $now.ToString("yyyy-MM-dd HH:mm:ss")

    $lines = @()
    $lines += "$Keyword"
    $lines += ""
    $lines += "## Cpolar 隧道状态变更通知"
    $lines += ""
    $lines += "---"
    $lines += ""

    # Helper to format a tunnel entry
    function Format-TunnelEntry {
        param($t, $prefix, $title)
        $lines = @()
        $lines += "**$prefix $($t.name)** — $title"
        if ($t.protocol)  { $lines += "- 协议：$($t.protocol)" }
        if ($t.publicUrl) { $lines += "- 公网地址：$($t.publicUrl)" }
        if ($t.localAddr) { $lines += "- 本地地址：$($t.localAddr)" }
        if ($t.createTime) { $lines += "- 创建时间：$($t.createTime)" }
        $lines += ""
        return $lines
    }

    # Added tunnels
    if ($DiffResult.added.Count -gt 0) {
        foreach ($t in $DiffResult.added) {
            $lines += Format-TunnelEntry -t $t -prefix "🟢" -title "新增上线"
        }
    }

    # Updated tunnels
    if ($DiffResult.updated.Count -gt 0) {
        foreach ($t in $DiffResult.updated) {
            $lines += Format-TunnelEntry -t $t -prefix "🔄" -title "信息变更"
        }
    }

    # Reconnected tunnels (only createTime changed — tunnel restarted)
    if ($DiffResult.reconnected.Count -gt 0) {
        foreach ($t in $DiffResult.reconnected) {
            $lines += Format-TunnelEntry -t $t -prefix "🟢" -title "重新上线（隧道重启）"
        }
    }

    # Offline tunnels
    if ($DiffResult.removed.Count -gt 0) {
        foreach ($t in $DiffResult.removed) {
            $lines += Format-TunnelEntry -t $t -prefix "🔴" -title "已离线"
        }
    }

    # Footer with detection time
    $lines += "---"
    $lines += ""
    $lines += "⏱ 检测时间：$timeStr"

    return @{
        msgtype = "markdown"
        markdown = @{
            title = "Cpolar 隧道状态变更"
            text  = $lines -join "`n"
        }
    }
}

# ============================================================
# Function: Send-DingTalkWebhook — push message to DingTalk robot
# ============================================================
function Send-DingTalkWebhook {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl,

        [Parameter(Mandatory = $true)]
        $MessageBody
    )

    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) {
        Write-GuardLog -Level "WARN" -Message "Webhook URL 未配置，跳过推送"
        return $false
    }

    $jsonBody = $MessageBody | ConvertTo-Json -Depth 5 -Compress

    try {
        $response = Invoke-RestMethod -Uri $WebhookUrl `
            -Method Post `
            -ContentType "application/json;charset=utf-8" `
            -Body $jsonBody `
            -TimeoutSec 15 `
            -ErrorAction Stop

        if ($response.errcode -eq 0) {
            Write-GuardLog -Level "INFO" -Message "钉钉推送成功"
            return $true
        } else {
            Write-GuardLog -Level "ERROR" -Message "钉钉返回错误: $($response.errmsg)"
            return $false
        }
    } catch {
        Write-GuardLog -Level "ERROR" -Message "钉钉推送失败: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================
# Function: Save-LastSent — persist last-sent tunnel snapshot
# ============================================================
function Save-LastSent {
    param($Tunnels)
    try {
        $json = $Tunnels | ConvertTo-Json -Depth 5 -Compress
        Set-Content -Path $sentCachePath -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-GuardLog -Level "WARN" -Message "Failed to save last-sent cache: $_"
    }
}

# ============================================================
# Function: Load-LastSent — load last-sent tunnel snapshot
# ============================================================
function Load-LastSent {
    if (-not (Test-Path -Path $sentCachePath)) { return $null }
    try {
        $data = Get-Content -Path $sentCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        return $data
    } catch {
        Write-GuardLog -Level "WARN" -Message "Failed to load last-sent cache: $_"
        return $null
    }
}

# ============================================================
# Function: Format-Time — format DateTime to HH:mm:ss
# ============================================================
function Format-Time {
    param($Date)
    return $Date.ToString("HH:mm:ss")
}

# ============================================================
# Function: Get-IntervalSeconds — get polling interval in seconds
# ============================================================
function Get-IntervalSeconds {
    param($Config)
    return [Math]::Max(60, $Config.interval * 60)
}

# ============================================================
# Entry point
# ============================================================

Initialize-GuardLog

Write-GuardLog -Level "INFO" -Message "CpolarGuard started. ScriptDir=$scriptDir"

$config = Read-Config
if (-not $config) {
    Write-GuardLog -Level "ERROR" -Message "Failed to load config. Exiting."
    Start-Sleep -Seconds 5
    exit 1
}

$global:pollInterval = Get-IntervalSeconds -Config $config
$global:lastData = Load-LastSent
$global:isFirstRun = $true

Write-GuardLog -Level "INFO" -Message "Poll interval: $($global:pollInterval)s | Debug=$($config.debug)"
if (-not $config.webhookUrl) {
    Write-GuardLog -Level "WARN" -Message "Webhook URL 未配置，请编辑 config/config.json 设置 webhookUrl"
}
if (-not $config.username -or -not $config.password) {
    Write-GuardLog -Level "WARN" -Message "username 或 password 未配置，请编辑 config/config.json 填写 Cpolar 登录邮箱和密码"
}

# ============================================================
# Config hot-reload watcher
# ============================================================
$script:configLastWrite = $null
function Watch-ConfigChange {
    try {
        if (Test-Path $configPath) {
            $currentWrite = (Get-Item $configPath).LastWriteTime
            if ($script:configLastWrite -and $currentWrite -gt $script:configLastWrite) {
                Write-GuardLog -Level "INFO" -Message "config.json 已变更，将在下一周期自动生效"
            }
            $script:configLastWrite = $currentWrite
        }
    } catch {
        # Silently ignore read errors
    }
}

# ============================================================
# Main guard loop: poll → diff → push → sleep
# ============================================================
Write-GuardLog -Level "INFO" -Message "Guard loop started."

while ($true) {
    $config = Read-Config
    if (-not $config) {
        Write-GuardLog -Level "ERROR" -Message "config.json reload failed. Will retry next cycle."
        Start-Sleep -Seconds $global:pollInterval
        continue
    }
    Watch-ConfigChange

    $global:pollInterval = Get-IntervalSeconds -Config $config

    # --------------------------------------------------------
    # 1. Fetch tunnels from Cpolar API
    # --------------------------------------------------------
    $tunnels = Fetch-Tunnels -Config $config
    if (-not $tunnels) {
        Write-GuardLog -Level "WARN" -Message "No tunnel data fetched (check token or Cpolar Web). Will retry."
        Start-Sleep -Seconds $global:pollInterval
        continue
    }

    # --------------------------------------------------------
    # 2. Filter to selected tunnels
    # --------------------------------------------------------
    $selectedTunnels = Filter-SelectedTunnels -Tunnels $tunnels -SelectedNames $config.selectedTunnelNames
    $hasSelectedFilter = ($config.selectedTunnelNames -and $config.selectedTunnelNames.Count -gt 0)

    # 未配置任何勾选隧道 → 跳过推送
    if ($selectedTunnels.Count -eq 0 -and -not $hasSelectedFilter) {
        Write-GuardLog -Level "CHECK" -Message "未勾选隧道，跳过推送"
        $global:lastData = $selectedTunnels
        Save-LastSent -Tunnels $selectedTunnels
        $global:isFirstRun = $false
        Start-Sleep -Seconds $global:pollInterval
        continue
    }

    # --------------------------------------------------------
    # 3. Detect changes
    # --------------------------------------------------------
    $oldData = if ($global:isFirstRun) { Load-LastSent } else { $global:lastData }
    $diff = Detect-TunnelChanges -OldData $oldData -NewData $selectedTunnels -SelectedIds $config.selectedTunnelNames

    # Update cached data
    $global:lastData = $selectedTunnels
    $global:isFirstRun = $false

    # --------------------------------------------------------
    # 4. Push if there are changes
    # --------------------------------------------------------
    if ($diff.hasChanges) {
        Write-GuardLog -Level "INFO" -Message "变更检测: $($diff.added.Count) 新增, $($diff.updated.Count) 更新, $($diff.reconnected.Count) 重新上线, $($diff.removed.Count) 离线"

        $message = Build-DingTalkMessage -DiffResult $diff -Keyword $config.keyword
        $success = Send-DingTalkWebhook -WebhookUrl $config.webhookUrl -MessageBody $message

        if ($success) {
            Save-LastSent -Tunnels $selectedTunnels
            Write-GuardLog -Level "INFO" -Message "推送完成"
        } else {
            Write-GuardLog -Level "WARN" -Message "推送失败，下次重试时重新检测"
        }
    } else {
        Write-GuardLog -Level "CHECK" -Message "无变更，已跳过推送"
    }

    # --------------------------------------------------------
    # 5. Wait for next polling cycle
    # --------------------------------------------------------
    Start-Sleep -Seconds $global:pollInterval
}
