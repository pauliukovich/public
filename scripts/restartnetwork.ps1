# Restart-NetworkAdapters.ps1
# PowerShell 5 compatible
# Description: disable each network adapter, wait 5 seconds, then enable it again.
# Uses: Get-NetAdapter / Disable-NetAdapter / Enable-NetAdapter

[CmdletBinding()]
param(
    [int] $WaitSeconds = 5,
    [string] $LogFile = "C:\Temp\network-adapters-restart.log"
)

function Write-Log {
    param($Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$ts`t$Message"
    # write to console and to file (create folder if missing)
    if (-not (Test-Path (Split-Path $LogFile))) {
        New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
    }
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $line
}

# Elevation check
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Host "ERROR: Script requires Administrator privileges. Run in elevated PowerShell." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR: Unable to verify elevation. Exiting." -ForegroundColor Red
    exit 1
}

Write-Log "=== START network adapters restart sequence ==="

# Get all network adapters excluding loopback and Bluetooth if desired.
# Adjust filter if you want only physical adapters.
$adapters = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -notmatch 'Loopback' -and $_.Name -notmatch 'Bluetooth'
}

if (-not $adapters) {
    Write-Log "No network adapters found. Exiting."
    exit 0
}

foreach ($if in $adapters) {
    $name = $if.Name
    $status = $if.Status
    Write-Log "Processing adapter: $name (Status: $status, AdminStatus: $($if.AdminStatus))"
    try {
        # Disable adapter (suppress confirmation)
        Write-Log "Disabling adapter: $name"
        Disable-NetAdapter -Name $name -Confirm:$false -ErrorAction Stop

        Start-Sleep -Seconds $WaitSeconds

        Write-Log "Enabling adapter: $name"
        Enable-NetAdapter -Name $name -Confirm:$false -ErrorAction Stop

        # Optional: wait until adapter state is Up (timeout)
        $timeout = 30
        $elapsed = 0
        while ($elapsed -lt $timeout) {
            $cur = Get-NetAdapter -Name $name -ErrorAction SilentlyContinue
            if ($cur -and $cur.Status -eq 'Up') {
                Write-Log "Adapter $name is Up."
                break
            }
            Start-Sleep -Seconds 1
            $elapsed += 1
        }
        if ($elapsed -ge $timeout) {
            Write-Log "Warning: Adapter $name did not reach 'Up' within $timeout seconds."
        }
    } catch {
        Write-Log "ERROR processing $name : $($_.Exception.Message)"
    }
}

Write-Log "=== FINISHED network adapters restart sequence ==="