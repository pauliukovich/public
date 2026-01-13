param(
    [string]$Computer,          # Target computer name; if empty, will be prompted
    [int]$IntervalSec = 5,      # Seconds between checks/pings
    [int]$PingCount = 1,        # ICMP echo count per iteration
    [switch]$PopupOnLogout      # Show a popup on logout (tries WPF MessageBox)
)

# If no computer name provided, ask interactively
if (-not $Computer -or $Computer.Trim() -eq '') {
    $Computer = Read-Host 'Enter computer name (e.g., SALA31-LAP)'
}

Write-Host "Target: ${Computer}. Interval: ${IntervalSec}s. PingCount: ${PingCount}" -ForegroundColor Cyan

# -------------------- Helpers: who is interactively logged on --------------------
function Get-InteractiveUser_CIM {
    param([string]$ComputerName)
    try {
        # Win32_ComputerSystem.UserName returns DOMAIN\User for the interactive session
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $ComputerName -ErrorAction Stop
        return $cs.UserName
    } catch { return $null }
}

function Get-InteractiveUser_WMI {
    param([string]$ComputerName)
    try {
        # Legacy WMI (DCOM); useful when WinRM is blocked but DCOM is open
        $cs = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $ComputerName -ErrorAction Stop
        return $cs.UserName
    } catch { return $null }
}

function Get-InteractiveUser_quser {
    param([string]$ComputerName)
    try {
        # Fallback: parse `quser /server:<host>` output; pick Active/Console session
        $raw = (quser /server:$ComputerName) 2>$null
        if (-not $raw) { return $null }
        $lines = $raw -split "`n" | Where-Object { $_ -and ($_ -notmatch 'USERNAME') }
        foreach ($ln in $lines) {
            $parts = $ln -replace '^\s+','' -split '\s+'
            if ($parts.Count -ge 2) {
                $username = $parts[0]
                $state    = $parts[-2]       # e.g., Active / Disc / Idle
                if ($state -match 'Active|Console') { return $username }
            }
        }
        return $null
    } catch { return $null }
}

function Get-InteractiveUser {
    param([string]$ComputerName)
    # Try CIM -> WMI -> quser in order
    $u = Get-InteractiveUser_CIM  -ComputerName $ComputerName
    if (-not $u) { $u = Get-InteractiveUser_WMI   -ComputerName $ComputerName }
    if (-not $u) { $u = Get-InteractiveUser_quser -ComputerName $ComputerName }
    return $u
}

# -------------------- Notification helpers --------------------
function Show-LogoutNotification {
    param(
        [string]$ComputerName,
        [string]$InitialUser,
        [string]$CurrentUser # may be $null on real logout
    )
    $msgTitle = "Logout detected"
    if ($CurrentUser) {
        $msgBody  = "On ${ComputerName}, user changed from ${InitialUser} to ${CurrentUser}."
    } else {
        $msgBody  = "On ${ComputerName}, user ${InitialUser} logged off."
    }

    # 1) Try a WPF MessageBox (Windows PowerShell/PowerShell 7 on full .NET)
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show($msgBody, $msgTitle, 'OK', 'Information') | Out-Null
        return
    } catch {
        # 2) Fallback: console bell + big banner
        try { [console]::Beep(1000,300) } catch {}
        Write-Host ""
        Write-Host "==== ${msgTitle} ====" -ForegroundColor Yellow
        Write-Host $msgBody -ForegroundColor Yellow
        Write-Host "=====================" -ForegroundColor Yellow
    }
}

# -------------------- First reachability probe (informational) --------------------
$firstPing = Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction SilentlyContinue
if (-not $firstPing) {
    Write-Host "Heads-up: ${Computer} is not responding to ICMP right now. Continuing anyway." -ForegroundColor DarkYellow
}

# -------------------- Get initial interactive user --------------------
$initialUser = Get-InteractiveUser -ComputerName $Computer
if (-not $initialUser) {
    Write-Host "Failed to obtain interactive user on ${Computer}. Check rights/firewall/WinRM/DCOM/RDS." -ForegroundColor Red
    exit 1
}

Write-Host "Interactive user on ${Computer}: ${initialUser}" -ForegroundColor Green
Write-Host "Will keep pinging every ${IntervalSec}s until ${initialUser} logs off or the user changes." -ForegroundColor Cyan

# -------------------- Main loop --------------------
try {
    while ($true) {
        # Ping the host (quiet = Boolean)
        $alive = Test-Connection -ComputerName $Computer -Count $PingCount -Quiet -ErrorAction SilentlyContinue
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        if ($alive) {
            Write-Host "$stamp PING OK -> ${Computer} reachable."
        } else {
            Write-Host "$stamp PING FAIL -> ${Computer} unreachable."
        }

        Start-Sleep -Seconds $IntervalSec

        # Re-check interactive user
        $currentUser = Get-InteractiveUser -ComputerName $Computer

        # Case A: No interactive user -> logged off
        if (-not $currentUser) {
            $time = Get-Date -Format 'HH:mm:ss'
            Write-Host "$time User logged off (no interactive session). Stopping." -ForegroundColor Yellow
            if ($PopupOnLogout) { Show-LogoutNotification -ComputerName $Computer -InitialUser $initialUser -CurrentUser $null }
            break
        }

        # Case B: Different user -> session changed
        if ($currentUser -ne $initialUser) {
            $time = Get-Date -Format 'HH:mm:ss'
            Write-Host "$time User changed: ${currentUser} (was ${initialUser}). Stopping." -ForegroundColor Yellow
            if ($PopupOnLogout) { Show-LogoutNotification -ComputerName $Computer -InitialUser $initialUser -CurrentUser $currentUser }
            break
        }
    }
}
catch {
    Write-Host "Runtime error: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host "Done." -ForegroundColor Green
}
