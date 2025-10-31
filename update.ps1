<# 
.SYNOPSIS
  Fix & sync Windows Update services remotely over WinRM and trigger a scan.

.DESCRIPTION
  For each target:
   - Ping check + WinRM check
   - Ensure services exist, set startup type (Automatic; wuauserv -> Delayed Auto)
   - Start services if stopped
   - Trigger update scan (UsoClient StartScan; fallback to wuauclt)
   - Return per-host status incl. last successful scan time (registry)
   - Log to %TEMP%\WU-Repair-<date>.csv and .txt

.REQUIREMENTS
  - Run as domain admin (or with -Credential)
  - WinRM enabled on targets
  - PowerShell 5.1+ / 7+ on the admin side
#>

# ---------------------- TARGETS ----------------------
$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
)

# ---------------------- SETTINGS ----------------------
$TimeoutSec      = 20
$PingTimeoutMs   = 1500
$LogDir          = $env:TEMP
$Stamp           = (Get-Date -Format 'yyyyMMdd-HHmmss')
$CsvPath         = Join-Path $LogDir "WU-Repair-$Stamp.csv"
$TxtPath         = Join-Path $LogDir "WU-Repair-$Stamp.txt"
$UseCredential   = $false   # flip to $true if you want to be prompted
$Credential      = $null
if ($UseCredential) { $Credential = Get-Credential }

# ---------------------- REMOTE SCRIPT ----------------------
$RemoteScript = {
  param([int]$TimeoutSec = 20)

  # Helper: safe service fetch
  function Get-ServiceSafe([string[]]$Names){
    foreach($n in $Names){
      try { Get-Service -Name $n -ErrorAction Stop }
      catch { }
    }
  }

  # Target services (some may not exist on older builds)
  $svcNames = 'wuauserv','bits','UsoSvc','WaaSMedicSvc'

  # 1) Ensure startup type: Automatic (wuauserv -> Delayed-Auto for reliability)
  foreach($svc in $svcNames){
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($null -ne $s) {
      try {
        Set-Service -Name $svc -StartupType Automatic -ErrorAction Stop
        if ($svc -eq 'wuauserv') {
          # Delayed Auto (more graceful on boot)
          & sc.exe config wuauserv start= delayed-auto | Out-Null
        }
      } catch {}
    }
  }

  # 2) Start services if needed
  foreach($svc in $svcNames){
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($null -ne $s -and $s.Status -ne 'Running'){
      try { Start-Service -Name $svc -ErrorAction Stop } catch {}
    }
  }

  # 3) Trigger scan
  $scanTriggered = $false
  $usoPath = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
  if (Test-Path $usoPath) {
    try {
      $p = Start-Process -FilePath $usoPath -ArgumentList 'StartScan' -NoNewWindow -PassThru -ErrorAction Stop
      $null = $p.WaitForExit($TimeoutSec*1000)
      $scanTriggered = $true
    } catch {}
  }
  if (-not $scanTriggered) {
    $wua = Join-Path $env:SystemRoot 'System32\wuauclt.exe'
    if (Test-Path $wua) {
      try {
        Start-Process -FilePath $wua -ArgumentList '/detectnow' -NoNewWindow -ErrorAction SilentlyContinue
        Start-Process -FilePath $wua -ArgumentList '/reportnow' -NoNewWindow -ErrorAction SilentlyContinue
        $scanTriggered = $true
      } catch {}
    }
  }

  # 4) Collect status
  $services = Get-ServiceSafe $svcNames | Select-Object Name, Status, StartType
  $lastScan = $null
  try {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect'
    $lastScan = (Get-ItemProperty -Path $regPath -ErrorAction Stop).LastSuccessTime
  } catch { $lastScan = $null }

  # Query Windows Update client version (optional candy)
  $wuDll = Join-Path $env:SystemRoot 'System32\wuaueng.dll'
  $wuVer = $null
  if (Test-Path $wuDll) {
    try { $wuVer = (Get-Item $wuDll).VersionInfo.ProductVersion } catch {}
  }

  # Return object
  [pscustomobject]@{
    ComputerName        = $env:COMPUTERNAME
    ScanTriggered       = $scanTriggered
    LastScanTime        = $lastScan
    WU_Engine_Version   = $wuVer
    Svc_wuauserv        = ($services | ? Name -eq 'wuauserv'      | Select -Expand Status     -ErrorAction SilentlyContinue)
    Svc_wuauserv_Start  = ($services | ? Name -eq 'wuauserv'      | Select -Expand StartType  -ErrorAction SilentlyContinue)
    Svc_bits            = ($services | ? Name -eq 'bits'          | Select -Expand Status     -ErrorAction SilentlyContinue)
    Svc_bits_Start      = ($services | ? Name -eq 'bits'          | Select -Expand StartType  -ErrorAction SilentlyContinue)
    Svc_UsoSvc          = ($services | ? Name -eq 'UsoSvc'        | Select -Expand Status     -ErrorAction SilentlyContinue)
    Svc_UsoSvc_Start    = ($services | ? Name -eq 'UsoSvc'        | Select -Expand StartType  -ErrorAction SilentlyContinue)
    Svc_WaaSMedicSvc    = ($services | ? Name -eq 'WaaSMedicSvc'  | Select -Expand Status     -ErrorAction SilentlyContinue)
    Svc_WaaSMedic_Start = ($services | ? Name -eq 'WaaSMedicSvc'  | Select -Expand StartType  -ErrorAction SilentlyContinue)
  }
}

# ---------------------- LOCAL HELPERS ----------------------
function Test-Online {
  param([string]$Computer)
  try {
    # ICMP quick check
    if (-not (Test-Connection -ComputerName $Computer -Count 1 -Quiet -TimeoutSeconds ($PingTimeoutMs/1000))) { return $false }
    # WinRM quick check
    Test-WSMan -ComputerName $Computer -ErrorAction Stop | Out-Null
    return $true
  } catch { return $false }
}

# Pretty console
function Write-Info   { param($t) ; Write-Host $t -ForegroundColor Cyan }
function Write-OK     { param($t) ; Write-Host $t -ForegroundColor Green }
function Write-Warn   { param($t) ; Write-Host $t -ForegroundColor Yellow }
function Write-Err    { param($t) ; Write-Host $t -ForegroundColor Red }

# ---------------------- MAIN ----------------------
$results = New-Object System.Collections.Generic.List[object]
Write-Info "== Windows Update remote repair & scan ==  $(Get-Date)"
Write-Info "Log CSV: $CsvPath"
Write-Info "Log TXT: $TxtPath"
Write-Host ""

foreach($c in $Computers){
  Write-Info "[ $c ] checking connectivity…"
  if (-not (Test-Online -Computer $c)) {
    Write-Err  "   OFFLINE or WinRM unreachable"
    $results.Add([pscustomobject]@{
      ComputerName=$c; Reachable=$false; Error='Offline/No WinRM'
      ScanTriggered=$false; LastScanTime=$null
      Svc_wuauserv=$null; Svc_wuauserv_Start=$null
      Svc_bits=$null; Svc_bits_Start=$null
      Svc_UsoSvc=$null; Svc_UsoSvc_Start=$null
      Svc_WaaSMedicSvc=$null; Svc_WaaSMedic_Start=$null
      WU_Engine_Version=$null
    }) | Out-Null
    continue
  }

  try {
    $icParams = @{
      ComputerName = $c
      ScriptBlock  = $RemoteScript
      ArgumentList = @($TimeoutSec)
      ErrorAction  = 'Stop'
      HideComputerName = $true
    }
    if ($Credential) { $icParams.Credential = $Credential }

    $out = Invoke-Command @icParams

    $results.Add($out) | Out-Null
    $reach = $true

    $okServices = @('wuauserv','bits','UsoSvc','WaaSMedicSvc') |
                  ForEach-Object {
                    $st = $out."Svc_$($_)"
                    if ($st -eq 'Running') { $_ }
                  }

    if ($out.ScanTriggered) {
      Write-OK   ("   Services OK: {0}" -f ($(($okServices -join ', '))  -replace '^$','(none)'))
      Write-OK   ("   Update scan triggered. LastScan: {0}" -f ($out.LastScanTime ?? 'N/A'))
    } else {
      Write-Warn ("   Services adjusted, but scan trigger may have failed. LastScan: {0}" -f ($out.LastScanTime ?? 'N/A'))
    }
  }
  catch {
    Write-Err "   ERROR: $($_.Exception.Message)"
    $results.Add([pscustomobject]@{
      ComputerName=$c; Reachable=$true; Error=$_.Exception.Message
      ScanTriggered=$false; LastScanTime=$null
      Svc_wuauserv=$null; Svc_wuauserv_Start=$null
      Svc_bits=$null; Svc_bits_Start=$null
      Svc_UsoSvc=$null; Svc_UsoSvc_Start=$null
      Svc_WaaSMedicSvc=$null; Svc_WaaSMedic_Start=$null
      WU_Engine_Version=$null
    }) | Out-Null
  }
}

# ---------------------- LOGGING ----------------------
# CSV
$results | Select-Object `
  ComputerName,
  @{n='Reachable';e={if ($_ | Get-Member -Name Reachable -MemberType NoteProperty){$_.Reachable}else{$true}}},
  ScanTriggered, LastScanTime, WU_Engine_Version,
  Svc_wuauserv, Svc_wuauserv_Start,
  Svc_bits,     Svc_bits_Start,
  Svc_UsoSvc,   Svc_UsoSvc_Start,
  Svc_WaaSMedicSvc, Svc_WaaSMedic_Start,
  Error |
  Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvPath

# TXT (compact)
"== Windows Update repair report ==", (Get-Date), "" | Out-File -FilePath $TxtPath -Encoding UTF8
foreach($r in $results){
  $line = "{0,-18} | Reachable:{1,-5} | Scan:{2,-5} | LastScan:{3,-20} | WUA:{4}/{5} | BITS:{6}/{7} | USO:{8}/{9} | MEDIC:{10}/{11} | Err:{12}" -f `
    $r.ComputerName,
    ($(if ($r.PSObject.Properties.Name -contains 'Reachable'){$r.Reachable}else{$true})),
    $r.ScanTriggered, ($r.LastScanTime ?? 'N/A'),
    ($r.Svc_wuauserv ?? 'n/a'), ($r.Svc_wuauserv_Start ?? 'n/a'),
    ($r.Svc_bits ?? 'n/a'),     ($r.Svc_bits_Start ?? 'n/a'),
    ($r.Svc_UsoSvc ?? 'n/a'),   ($r.Svc_UsoSvc_Start ?? 'n/a'),
    ($r.Svc_WaaSMedicSvc ?? 'n/a'), ($r.Svc_WaaSMedic_Start ?? 'n/a'),
    ($r.Error ?? '')
  Add-Content -Path $TxtPath -Value $line
}

Write-Host ""
Write-Info  "CSV: $CsvPath"
Write-Info  "TXT: $TxtPath"
Write-OK    "Done."
# --- keep console open on PS5 ISE ---
if ($psise){ Read-Host "Press ENTER to exit" }
