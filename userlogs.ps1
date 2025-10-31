<# 
Get-UserActivity.ps1
Reads a domain user's activity timeline across workstations (Security + RDS logs),
adds DC-side auth traces as fallback, enforces per-host timeouts, and can export CSV/HTML.

USAGE EXAMPLES
  .\Get-UserActivity.ps1 -User serwis
  .\Get-UserActivity.ps1 -User serwis -SinceHours 48 -Computers SALA21-LAP,SALA22-LAP -PerHostTimeoutSec 25
  .\Get-UserActivity.ps1 -User serwis -Csv out.csv -Html out.html

REQUIREMENTS
  - Run as an account that can read Security logs on targets (Event Log Readers / SeSecurityPrivilege)
  - WinRM enabled on targets
  - PowerShell 5.1+ (compatible with 7.x)
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$User,

  # How far back to search
  [int]$SinceHours = 24,

  # Workstation list (edit to your estate or pass explicitly)
  [string[]]$Computers = @(
    'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
    'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
    'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
    'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
    'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
    'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
  ),

  # DCs for fallback auth traces
  [string[]]$DomainControllers = @('DC01','DC02'),

  # Per-host timeout (seconds) to avoid hanging on slow/unreachable machines
  [int]$PerHostTimeoutSec = 15,

  # Optional exports
  [string]$Csv,
  [string]$Html
)

# --- helpers -------------------------------------------------------------
function Write-Green([string]$t){ Write-Host $t -ForegroundColor Green }

# Logon type code -> label
$LogonTypeMap = @{
  2='Interactive (Console)';3='Network';4='Batch';5='Service';7='Unlock';
  8='NetworkCleartext';9='NewCredentials (RunAs)';10='RemoteInteractive (RDP)';11='CachedInteractive'
}

# Time boundary
$Since = (Get-Date).AddHours(-[math]::Abs($SinceHours))

# --- worker to collect from a single computer (runs inside a job) -------
$GetFromComputer = {
  param($Computer,$User,$Since,$LogonTypeMap)

  $events = @()

  # Security log: logon/logoff/lock/unlock
  try {
    $secIds = 4624,4634,4647,4800,4801
    Get-WinEvent -ComputerName $Computer -FilterHashtable @{LogName='Security'; Id=$secIds; StartTime=$Since} -ErrorAction Stop |
      Where-Object { $_.Properties.Value -match "(?i)\b$([regex]::Escape($User))\b" } |
      ForEach-Object {
        $xml=[xml]$_.ToXml()
        $lt  = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'LogonType'} | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
        $ip  = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'IpAddress'} | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
        $ws  = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'WorkstationName'} | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
        $usr = ($xml.Event.EventData.Data | Where-Object {$_.Name -match 'TargetUserName|SubjectUserName'} | Select-Object -First 1 -ExpandProperty '#text' -ErrorAction Ignore)
        $evt = switch ($_.Id) {
          4624 {'LOGON'}
          4634 {'LOGOFF'}
          4647 {'USER-LOGOFF'}
          4800 {'LOCK'}
          4801 {'UNLOCK'}
          default { "SEC $($_.Id)" }
        }
        [pscustomobject]@{
          Time       = $_.TimeCreated
          Computer   = $Computer
          Event      = $evt
          Username   = $usr
          LogonType  = if($lt){ $LogonTypeMap[[int]$lt] } else { $null }
          IP         = if($ip -and $ip -ne '-'){$ip}else{$null}
          Workstation= $ws
          Source     = 'Security'
          EventId    = $_.Id
          SessionId  = $null
        }
      }
  } catch {}

  # RDS/LSM: connect/disconnect/reconnect/logoff
  try {
    $rdsLog = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
    Get-WinEvent -ComputerName $Computer -FilterHashtable @{LogName=$rdsLog; Id=21,23,24,25; StartTime=$Since} -ErrorAction Stop |
      Where-Object { $_.Properties.Value -match "(?i)\b$([regex]::Escape($User))\b" } |
      ForEach-Object {
        $xml=[xml]$_.ToXml()
        $u   = ($xml.Event.EventData.Data | Select-Object -First 1 -ExpandProperty '#text' -ErrorAction Ignore)
        $sid = ($xml.Event.EventData.Data | Select-Object -Last 1  -ExpandProperty '#text' -ErrorAction Ignore)
        $evt = switch ($_.Id) {
          21 {'RDS LOGON'}
          23 {'RDS LOGOFF'}
          24 {'RDS DISCONNECT'}
          25 {'RDS RECONNECT'}
          default { "RDS $($_.Id)" }
        }
        [pscustomobject]@{
          Time       = $_.TimeCreated
          Computer   = $Computer
          Event      = $evt
          Username   = $u
          LogonType  = 'RemoteInteractive (RDP)'
          IP         = $null
          Workstation= $null
          Source     = 'RDS LSM'
          EventId    = $_.Id
          SessionId  = $sid
        }
      }
  } catch {}

  $events
}

# --- DC fallback (fixed: no '??' and no $host name clash) ----------------
function Get-DCAuth {
  param($DCs,$User,$Since)
  $res=@()
  foreach($dc in $DCs){
    try{
      Get-WinEvent -ComputerName $dc -FilterHashtable @{LogName='Security'; Id=4768,4776; StartTime=$Since} -ErrorAction Stop |
        Where-Object { $_.Properties.Value -match "(?i)\b$([regex]::Escape($User))\b" } |
        ForEach-Object {
          $xml = [xml]$_.ToXml()
          if ($_.Id -eq 4768) {
            $acct       = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'} | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
            $clientIp   = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'ClientAddress'}  | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
            $clientName = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'ClientName'}     | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
            [pscustomobject]@{
              Time        = $_.TimeCreated
              Computer    = if($clientName){ $clientName } else { '(unknown)' }
              Event       = 'KERBEROS TGT'
              Username    = $acct
              LogonType   = 'Kerberos'
              IP          = if($clientIp -and $clientIp -ne '::1'){ $clientIp } else { $null }
              Workstation = $null
              Source      = "DC:$dc"
              EventId     = $_.Id
              SessionId   = $null
            }
          } else {
            $acct = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'TargetUserName'} | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
            $ws   = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'Workstation'}   | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
            $st   = ($xml.Event.EventData.Data | Where-Object {$_.Name -eq 'Status'}        | Select-Object -ExpandProperty '#text' -ErrorAction Ignore)
            $evt  = if($st -eq '0x0') { 'NTLM VALIDATION' } else { "NTLM FAILURE ($st)" }
            [pscustomobject]@{
              Time        = $_.TimeCreated
              Computer    = if($ws){ $ws } else { '(unknown)' }
              Event       = $evt
              Username    = $acct
              LogonType   = 'NTLM'
              IP          = $null
              Workstation = $null
              Source      = "DC:$dc"
              EventId     = $_.Id
              SessionId   = $null
            }
          }
        }
    } catch {}
  }
  $res
}

# --- run collection with per-host timeout --------------------------------
Write-Green ("Scanning user '{0}' since {1} ..." -f $User, $Since.ToString('yyyy-MM-dd HH:mm:ss'))

$jobs = foreach($c in $Computers){
  Start-Job -Name $c -ScriptBlock $GetFromComputer -ArgumentList $c,$User,$Since,$LogonTypeMap
}

$all = @()
foreach($j in $jobs){
  $ok = Wait-Job $j -Timeout $PerHostTimeoutSec
  if($ok){
    $all += Receive-Job $j
  } else {
    Write-Green ("[SKIP] {0} timed out after {1}s" -f $j.Name,$PerHostTimeoutSec)
    Stop-Job $j -ErrorAction SilentlyContinue | Out-Null
  }
  Remove-Job $j -Force | Out-Null
}

# add DC traces only for hosts that didn't yield direct workstation events
$workHosts = $all.Computer | Sort-Object -Unique
$dc = Get-DCAuth -DCs $DomainControllers -User $User -Since $Since | Where-Object { $_.Computer -notin $workHosts }
$all += $dc

$all = $all | Sort-Object Time, Computer

# --- render ---------------------------------------------------------------
if(-not $all){
  Write-Green ("No events for '{0}' found in the last {1} hour(s)." -f $User,$SinceHours)
  return
}

Write-Green ""
Write-Green "==================== USER ACTIVITY REPORT ===================="
Write-Green ("User        : {0}" -f $User)
Write-Green ("Time window : {0} -> {1}" -f $Since.ToString("yyyy-MM-dd HH:mm:ss"), (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
Write-Green ("Hosts       : {0}" -f ($Computers -join ', '))
Write-Green "Sources     : Workstations (Security + RDS), DC fallback (4768/4776)"
Write-Green "--------------------------------------------------------------"

foreach($e in $all){
  $ts = $e.Time.ToString("yyyy-MM-dd HH:mm:ss")
  $lt = if($e.LogonType){ " | $($e.LogonType)" } else { "" }
  $ip = if($e.IP){ " | IP: $($e.IP)" } else { "" }
  $ws = if($e.Workstation){ " | WS: $($e.Workstation)" } else { "" }
  $sid= if($e.SessionId){ " | Session: $($e.SessionId)" } else { "" }
  Write-Green ("[{0}] {1,-18} — {2}{3}{4}{5}{6}  (ID {7}, {8})" -f $ts,$e.Computer,$e.Event,$lt,$ip,$ws,$sid,$e.EventId,$e.Source)
}
Write-Green "=============================================================="

# per-computer summary
$by = $all | Group-Object Computer | ForEach-Object {
  $g = $_.Group | Sort-Object Time
  [pscustomobject]@{
    Computer = $_.Name
    First    = $g[0].Time.ToString("yyyy-MM-dd HH:mm:ss")
    Last     = $g[-1].Time.ToString("yyyy-MM-dd HH:mm:ss")
    Events   = $g.Count
  }
} | Sort-Object Last -Descending

Write-Green "Per-computer summary:"
$by | ForEach-Object { Write-Green ("  {0,-18} First: {1} | Last: {2} | Events: {3}" -f $_.Computer,$_.First,$_.Last,$_.Events) }
Write-Green ""

# --- exports --------------------------------------------------------------
if($Csv){
  try{
    $all | Select-Object Time,Computer,Event,Username,LogonType,IP,Workstation,Source,EventId,SessionId |
      Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Csv
    Write-Green ("[CSV] Written to: {0}" -f (Resolve-Path $Csv))
  } catch {
    Write-Green ("[CSV] Failed: {0}" -f $_.Exception.Message)
  }
}

if($Html){
  try{
    $htmlBody = $all | Select-Object Time,Computer,Event,Username,LogonType,IP,Workstation,Source,EventId,SessionId |
      ConvertTo-Html -Title "User Activity: $User" -PreContent "<h2>User Activity: $User</h2><p>Since: $($Since.ToString('yyyy-MM-dd HH:mm:ss'))</p>" |
      Out-String
    $htmlBody | Set-Content -Path $Html -Encoding UTF8
    Write-Green ("[HTML] Written to: {0}" -f (Resolve-Path $Html))
  } catch {
    Write-Green ("[HTML] Failed: {0}" -f $_.Exception.Message)
  }
}
