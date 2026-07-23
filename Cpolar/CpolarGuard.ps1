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
        $statusCode = "?"
        $body = "(无法读取响应体)"
        if ($_.Exception.Response) {
            try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch { }
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $body = $reader.ReadToEnd()
                $reader.Close()
            } catch { }
        } else {
            $body = $_.Exception.Message
        }
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

    # Login with email + password (Cpolar Web uses email as login name)
    $bodyObj = @{ email = $Config.username; password = $Config.password }
    $body = $bodyObj | ConvertTo-Json

    Write-GuardLog -Level "INFO" -Message "Logging in with email"

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

        Write-GuardLog -Level "ERROR" -Message "Login failed: code=$($response.code) msg=$($response.message)"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $errBody = $reader.ReadToEnd()
            $reader.Close()
        } catch { $errBody = "(无法读取)" }
        Write-GuardLog -Level "ERROR" -Message "Login failed: $statusCode - $errBody"
    }

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
    $tunnels = @($tunnels | ForEach-Object {
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
    })

    $tunnelCount = $tunnels.Count

    Write-GuardLog -Level "CHECK" -Message "Fetched $tunnelCount tunnels"
    if ($Config.debug) {
        $rawPreview = $rawJson
        if ($rawPreview.Length -gt 800) { $rawPreview = $rawPreview.Substring(0, 800) + "..." }
        Write-GuardLog -Level "INFO" -Message "Raw API response: $rawPreview"
    }

    Write-Output -NoEnumerate $tunnels
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

    # Build lookup maps by tunnel id (name|protocol) to handle same-name multi-protocol tunnels
    $oldMap = @{}
    if ($OldData) {
        foreach ($t in $OldData) {
            $id = Get-TunnelId $t
            $oldMap[$id] = $t
        }
    }

    $newMap = @{}
    foreach ($t in $NewData) {
        $id = Get-TunnelId $t
        $newMap[$id] = $t
    }

    # Filter by selected tunnel names if configured (keys are name|protocol, compare name part)
    $relevantNewIds = if ($hasSelectedFilter) {
        $newMap.Keys | Where-Object { ($_ -split '\|')[0] -in $SelectedIds }
    } else {
        $newMap.Keys
    }

    $added         = @()
    $updated       = @()
    $reconnected   = @()
    $removed       = @()
    $updatedDetails = @{}

    # Detect added, updated, and reconnected
    foreach ($id in $relevantNewIds) {
        if (-not $oldMap.ContainsKey($id)) {
            $added += $newMap[$id]
        } elseif (-not (Test-TunnelEqual -a $newMap[$id] -b $oldMap[$id])) {
            # 状态变为 inactive → 归入离线
            if ($newMap[$id].status -eq "inactive") {
                $removed += $newMap[$id]
            } elseif ($oldMap[$id].status -eq "inactive") {
                # 从 inactive 恢复 → 归入重新上线
                $reconnected += $newMap[$id]
            } else {
                $updated += $newMap[$id]
                # Record field-level change details
                $fieldDiff = Get-TunnelDiffFields -a $newMap[$id] -b $oldMap[$id]
                $updatedDetails[$id] = $fieldDiff
            }
        } elseif ($newMap[$id].createTime -ne $oldMap[$id].createTime) {
            $reconnected += $newMap[$id]
        }
    }

    # Detect removed (only among previously relevant tunnels)
    $relevantOldIds = if ($hasSelectedFilter) {
        $oldMap.Keys | Where-Object { ($_ -split '\|')[0] -in $SelectedIds }
    } else {
        $oldMap.Keys
    }
    foreach ($id in $relevantOldIds) {
        if (-not $newMap.ContainsKey($id)) {
            $t = $oldMap[$id]
            $t | Add-Member -NotePropertyName "status" -NotePropertyValue "offline" -Force
            $removed += $t
        }
    }

    $hasChanges = ($added.Count -gt 0) -or ($updated.Count -gt 0) -or ($reconnected.Count -gt 0) -or ($removed.Count -gt 0)

    return @{
        added          = $added
        updated        = $updated
        reconnected    = $reconnected
        removed        = $removed
        hasChanges     = $hasChanges
        updatedDetails = $updatedDetails
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
# Function: Get-TunnelDiffFields — return list of changed fields between two tunnels
# ============================================================
function Get-TunnelDiffFields {
    param($a, $b)
    $fields = @('name', 'protocol', 'publicUrl', 'localAddr', 'status')
    $diff = @()
    foreach ($f in $fields) {
        $va = if ($a.$f) { $a.$f.ToString() } else { "" }
        $vb = if ($b.$f) { $b.$f.ToString() } else { "" }
        if ($va -ne $vb) { $diff += @{ field = $f; old = $va; new = $vb } }
    }
    return $diff
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
        [string]$Keyword = "Cpolar",
        $ConfigEvents = $null,
        $SystemEvents = $null
    )

    $now = Get-Date
    $timeStr = $now.ToString("yyyy-MM-dd HH:mm:ss")

    # Build header
    $blocks = @()
    $blocks += "$Keyword"
    $blocks += ""
    $blocks += "## Cpolar 监控报告"
    $blocks += ""

    # [01] Config changes block
    $configBlock = Format-ConfigBlock -ConfigEvents $ConfigEvents
    if ($configBlock) { $blocks += $configBlock }

    # [02] Tunnel changes block
    $tunnelBlock = Format-TunnelBlock -DiffResult $DiffResult
    if ($tunnelBlock) { $blocks += $tunnelBlock }

    # [03] System status block
    $systemBlock = Format-SystemBlock -SystemEvents $SystemEvents
    if ($systemBlock) { $blocks += $systemBlock }

    # Footer with detection time
    $blocks += "---"
    $blocks += ""
    $blocks += "⏱ 检测时间：$timeStr"

    return @{
        msgtype = "markdown"
        markdown = @{
            title = "Cpolar 监控报告"
            text  = ($blocks -join "`n")
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
# Function: Format-FieldValue — normalize field value for display
# ============================================================
function Format-FieldValue {
    param($Value)
    if ($null -eq $Value -or ($Value -is [string] -and $Value -eq "")) { return "—" }
    if ($Value -is [int] -and $Value -eq 0) { return "0" }
    $str = $Value.ToString()
    if ($str.Length -gt 100) { return $str.Substring(0, 97) + "..." }
    return $str
}

# ============================================================
# Function: Compare-ConfigState — detect field-level config changes
# ============================================================
function Compare-ConfigState {
    param($Current, $Last)

    $result = @{ hasChanges = $false; changedFields = @(); missingFields = @(); configState = "valid" }
    if (-not $Last) { return $result }

    # Compare scalar fields
    $scalarFields = @(
        @{ name = "webhookUrl";        label = "Webhook 地址";   sensitive = $true  }
        @{ name = "interval";          label = "轮询间隔";       sensitive = $false }
        @{ name = "cpolarApiBase";     label = "API 地址";       sensitive = $false }
        @{ name = "keyword";           label = "消息关键词";     sensitive = $false }
        @{ name = "debug";             label = "调试模式";       sensitive = $false }
    )
    foreach ($f in $scalarFields) {
        $oldVal = Format-FieldValue ($Last.$($f.name))
        $newVal = Format-FieldValue ($Current.$($f.name))
        if ($oldVal -ne $newVal) {
            $entry = @{ field = $f.label; old = $oldVal; new = $newVal; sensitive = $f.sensitive }
            $result.hasChanges = $true
            $result.changedFields += $entry
        }
    }

    # Compare selectedTunnelNames (array)
    $oldNames = if ($Last.selectedTunnelNames) { @($Last.selectedTunnelNames) } else { @() }
    $newNames = if ($Current.selectedTunnelNames) { @($Current.selectedTunnelNames) } else { @() }
    $addedNames   = $newNames | Where-Object { $_ -notin $oldNames }
    $removedNames = $oldNames | Where-Object { $_ -notin $newNames }
    if ($addedNames.Count -gt 0 -or $removedNames.Count -gt 0) {
        $result.hasChanges = $true
        $result.changedFields += @{
            field     = "监控隧道列表"
            old       = if ($oldNames.Count -gt 0) { $oldNames -join ", " } else { "（空）" }
            new       = if ($newNames.Count -gt 0) { $newNames -join ", " } else { "（空）" }
            sensitive = $false
        }
    }

    # Detect missing required fields (only warn when empty)
    if (-not $Current.webhookUrl) { $result.missingFields += "webhookUrl" }
    if (-not $Current.selectedTunnelNames -or $Current.selectedTunnelNames.Count -eq 0) { $result.missingFields += "selectedTunnelNames" }

    return $result
}

# ============================================================
# Function: Format-ConfigBlock — render [01] Config changes section
# ============================================================
function Format-ConfigBlock {
    param($ConfigEvents)
    if (-not $ConfigEvents -or $ConfigEvents.Count -eq 0) { return $null }

    $lines = @()
    $lines += "━━━ Config 配置变更 ━━━"
    $lines += ""
    foreach ($evt in $ConfigEvents) {
        $lines += "**⚙️ $($evt.field) — 已变更**"
        if ($evt.sensitive) {
            $lines += "- 原值：$(Format-FieldValue $evt.old)"
            $lines += "- 新值：$(Format-FieldValue $evt.new)"
            $lines += "- 提示：敏感字段已隐藏实际值"
        } else {
            $lines += "- 原值：$(Format-FieldValue $evt.old)"
            $lines += "- 新值：$(Format-FieldValue $evt.new)"
            $lines += "- 生效：下一轮检测生效"
        }
        $lines += ""
    }
    return ($lines -join "`n")
}

# ============================================================
# Function: Format-TunnelBlock — render [02] Tunnel changes section
# ============================================================
function Format-TunnelBlock {
    param($DiffResult)

    if (-not $DiffResult -or -not $DiffResult.hasChanges) { return $null }

    # Helper: format one tunnel entry with fixed 3 fields
    function Format-TunnelEntry3 {
        param($t, $prefix, $title, $extraFields)
        $el = @()
        $el += "**$prefix $($t.name) — $title**"
        $el += "- 协议：$(Format-FieldValue $t.protocol)"
        $el += "- 公网地址：$(Format-FieldValue $t.publicUrl)"
        $el += "- 本地地址：$(Format-FieldValue $t.localAddr)"
        $el += "- 创建时间：$(Format-FieldValue $t.createTime)"
        if ($extraFields) {
            foreach ($ef in $extraFields) {
                $el += "- $($ef.label)：$(Format-FieldValue $ef.value)"
            }
        }
        $el += ""
        return $el
    }

    $lines = @()
    $lines += "━━━ 隧道状态变更 ━━━"
    $lines += ""

    # Added
    foreach ($t in $DiffResult.added) {
        $lines += Format-TunnelEntry3 -t $t -prefix "🟢" -title "新增上线"
    }
    # Reconnected
    foreach ($t in $DiffResult.reconnected) {
        $lines += Format-TunnelEntry3 -t $t -prefix "🟢" -title "重新上线"
    }
    # Updated
    foreach ($t in $DiffResult.updated) {
        $name = if ($t.name) { $t.name } else { "" }
        $details = @()
        if ($DiffResult.updatedDetails -and $DiffResult.updatedDetails[$name]) {
            $changedFields = ($DiffResult.updatedDetails[$name] | ForEach-Object { $_.field }) -join "、"
            $details += @{ label = "变更项"; value = $changedFields }
        }
        $lines += Format-TunnelEntry3 -t $t -prefix "🔄" -title "信息变更" -extraFields $details
    }
    # Removed / offline
    foreach ($t in $DiffResult.removed) {
        $lines += Format-TunnelEntry3 -t $t -prefix "🔴" -title "已离线"
    }

    return ($lines -join "`n")
}

# ============================================================
# Function: Format-SystemBlock — render [03] System status section
# ============================================================
function Format-SystemBlock {
    param($SystemEvents)
    if (-not $SystemEvents -or $SystemEvents.Count -eq 0) { return $null }

    $lines = @()
    $lines += "━━━ 系统状态 ━━━"
    $lines += ""

    foreach ($evt in $SystemEvents) {
        $emoji = switch ($evt.type) {
            'AUTH_FAILED'       { "🔑❌" }
            'AUTH_RECOVERED'    { "🔑✅" }
            'API_FAILED'        { "🌐❌" }
            'API_RECOVERED'     { "🌐✅" }
            'PUSH_FAILED_ALERT' { "📤🔴" }
            'PUSH_RECOVERED'    { "📤✅" }
            'DATA_INCOMPLETE'   { "⚠️📡" }
            'FIRST_RUN'         { "🚀" }
            default             { "ℹ️" }
        }
        $lines += "**$emoji $($evt.title) — $($evt.action)**"
        if ($evt.fields) {
            foreach ($f in $evt.fields) {
                $lines += "- $($f.label)：$(Format-FieldValue $f.value)"
            }
        }
        $lines += ""
    }

    return ($lines -join "`n")
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
$global:lastConfig = $null              # 上一轮 config 快照（用于字段级对比）
$global:pushHistory = @{ consecutiveFails = 0; lastFailTime = $null; lastFailReason = "" }
$global:apiHistory = @{ consecutiveFails = 0; lastSuccessTime = $null; lastFailTime = $null; lastFailReason = "" }

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
    # [Config] Detect field-level config changes
    # --------------------------------------------------------
    $configDiff = Compare-ConfigState -Current $config -Last $global:lastConfig
    if ($configDiff.hasChanges) {
        $global:lastConfig = $config
        Write-GuardLog -Level "INFO" -Message "Config 变更: $($configDiff.changedFields.Count) 个字段"
    } elseif (-not $global:lastConfig) {
        # First successful load — establish baseline
        $global:lastConfig = $config
    }
    if ($configDiff.missingFields.Count -gt 0) {
        Write-GuardLog -Level "WARN" -Message "Config 缺失字段: $($configDiff.missingFields -join ', ')"
    }

    # --------------------------------------------------------
    # 1. Fetch tunnels from Cpolar API
    # --------------------------------------------------------
    $tunnels = Fetch-Tunnels -Config $config
    if ($null -eq $tunnels) {
        $global:apiHistory.consecutiveFails++
        $global:apiHistory.lastFailTime = Get-Date
        if ($global:apiHistory.consecutiveFails -eq 1) {
            Write-GuardLog -Level "WARN" -Message "API 请求失败（首次），将在下一周期重试"
        } elseif ($global:apiHistory.consecutiveFails -eq 3) {
            Write-GuardLog -Level "WARN" -Message "API 已连续 $($global:apiHistory.consecutiveFails) 次失败，请检查 Cpolar Web 服务是否运行，但历史记录中仍有 $(@($global:lastData).Count) 个隧道"
        } else {
            Write-GuardLog -Level "WARN" -Message "API 请求失败（连续 $($global:apiHistory.consecutiveFails) 次）"
        }
        Start-Sleep -Seconds $global:pollInterval
        continue
    }
    # API success — reset failure counter
    if ($global:apiHistory.consecutiveFails -gt 0) {
        Write-GuardLog -Level "INFO" -Message "API 已恢复（之前连续失败 $($global:apiHistory.consecutiveFails) 次）"
        $global:apiHistory.consecutiveFails = 0
        $global:apiHistory.lastSuccessTime = Get-Date
    }

    # --------------------------------------------------------
    # 2. Filter to selected tunnels
    # --------------------------------------------------------
    $selectedTunnels = Filter-SelectedTunnels -Tunnels $tunnels -SelectedNames $config.selectedTunnelNames

    # 无任何匹配隧道 → 检查是否有历史数据需要离线通知
    if ($selectedTunnels.Count -eq 0) {
        # 检查 lastData 是否有历史记录（last-sent.json 中缓存的隧道）
        $hasHistorical = $global:lastData -and (@($global:lastData).Count -gt 0)

        if ($hasHistorical -and -not $global:isFirstRun) {
            # 之前缓存的隧道全部消失 → 触发离线检测
            $historicalCount = @($global:lastData).Count
            Write-GuardLog -Level "INFO" -Message "API 返回空列表，但历史记录中有 $historicalCount 个隧道，检测到全部离线"

            $diff = Detect-TunnelChanges -OldData $global:lastData -NewData @() -SelectedIds @()
            if ($diff.hasChanges) {
                $message = Build-DingTalkMessage -DiffResult $diff -Keyword $config.keyword -ConfigEvents $configDiff.changedFields -SystemEvents $null
                $success = Send-DingTalkWebhook -WebhookUrl $config.webhookUrl -MessageBody $message

                if ($success) {
                    $global:lastData = @()
                    Save-LastSent -Tunnels @()
                    Write-GuardLog -Level "INFO" -Message "全部隧道离线推送完成，已清空 last-sent.json"
                } else {
                    Write-GuardLog -Level "WARN" -Message "全部隧道离线推送失败"
                }
            }
        } else {
            Write-GuardLog -Level "CHECK" -Message "无匹配隧道且无历史记录，跳过推送"
        }

        $global:lastData = @()
        Save-LastSent -Tunnels @()
        $global:isFirstRun = $false

        # Still push config-only changes (if no offline push was done above)
        if ($configDiff.hasChanges -and -not $hasHistorical) {
            $message = Build-DingTalkMessage -DiffResult $null -Keyword $config.keyword -ConfigEvents $configDiff.changedFields
            $success = Send-DingTalkWebhook -WebhookUrl $config.webhookUrl -MessageBody $message
            if ($success) {
                Write-GuardLog -Level "INFO" -Message "Config 变更推送完成"
            } else {
                Write-GuardLog -Level "WARN" -Message "Config 变更推送失败"
            }
        }
        Start-Sleep -Seconds $global:pollInterval
        continue
    }

    # --------------------------------------------------------
    # 3. Detect tunnel changes
    # --------------------------------------------------------
    $oldData = if ($global:isFirstRun) { Load-LastSent } else { $global:lastData }
    $diff = Detect-TunnelChanges -OldData $oldData -NewData $selectedTunnels -SelectedIds $config.selectedTunnelNames

    # Update cached data
    $global:lastData = $selectedTunnels
    $global:isFirstRun = $false

    # --------------------------------------------------------
    # 4. Collect system events
    # --------------------------------------------------------
    $systemEvents = @()

    # Push failure alert (only when consecutive failures reach threshold)
    if ($global:pushHistory.consecutiveFails -ge 3) {
        $lastFailStr = if ($global:pushHistory.lastFailTime) { $global:pushHistory.lastFailTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "—" }
        $systemEvents += @{
            type   = "PUSH_FAILED_ALERT"
            title  = "推送持续失败"
            action = "已连续 $($global:pushHistory.consecutiveFails) 次"
            fields = @(
                @{ label = "连续失败次数"; value = "$($global:pushHistory.consecutiveFails) 次" }
                @{ label = "最后失败时间"; value = $lastFailStr }
                @{ label = "建议";         value = "检查 config.json 中的 webhookUrl 是否正确" }
            )
        }
    }

    # --------------------------------------------------------
    # 5. Push if there are any changes
    # --------------------------------------------------------
    $hasAnyChanges = $diff.hasChanges -or $configDiff.hasChanges -or $systemEvents.Count -gt 0

    if ($hasAnyChanges) {
        if ($diff.hasChanges) {
            Write-GuardLog -Level "INFO" -Message "变更检测: $($diff.added.Count) 新增, $($diff.updated.Count) 更新, $($diff.reconnected.Count) 重新上线, $($diff.removed.Count) 离线"
        }

        # 数据完整性检查：等待 Cpolar API 数据稳定后再推送
        # 排除离线隧道（removed），它们没有新数据是正常的
        $allOnChanged = $diff.added + $diff.updated + $diff.reconnected
        $incompleteTunnels = $allOnChanged | Where-Object { -not $_.protocol -or -not $_.publicUrl }

        if ($incompleteTunnels -and $diff.hasChanges) {
            $names = ($incompleteTunnels | ForEach-Object { $_.name }) -join ", "
            Write-GuardLog -Level "WARN" -Message "隧道 [$names] 数据不完整（缺少协议或公网地址），Cpolar API 数据尚未就绪，本轮跳过推送，下一轮重试"
        } else {
            $message = Build-DingTalkMessage -DiffResult $diff -Keyword $config.keyword -ConfigEvents $configDiff.changedFields -SystemEvents $systemEvents
            $success = Send-DingTalkWebhook -WebhookUrl $config.webhookUrl -MessageBody $message

            if ($success) {
                if ($diff.hasChanges) { Save-LastSent -Tunnels $selectedTunnels }
                Write-GuardLog -Level "INFO" -Message "推送完成"
                # Reset push failure counter on success
                if ($global:pushHistory.consecutiveFails -gt 0) {
                    Write-GuardLog -Level "INFO" -Message "推送已恢复（之前连续失败 $($global:pushHistory.consecutiveFails) 次）"
                    $global:pushHistory.consecutiveFails = 0
                    $global:pushHistory.lastFailTime = $null
                    $global:pushHistory.lastFailReason = ""
                }
            } else {
                $global:pushHistory.consecutiveFails++
                $global:pushHistory.lastFailTime = Get-Date
                if ($global:pushHistory.consecutiveFails -eq 1) {
                    $global:pushHistory.lastFailReason = "首次推送失败"
                }
                Write-GuardLog -Level "WARN" -Message "推送失败（已连续 $($global:pushHistory.consecutiveFails) 次）"
            }
        }
    } else {
        Write-GuardLog -Level "CHECK" -Message "无变更，已跳过推送"
    }

    # --------------------------------------------------------
    # 6. Wait for next polling cycle
    # --------------------------------------------------------
    Start-Sleep -Seconds $global:pollInterval
}
