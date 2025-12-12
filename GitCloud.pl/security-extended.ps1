<#
EXTENDED SECURITY REPORT — 5 DAYS (NO SUCCESSFUL LOGONS SECTION)
Collects:
- Failed logons (4625)
- RDP logons (1149 + 4624 type 10)
- Account lockouts (4740)
- AD changes (4720,4722,4723,4724,4725,4726,4738,4728–4733)
- LOG CLEAR EVENTS (Security 1102, System 104)
- AUDIT / SECURITY POLICY CHANGES (4719,4739)
- LOCAL ADMINISTRATORS GROUP CHANGES (4732,4733 for S-1-5-32-544)
- WinRM events
- Kerberos errors
- Service start/stop events (7036)
- USB events
- Network config changes
- PowerShell ScriptBlock logs
Output: C:\Windows\database\log\security-extended.txt
#>

[CmdletBinding()]
param()

$DaysBack = 5
$OutFile  = "C:\Windows\database\log\security-extended.txt"

# Create directory
$OutDir = Split-Path $OutFile -Parent
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$now   = Get-Date
$since = $now.AddDays(-$DaysBack)

function SafeEvent {
    param($filter)
    try { Get-WinEvent -FilterHashtable $filter -ErrorAction Stop }
    catch { @() }
}

$report = @()
$report += "=============== EXTENDED SECURITY REPORT ==============="
$report += "Generated: $now"
$report += "Range: $since  ->  $now"
$report += "========================================================"
$report += ""

# --------------------------------------------------------------------
# FETCH 4624 ONLY FOR RDP (DO NOT PRINT GENERAL LOGONS)
# --------------------------------------------------------------------
$okLogons = SafeEvent @{LogName='Security'; ID=4624; StartTime=$since}

# --------------------------------------------------------------------
# FAILED LOGONS (4625)
# --------------------------------------------------------------------
$report += "=== FAILED LOGONS (4625) ==="
$failLogons = SafeEvent @{LogName='Security'; ID=4625; StartTime=$since}
if ($failLogons.Count -eq 0) {
    $report += "No failed logons."
} else {
    foreach ($ev in $failLogons) {
        $msg = $ev.Message

        $user = "Unknown"
        if ($msg -match "Account Name:\s+(.+?)\s+Account Domain") {
            $user = $matches[1].Trim()
        }

        $ip = "Unknown"
        if ($msg -match "Source Network Address:\s+(\S+)") {
            $ip = $matches[1]
        }

        if ($user -eq "Unknown" -and $ip -eq "Unknown") { continue }

        $report += "[$($ev.TimeCreated)] USER=$user IP=$ip"
    }
}
$report += ""

# --------------------------------------------------------------------
# RDP LOGONS (1149 + 4624 type 10)
# --------------------------------------------------------------------
$report += "=== RDP LOGONS ==="
$rdp1 = SafeEvent @{LogName='Security'; ID=1149; StartTime=$since}
$rdp2 = $okLogons | Where-Object { $_.Message -match "Logon Type:\s+10" }

if (($rdp1 + $rdp2).Count -eq 0) {
    $report += "No RDP logons in this period."
} else {
    foreach ($ev in $rdp1 + $rdp2) {
        $msg = $ev.Message

        $user = "Unknown"
        if ($msg -match "Account Name:\s+(.+?)\s+Account Domain") {
            $user = $matches[1].Trim()
        }
        if ($user -eq "Unknown") { continue }

        $ws = "Unknown"
        if ($msg -match "Workstation Name:\s+(\S+)") {
            $ws = $matches[1]
        }

        $report += "[$($ev.TimeCreated)] RDP USER=$user WORKSTATION=$ws"
    }
}
$report += ""

# --------------------------------------------------------------------
# ACCOUNT LOCKOUTS (4740)
# --------------------------------------------------------------------
$report += "=== ACCOUNT LOCKOUTS (4740) ==="
$locks = SafeEvent @{LogName='Security'; ID=4740; StartTime=$since}
if ($locks.Count -eq 0) {
    $report += "No account lockouts."
} else {
    foreach ($ev in $locks) {
        $msg = $ev.Message
        $user = "Unknown"
        if ($msg -match "Account Name:\s+(.+?)\s+Additional") {
            $user = $matches[1].Trim()
        }
        if ($user -eq "Unknown") { continue }

        $report += "[$($ev.TimeCreated)] LOCKOUT USER=$user"
    }
}
$report += ""

# --------------------------------------------------------------------
# AD ACCOUNT CHANGES
# --------------------------------------------------------------------
$report += "=== AD ACCOUNT CHANGES ==="
$adIDs = 4720,4722,4723,4724,4725,4726,4738,4728,4729,4730,4731,4732,4733
$adEvents = SafeEvent @{LogName='Security'; ID=$adIDs; StartTime=$since}
if ($adEvents.Count -eq 0) {
    $report += "No AD account changes."
} else {
    foreach ($ev in $adEvents) {
        $msg = $ev.Message
        $user = "Unknown"
        if ($msg -match "Target Account:\s*[\r\n]+.*Account Name:\s+(.+?)\s") {
            $user = $matches[1].Trim()
        }
        if ($user -eq "Unknown") { continue }

        $report += "[$($ev.TimeCreated)] AD EVENTID=$($ev.Id) USER=$user"
    }
}
$report += ""

# --------------------------------------------------------------------
# LOG CLEAR EVENTS (Security 1102, System 104)
# --------------------------------------------------------------------
$report += "=== LOG CLEAR EVENTS ==="
$secClears = SafeEvent @{LogName='Security'; ID=1102; StartTime=$since}
$sysClears = SafeEvent @{LogName='System';   ID=104;  StartTime=$since}
$logClearLines = @()

foreach ($ev in $secClears) {
    $msg = $ev.Message
    $who = "Unknown"
    if ($msg -match "Subject:\s*[\r\n]+.*Account Name:\s+(.+?)\s") {
        $who = $matches[1].Trim()
    }
    if ($who -eq "Unknown") { continue }
    $logClearLines += "[$($ev.TimeCreated)] SECURITY LOG CLEARED BY=$who"
}
foreach ($ev in $sysClears) {
    $msg = $ev.Message
    $who = "Unknown"
    if ($msg -match "by:\s+(.+)$") {
        $who = $matches[1].Trim()
    }
    if ($who -eq "Unknown") { continue }
    $logClearLines += "[$($ev.TimeCreated)] SYSTEM LOG CLEARED BY=$who"
}

if ($logClearLines.Count -eq 0) {
    if ($secClears.Count -eq 0 -and $sysClears.Count -eq 0) {
        $report += "No log clear events in this period."
    } else {
        $report += "Log clear events detected, but user name could not be identified."
    }
} else {
    $report += $logClearLines
}
$report += ""

# --------------------------------------------------------------------
# AUDIT / SECURITY POLICY CHANGES (4719, 4739)
# --------------------------------------------------------------------
$report += "=== AUDIT / SECURITY POLICY CHANGES ==="
$polIds    = 4719,4739
$polEvents = SafeEvent @{LogName='Security'; ID=$polIds; StartTime=$since}
$polLines  = @()

foreach ($ev in $polEvents) {
    $msg  = $ev.Message
    $who  = "Unknown"
    if ($msg -match "Subject:\s*[\r\n]+.*Account Name:\s+(.+?)\s") {
        $who = $matches[1].Trim()
    }
    if ($who -eq "Unknown") { continue }

    $polLines += "[$($ev.TimeCreated)] POLICY EVENTID=$($ev.Id) BY=$who"
}

if ($polLines.Count -eq 0) {
    if ($polEvents.Count -eq 0) {
        $report += "No audit/security policy changes in this period."
    } else {
        $report += "Policy change events detected, but user name could not be identified."
    }
} else {
    $report += $polLines
}
$report += ""

# --------------------------------------------------------------------
# LOCAL ADMINISTRATORS GROUP CHANGES (4732/4733, S-1-5-32-544)
# --------------------------------------------------------------------
$report += "=== LOCAL ADMINISTRATORS GROUP CHANGES ==="
$admEvents   = SafeEvent @{LogName='Security'; ID=@(4732,4733); StartTime=$since}
$admFiltered = @()

foreach ($ev in $admEvents) {
    $msg = $ev.Message

    if ($msg -notmatch "S-1-5-32-544") { continue }

    $member = "Unknown"
    if ($msg -match "Member Name:\s+(.+?)\s+Member ID") {
        $member = $matches[1].Trim()
    }

    $who = "Unknown"
    if ($msg -match "Subject:\s*[\r\n]+.*Account Name:\s+(.+?)\s") {
        $who = $matches[1].Trim()
    }

    if ($member -eq "Unknown" -and $who -eq "Unknown") { continue }

    $action = if ($ev.Id -eq 4732) { "ADDED" } else { "REMOVED" }

    # ???????????? ??????: ?????????? ?????????????? ?????? ?????? ????????????
    $admFiltered += ("[{0}] ADMIN {1}: {2} BY={3}" -f $ev.TimeCreated, $action, $member, $who)
}

if ($admFiltered.Count -eq 0) {
    if ($admEvents.Count -eq 0) {
        $report += "No local Administrators group changes in this period."
    } else {
        $report += "Administrators group change events detected, but could not be fully identified."
    }
} else {
    $report += $admFiltered
}
$report += ""

# --------------------------------------------------------------------
# WINRM EVENTS
# --------------------------------------------------------------------
$report += "=== WINRM EVENTS ==="
$wm = SafeEvent @{LogName='Microsoft-Windows-WinRM/Operational'; StartTime=$since}
if ($wm.Count -eq 0) {
    $report += "No WinRM events in this period."
} else {
    foreach ($ev in $wm) {
        $short = $ev.Message.Substring(0,[Math]::Min(200,$ev.Message.Length))
        $report += "[$($ev.TimeCreated)] WinRM ID=$($ev.Id) $short"
    }
}
$report += ""

# --------------------------------------------------------------------
# KERBEROS ERRORS
# --------------------------------------------------------------------
$report += "=== KERBEROS ERRORS ==="
$kerb = SafeEvent @{LogName='System'; ProviderName='Kerberos'; StartTime=$since}
if ($kerb.Count -eq 0) {
    $report += "No Kerberos events in this period."
} else {
    foreach ($ev in $kerb) {
        $report += "[$($ev.TimeCreated)] $($ev.Message)"
    }
}
$report += ""

# --------------------------------------------------------------------
# SERVICE START/STOP (7036)
# --------------------------------------------------------------------
$report += "=== SERVICE START/STOP (7036) ==="
$svc = SafeEvent @{LogName='System'; ID=7036; StartTime=$since}
if ($svc.Count -eq 0) {
    $report += "No service state changes in this period."
} else {
    foreach ($ev in $svc) {
        $report += "[$($ev.TimeCreated)] $($ev.Message)"
    }
}
$report += ""

# --------------------------------------------------------------------
# USB EVENTS
# --------------------------------------------------------------------
$report += "=== USB EVENTS ==="
$usb = SafeEvent @{LogName='System'; ProviderName='Microsoft-Windows-DriverFrameworks-UserMode'; StartTime=$since}
if ($usb.Count -eq 0) {
    $report += "No USB-related events in this period."
} else {
    foreach ($ev in $usb) {
        $txt = $ev.Message.Substring(0,[Math]::Min(200,$ev.Message.Length))
        $report += "[$($ev.TimeCreated)] USB: $txt"
    }
}
$report += ""

# --------------------------------------------------------------------
# NETWORK CONFIG CHANGES
# --------------------------------------------------------------------
$report += "=== NETWORK CONFIG CHANGES ==="
$net = SafeEvent @{LogName='System'; ProviderName='Tcpip'; StartTime=$since}
if ($net.Count -eq 0) {
    $report += "No TCP/IP events in this period."
} else {
    foreach ($ev in $net) {
        $txt = $ev.Message.Substring(0,[Math]::Min(200,$ev.Message.Length))
        $report += "[$($ev.TimeCreated)] NET: $txt"
    }
}
$report += ""

# --------------------------------------------------------------------
# POWERSHELL SCRIPTBLOCK LOGS
# --------------------------------------------------------------------
$report += "=== POWERSHELL SCRIPTBLOCK LOGS ==="
$ps = SafeEvent @{LogName='Microsoft-Windows-PowerShell/Operational'; StartTime=$since}
if ($ps.Count -eq 0) {
    $report += "No PowerShell ScriptBlock events in this period."
} else {
    foreach ($ev in $ps) {
        $txt = $ev.Message.Substring(0,[Math]::Min(300,$ev.Message.Length))
        $report += "[$($ev.TimeCreated)] PS SCRIPTBLOCK: $txt"
    }
}
$report += ""

# --------------------------------------------------------------------
# WRITE FILE
# --------------------------------------------------------------------
Set-Content -Path $OutFile -Value $report -Encoding UTF8
