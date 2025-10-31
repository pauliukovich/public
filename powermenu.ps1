# Remote Control Menu (PowerShell 7)
# Choose one PC or ALL -> pick action -> execute -> repeat
# Requires WinRM on targets and your rights to manage them.

# --- List of computers ---
$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
)

# --- Helpers ---
function Test-RemoteReady {
    param([string]$Computer)
    if (-not (Test-Connection -ComputerName $Computer -Count 1 -Quiet)) { return $false }
    try { Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

function Invoke-RemoteLogoff {
    param([string]$Computer)

    # 1) CIM Logoff (Flags=0)
    try {
        $cs = New-CimSession -ComputerName $Computer -ErrorAction Stop
        $os = Get-CimInstance -CimSession $cs -ClassName Win32_OperatingSystem -ErrorAction Stop
        $res = Invoke-CimMethod -InputObject $os -MethodName Win32Shutdown -Arguments @{ Flags = 0 } -ErrorAction Stop
        Remove-CimSession $cs
        if ($res.ReturnValue -eq 0) { return $true }
    } catch { }

    # 2) Fallback: quser/logoff by session ID
    try {
        $result = Invoke-Command -ComputerName $Computer -ErrorAction Stop -ScriptBlock {
            $lines = (quser) 2>$null
            if (-not $lines) { return "NO_SESSIONS" }

            $sessions = foreach ($line in $lines) {
                if ($line -match '^\s*(\S+)\s+(\S+|\s)\s+(\d+)\s+(\S+)\s+(.+)$') {
                    [pscustomobject]@{
                        USERNAME    = $matches[1]
                        SESSIONNAME = $matches[2]
                        ID          = [int]$matches[3]
                        STATE       = $matches[4]
                        REST        = $matches[5]
                    }
                }
            }

            $active = $sessions | Where-Object { $_.USERNAME -and $_.STATE -match 'Active|Aktywna' }
            if (-not $active) { return "NO_ACTIVE" }

            foreach ($s in $active) { logoff $s.ID /V 2>$null }
            return "OK"
        }

        if ($result -eq "OK" -or $result -in @("NO_ACTIVE","NO_SESSIONS")) { return $true }
    } catch {
        return $false
    }

    return $false
}

function Invoke-RemoteAction {
    param(
        [string]$Computer,
        [ValidateSet('Shutdown','Reboot','Logoff')]
        [string]$Action
    )

    if (-not (Test-RemoteReady $Computer)) {
        Write-Host ("{0}: UNREACHABLE (ping/WSMan)" -f $Computer) -ForegroundColor Red
        return @{ Computer=$Computer; Action=$Action; Result='UNREACHABLE' }
    }

    try {
        switch ($Action) {
            'Shutdown' {
                Invoke-Command -ComputerName $Computer -ScriptBlock { Stop-Computer -Force }
                Write-Host ("{0}: Shutdown sent" -f $Computer) -ForegroundColor Green
                return @{ Computer=$Computer; Action=$Action; Result='OK' }
            }
            'Reboot' {
                Invoke-Command -ComputerName $Computer -ScriptBlock { Restart-Computer -Force }
                Write-Host ("{0}: Reboot sent" -f $Computer) -ForegroundColor Green
                return @{ Computer=$Computer; Action=$Action; Result='OK' }
            }
            'Logoff' {
                if (Invoke-RemoteLogoff -Computer $Computer) {
                    Write-Host ("{0}: Logoff completed (or no active users)" -f $Computer) -ForegroundColor Green
                    return @{ Computer=$Computer; Action=$Action; Result='OK' }
                } else {
                    Write-Host ("{0}: Logoff FAILED" -f $Computer) -ForegroundColor Red
                    return @{ Computer=$Computer; Action=$Action; Result='FAIL' }
                }
            }
        }
    } catch {
        $errMsg = $_.Exception.Message
        Write-Host ("{0}: ERROR - {1}" -f $Computer, $errMsg) -ForegroundColor Red
        return @{ Computer=$Computer; Action=$Action; Result='ERROR'; Message=$errMsg }
    }
}

# --- Main loop ---
while ($true) {
    Write-Host "`nSelect target (0 = Exit, A = ALL):" -ForegroundColor Cyan
    for ($i=0; $i -lt $Computers.Count; $i++) { Write-Host "$($i+1)) $($Computers[$i])" }
    Write-Host "A) ALL (broadcast to all listed hosts)"

    $sel = Read-Host "Enter choice"
    if ($sel -eq '0') { break }

    $targets = @()
    if ($sel -match '^(A|ALL)$') {
        $targets = $Computers
        Write-Host "Selected: ALL hosts ($($targets.Count))" -ForegroundColor Yellow
    } else {
        $Computer = $Computers[[int]$sel-1]
        if (-not $Computer) { Write-Host "Invalid selection." -ForegroundColor Red; continue }
        $targets = @($Computer)
        Write-Host ("Selected: {0}" -f $Computer) -ForegroundColor Green
    }

    Write-Host "`nSelect action:" -ForegroundColor Cyan
    Write-Host "1) Shutdown"
    Write-Host "2) Reboot"
    Write-Host "3) Logoff"
    Write-Host "0) Back"
    $actSel = Read-Host "Enter number"

    $actionName = switch ($actSel) {
        1 {'Shutdown'}
        2 {'Reboot'}
        3 {'Logoff'}
        0 { continue }
        default { $null }
    }
    if (-not $actionName) { Write-Host "Invalid action." -ForegroundColor Red; continue }

    # Safety confirm for ALL + destructive actions
    if ($targets.Count -gt 1 -and $actionName -in @('Shutdown','Reboot')) {
        $confirm = Read-Host ("Confirm {0} on ALL {1} hosts? (Y/N)" -f $actionName, $targets.Count)
        if ($confirm -notin @('Y','y')) { Write-Host "Cancelled." -ForegroundColor Yellow; continue }
    }

    Write-Host ("`nExecuting {0} ..." -f $actionName) -ForegroundColor Cyan

    $results = @()
    foreach ($t in $targets) {
        $results += Invoke-RemoteAction -Computer $t -Action $actionName
    }

    # Summary
    $ok     = ($results | Where-Object { $_.Result -eq 'OK' }).Count
    $fail   = ($results | Where-Object { $_.Result -eq 'FAIL' }).Count
    $err    = ($results | Where-Object { $_.Result -eq 'ERROR' }).Count
    $unreach= ($results | Where-Object { $_.Result -eq 'UNREACHABLE' }).Count

    Write-Host ("`nSummary: OK={0}  FAIL={1}  ERROR={2}  UNREACHABLE={3}" -f $ok,$fail,$err,$unreach) -ForegroundColor Magenta
}
