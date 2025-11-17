# Simple daily USER summary (today only)
# - Console + RDP sessions (LogonType 2, 10)
# - Noise accounts (UMFD, DWM, NT AUTHORITY, services) are filtered out
# Output: C:\Temp\ServerUserSummary_TODAY.txt

$ErrorActionPreference = 'Stop'

# ---- Time range: today ----
$today     = Get-Date
$startTime = $today.Date
$endTime   = $startTime.AddDays(1)

Write-Host "Building simple USER summary for today: $($startTime.ToShortDateString()) ..." -ForegroundColor Cyan

# ---- Output file ----
$folder = "C:\Temp"
if (!(Test-Path $folder)) {
    New-Item -ItemType Directory -Path $folder | Out-Null
}
$outFile = Join-Path $folder "ServerUserSummary_TODAY.txt"
if (Test-Path $outFile) { Remove-Item $outFile -Force }

function Get-LogonTypeName {
    param([int]$Type)
    switch ($Type) {
        2  { 'Interactive (console)' }
        10 { 'RemoteInteractive (RDP/TS)' }
        Default { "Other ($Type)" }
    }
}

function Is-RealUser {
    param(
        [string]$Domain,
        [string]$User
    )

    if ([string]::IsNullOrWhiteSpace($User)) { return $false }

    # service / system noise
    if ($User -in @('SYSTEM','LOCAL SERVICE','NETWORK SERVICE')) { return $false }
    if ($User.StartsWith('$')) { return $false }           # computer accounts
    if ($Domain -in @('NT AUTHORITY','Window Manager','Font Driver Host')) { return $false }
    if ($User -like 'UMFD-*') { return $false }
    if ($User -like 'DWM-*')  { return $false }
    if ($User -eq 'ANONYMOUS LOGON') { return $false }

    return $true
}

# ---- Read Security log ----
Write-Host "Reading Security log..." -ForegroundColor Yellow

$secFilter = @{
    LogName   = 'Security'
    Id        = @(4624,4634,4647,4672)
    StartTime = $startTime
    EndTime   = $endTime
}

$events = Get-WinEvent -FilterHashtable $secFilter -ErrorAction SilentlyContinue

$sessions     = @{}  # LogonId -> session object
$elevatedById = @{}  # LogonId -> $true

foreach ($ev in $events) {
    $xml  = [xml]$ev.ToXml()
    $sys  = $xml.Event.System
    $data = $xml.Event.EventData.Data
    $id   = [int]$sys.EventID

    if ($id -eq 4672) {
        # elevated logon
        $logonId = ($data | Where-Object { $_.Name -eq 'SubjectLogonId' }).'#text'
        if ($logonId) { $elevatedById[$logonId] = $true }
        continue
    }

    $user      = ($data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
    $domain    = ($data | Where-Object { $_.Name -eq 'TargetDomainName' }).'#text'
    $logonId   = ($data | Where-Object { $_.Name -eq 'TargetLogonId' }).'#text'
    $logonType = ($data | Where-Object { $_.Name -eq 'LogonType' }).'#text'

    if (-not (Is-RealUser -Domain $domain -User $user)) { continue }

    $lt = 0
    [void][int]::TryParse($logonType, [ref]$lt)

    if ($id -eq 4624) {
        # only console/RDP sessions
        if ($lt -notin @(2,10)) { continue }

        if (-not $sessions.ContainsKey($logonId)) {
            $sessions[$logonId] = [PSCustomObject]@{
                User          = "{0}\{1}" -f $domain, $user
                LogonId       = $logonId
                LogonTime     = $ev.TimeCreated
                LogoffTime    = $null
                LogonType     = $lt
                LogonTypeName = Get-LogonTypeName -Type $lt
                Elevated      = $false
            }
        }
    }
    elseif ($id -in 4634,4647) {
        if ($sessions.ContainsKey($logonId)) {
            if (-not $sessions[$logonId].LogoffTime) {
                $sessions[$logonId].LogoffTime = $ev.TimeCreated
            }
        }
    }
}

# mark elevated sessions
foreach ($id in $sessions.Keys) {
    if ($elevatedById.ContainsKey($id)) {
        $sessions[$id].Elevated = $true
    }
}

$sessionList = $sessions.Values | Sort-Object LogonTime, User

# ---- Build per-user summary ----
"SERVER USER SUMMARY (TODAY)"                               | Out-File $outFile -Encoding UTF8
"Server:   $env:COMPUTERNAME"                              | Out-File $outFile -Append -Encoding UTF8
"Date:     $($startTime.ToShortDateString())"              | Out-File $outFile -Append -Encoding UTF8
"Generated: $(Get-Date)"                                   | Out-File $outFile -Append -Encoding UTF8
"========================================================" | Out-File $outFile -Append -Encoding UTF8
""                                                         | Out-File $outFile -Append -Encoding UTF8

if (-not $sessionList -or $sessionList.Count -eq 0) {
    "No user console/RDP sessions found for today."        | Out-File $outFile -Append -Encoding UTF8
} else {
    $grouped = $sessionList | Group-Object -Property User

    foreach ($g in $grouped | Sort-Object Name) {
        $userSessions = $g.Group
        $totalSessions = $userSessions.Count
        $totalDuration = [TimeSpan]::Zero
        $firstLogon    = $userSessions | Sort-Object LogonTime | Select-Object -First 1 -ExpandProperty LogonTime
        $lastLogoff    = $null
        $hadElevated   = $false

        foreach ($s in $userSessions) {
            if ($s.LogoffTime) {
                $totalDuration += (New-TimeSpan -Start $s.LogonTime -End $s.LogoffTime)
                if (-not $lastLogoff -or $s.LogoffTime -gt $lastLogoff) {
                    $lastLogoff = $s.LogoffTime
                }
            }
            if ($s.Elevated) { $hadElevated = $true }
        }

        "User:        $($g.Name)"                           | Out-File $outFile -Append -Encoding UTF8
        "Sessions:    $totalSessions"                       | Out-File $outFile -Append -Encoding UTF8
        "Total time:  {0:dd\.hh\:mm\:ss}" -f $totalDuration | Out-File $outFile -Append -Encoding UTF8
        "First logon: $firstLogon"                          | Out-File $outFile -Append -Encoding UTF8
        "Last logoff: {0}" -f ($lastLogoff ?? "(no logoff event)") | Out-File $outFile -Append -Encoding UTF8
        "Any elevated: $hadElevated"                        | Out-File $outFile -Append -Encoding UTF8
        "--------------------------------------------------------" | Out-File $outFile -Append -Encoding UTF8
    }
}

Write-Host "Summary saved to: $outFile" -ForegroundColor Green
