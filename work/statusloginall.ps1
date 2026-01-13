<#
  Get-AD-LoggedUsers-ExactList.ps1  (PowerShell 7)
  Purpose:
    - Check ONLY the fixed list of computers below (case-insensitive).
    - For each host, list ALL logged-on users via `quser` (with hard timeout).
    - Resolve DisplayName + samAccountName; try to get precise Logon Time (with seconds) via WMI (DCOM).
    - Output a table; optional CSV; keep console open at the end (interactive mode).

  Requirements:
    - PowerShell 7 (pwsh), RSAT ActiveDirectory module.
    - Rights to query remote stations. For precise logon time, remote WMI (DCOM) must be allowed.
#>

[CmdletBinding()]
param(
  [int]$RpcTimeoutSec = 3,                 # hard timeout for `quser` per host (seconds)
  [int]$CimTimeoutSec = 4,                 # CIM (DCOM) per-host operation time budget
  [string]$OutCsv     = ""                 # optional CSV path; if set => non-interactive mode
)

# --- Import AD module (fail fast) ---
try { Import-Module ActiveDirectory -ErrorAction Stop }
catch {
  Write-Error "ActiveDirectory (RSAT) missing or not running in PS7."
  exit 1
}

# --- Exact target list (EDIT here if the roster changes) ---
$TargetComputers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
)

# --- Room/floor helpers ---
function Get-RoomNumber {
  <# Extract room number from names like SALA21-LAP, SALA33-PC. Returns [int]? #>
  param([string]$ComputerName)
  $m = [regex]::Match($ComputerName, 'SALA(?<num>\d+)', 'IgnoreCase')
  if ($m.Success) { [int]$m.Groups['num'].Value } else { $null }
}

function Get-FloorText {
  <#
    Map room number to floor (adjust if needed):
      10–19 -> First floor
      20–29 -> Second floor
      30–39 -> Third floor
      else  -> Unknown
  #>
  param([int]$RoomNumber)
  if     ($RoomNumber -ge 10 -and $RoomNumber -le 19) { 'First floor' }
  elseif ($RoomNumber -ge 20 -and $RoomNumber -le 29) { 'Second floor' }
  elseif ($RoomNumber -ge 30 -and $RoomNumber -le 39) { 'Third floor' }
  else { 'Unknown' }
}

# --- Safe `quser` with hard timeout (prevents hangs) ---
function Invoke-QuserSafe {
  param([string]$Computer, [int]$TimeoutSec)
  $sb = {
    param($c)
    try {
      quser /server:$c 2>&1 | ForEach-Object { $_.ToString() }
    } catch {
      @()
    }
  }
  $job = Start-Job -ScriptBlock $sb -ArgumentList $Computer
  try {
    if (-not (Wait-Job -Job $job -Timeout $TimeoutSec)) {
      Stop-Job $job -Force -ErrorAction SilentlyContinue
      Remove-Job $job -Force -ErrorAction SilentlyContinue
      return $null
    }
    $out = Receive-Job $job -ErrorAction SilentlyContinue
    ,$out
  }
  finally {
    if ($job -and $job.State -ne 'Removed') {
      Remove-Job $job -Force -ErrorAction SilentlyContinue | Out-Null
    }
  }
}

# --- Parse `quser` into entries (RawUser + Approx LogonTime) ---
function Parse-QuserEntries {
  <#
    Returns array of @{ RawUser; LogonTimeApprox }
    - RawUser: "DOMAIN\user" or "user"
    - LogonTimeApprox: [datetime]? parsed from quser (often without seconds)
  #>
  param([string[]]$RawLines)

  $out = New-Object System.Collections.Generic.List[object]
  if (-not $RawLines -or $RawLines.Count -lt 2) { return $out }

  $payload = $RawLines | Where-Object { $_.Trim() -ne '' } | Select-Object -Skip 1
  foreach ($ln in $payload) {
    $parts = ($ln -split '\s{2,}') | ForEach-Object { $_.Trim() }
    if ($parts.Count -lt 1) { continue }
    $rawUser = $parts[0]

    $logon = $null
    if ($parts.Count -ge 6) {
      $logonStr = ($parts[5..($parts.Count-1)] -join ' ')
      foreach ($fmt in @([System.Globalization.CultureInfo]::InvariantCulture, (Get-Culture))) {
        try {
          $logon = [datetime]::Parse($logonStr, $fmt)
          break
        } catch {}
      }
    }
    if ($rawUser -and $rawUser -notmatch '^(USERNAME|>)$') {
      $out.Add([pscustomobject]@{ RawUser=$rawUser; LogonTimeApprox=$logon }) | Out-Null
    }
  }

  # unique by RawUser, keep the newest approx time
  $uniq = @()
  foreach ($g in ($out | Group-Object RawUser)) {
    $latest = $g.Group | Sort-Object LogonTimeApprox -Descending | Select-Object -First 1
    $uniq += $latest
  }
  $uniq
}

# --- Resolve raw quser name to SAM + DisplayName ---
function Resolve-Login {
  param([string]$RawUser)

  if ([string]::IsNullOrWhiteSpace($RawUser)) {
    return [pscustomobject]@{ Login=''; User=''; Note='empty' }
  }

  $candidate = $RawUser
  if ($RawUser -like '*\*') {
    $null, $candidate = $RawUser -split '\\', 2
  }

  try {
    $u = Get-ADUser -Filter { SamAccountName -eq $candidate } -Properties DisplayName -ErrorAction Stop
    [pscustomobject]@{ Login=$u.SamAccountName; User=$u.DisplayName; Note='' }
  } catch {
    try {
      $ldap = "(|(sAMAccountName=$candidate)(userPrincipalName=$candidate))"
      $u = Get-ADUser -LDAPFilter $ldap -Properties DisplayName -ErrorAction Stop
      [pscustomobject]@{ Login=$u.SamAccountName; User=$u.DisplayName; Note='' }
    } catch {
      [pscustomobject]@{ Login=$candidate; User=$candidate; Note='not resolved in AD' }
    }
  }
}

# --- Get precise logon time with seconds via WMI (DCOM) ---
function Get-PreciseLogonTime {
  <#
    Returns [datetime]? of the latest interactive/remote-interactive logon for given SAM on remote host.
    If WMI/DCOM is blocked or nothing is found, returns $null.
  #>
  param(
    [string]$Computer,
    [string]$SamAccountName,
    [int]$TimeoutSec
  )
  try {
    $opt  = New-CimSessionOption -Protocol Dcom
    $sess = New-CimSession -ComputerName $Computer -SessionOption $opt -OperationTimeoutSec $TimeoutSec

    $acct = Get-CimInstance -CimSession $sess -ClassName Win32_Account -Filter "Name='$SamAccountName'" -OperationTimeoutSec $TimeoutSec
    if (-not $acct) {
      $sess | Remove-CimSession -ErrorAction SilentlyContinue
      return $null
    }

    $assoc = Get-CimAssociatedInstance -InputObject $acct -Association Win32_LoggedOnUser -CimSession $sess -OperationTimeoutSec $TimeoutSec
    if (-not $assoc) {
      $sess | Remove-CimSession -ErrorAction SilentlyContinue
      return $null
    }

    $times = @()
    foreach ($s in $assoc) {
      try {
        if ($s.PSObject.Properties.Match('LogonType').Count -gt 0 -and
            $s.PSObject.Properties.Match('StartTime').Count -gt 0) {
          if ($s.LogonType -in 2,10) {
            $dt = [System.Management.ManagementDateTimeConverter]::ToDateTime($s.StartTime)
            if ($dt) { $times += $dt }
          }
        }
      } catch { }
    }

    $sess | Remove-CimSession -ErrorAction SilentlyContinue
    if ($times.Count -gt 0) {
      ($times | Sort-Object -Descending | Select-Object -First 1)
    } else {
      $null
    }
  } catch {
    $null
  }
}

# --- Main: iterate fixed list, query users, resolve login + precise time ---
$Rows = New-Object System.Collections.Generic.List[object]

foreach ($pc in $TargetComputers) {
  $room  = Get-RoomNumber -ComputerName $pc
  $floor = if ($room) { Get-FloorText -RoomNumber $room } else { 'Unknown' }

  $raw = Invoke-QuserSafe -Computer $pc -TimeoutSec $RpcTimeoutSec
  if ($null -eq $raw) {
    Write-Host ("{0} (room {1}, {2}) -> timeout/no response" -f $pc, $room, $floor) -ForegroundColor DarkYellow
    $Rows.Add([pscustomobject]@{
      Computer  = $pc
      Room      = $room
      Floor     = $floor
      Login     = ''
      User      = ''
      LogonTime = ''
      Note      = 'no response/timeout'
    }) | Out-Null
    continue
  }

  $entries = Parse-QuserEntries -RawLines $raw
  if (-not $entries -or $entries.Count -eq 0) {
    Write-Host ("{0} (room {1}, {2}) -> no logged users" -f $pc, $room, $floor) -ForegroundColor Gray
    $Rows.Add([pscustomobject]@{
      Computer  = $pc
      Room      = $room
      Floor     = $floor
      Login     = ''
      User      = ''
      LogonTime = ''
      Note      = 'no logged users'
    }) | Out-Null
    continue
  }

  $inlineBits = @()
  foreach ($e in $entries) {
    $r = Resolve-Login -RawUser $e.RawUser
    $prec  = if ($r.Login) { Get-PreciseLogonTime -Computer $pc -SamAccountName $r.Login -TimeoutSec $CimTimeoutSec } else { $null }
    $logon = if ($prec) { $prec } elseif ($e.LogonTimeApprox) { $e.LogonTimeApprox } else { $null }

    $Rows.Add([pscustomobject]@{
      Computer  = $pc
      Room      = $room
      Floor     = $floor
      Login     = $r.Login
      User      = $r.User
      LogonTime = if ($logon) { $logon.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
      Note      = $r.Note
    }) | Out-Null

    if ($logon) {
      $inlineBits += ("{0} [{1:yyyy-MM-dd HH:mm:ss}]" -f $r.Login, $logon)
    } else {
      $inlineBits += $r.Login
    }
  }

  Write-Host ("{0} (room {1}, {2}) -> {3}" -f $pc, $room, $floor, ($inlineBits -join ', ')) -ForegroundColor Green
}

# --- Output table ---
"`nResult (per session):" | Write-Host -ForegroundColor Cyan
$Rows |
  Sort-Object Floor, Room, Computer, Login |
  Format-Table Computer, Room, Floor, Login, User, LogonTime, Note -AutoSize

# --- Optional CSV export (non-interactive mode for web / schedulers) ---
if ($OutCsv -and $OutCsv.Trim() -ne "") {
  try {
    $Rows | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Exported to CSV: $OutCsv" -ForegroundColor Cyan
  } catch {
    Write-Warning "CSV export failed: $($_.Exception.Message)"
  }
}

# --- Keep console open only in interactive mode ---
if (-not $OutCsv -or $OutCsv.Trim() -eq "") {
  Write-Host "`nDone. Press ENTER to exit." -ForegroundColor Yellow
  [void][System.Console]::ReadLine()
}
