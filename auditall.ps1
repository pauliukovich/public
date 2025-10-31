# =====================================================================
# AD ONLINE INVENTORY (PowerShell 5.1 compatible)
# - Discover from AD only (no subnet scan)
# - Keep only ONLINE hosts (ping; optional TCP 5985/135)
# - Collect per host (via WinRM): Windows, RAM, CPU, GPU, Office,
#   SSD volumes (worst free%), Network (WiFi/LAN, NIC, IP, MAC, SSID, Speed),
#   Domain membership
# - Console: colored progress + compact summary table
# - EXPORT: CSV (all successful hosts with Status/FailReasons) + TXT (PASSED/FAILED)
# - PASS criteria: WorstFreePct >= 20 AND NetType == 'LAN'
# =====================================================================

# ---------- CREDENTIALS ----------
$domainUser = 'sp6zabki\serwis'
$cred = Get-Credential -UserName $domainUser -Message "Enter password for $domainUser"

# ---------- ONLINE FILTER SETTINGS ----------
$RequireWinRM = $false  # set $true to require TCP 5985 open during ONLINE filter
$RequireRPC   = $false  # set $true to require TCP 135 open during ONLINE filter

# ---------- TRUSTEDHOSTS HELPER ----------
function Add-TrustedHost([string]$fqdn){
  try {
    $current = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($current)) {
      Set-Item WSMan:\localhost\Client\TrustedHosts -Value $fqdn -Force | Out-Null
    } elseif ($current -notmatch [regex]::Escape($fqdn)) {
      Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$current,$fqdn" -Force | Out-Null
    }
  } catch { }
}

# ---------- BUFFERS ----------
$Summary       = New-Object System.Collections.Generic.List[object]  # on-screen table (success only)
$FullSuccesses = New-Object System.Collections.Generic.List[object]  # successfully collected hosts

Write-Host ">>> Step 1/2: Discover ACTIVE hosts from AD..." -ForegroundColor Cyan

# ---------- GET CANDIDATES FROM AD ----------
$dnsAD = @()
try {
  if (Get-Module -ListAvailable -Name ActiveDirectory) {
    Import-Module ActiveDirectory -ErrorAction Stop
    $dnsAD = Get-ADComputer -Filter * -Properties DNSHostName, Enabled |
             Where-Object { $_.Enabled -and $_.DNSHostName } |
             Select-Object -ExpandProperty DNSHostName
    Write-Host (" - From AD (before online filter): {0}" -f $dnsAD.Count) -ForegroundColor DarkYellow
  } else {
    Write-Host " - ActiveDirectory module not available — no host source." -ForegroundColor Red
  }
} catch {
  Write-Host " - AD error: $($_.Exception.Message)" -ForegroundColor Red
}

# ---------- ONLINE FILTER ----------
$online = @()
if ($dnsAD.Count -gt 0) {
  Write-Host " - Verifying ONLINE hosts from AD..." -ForegroundColor Cyan
  $jobs = @()
  $throttle = 200
  foreach ($name in $dnsAD) {
    $jobs += Start-Job -ScriptBlock {
      param($n, $reqWinRM, $reqRPC)
      $isUp = $false
      try { $isUp = Test-Connection -ComputerName $n -Count 1 -Quiet -ErrorAction SilentlyContinue } catch { $isUp = $false }
      if (-not $isUp) { return $null }
      if ($reqWinRM) {
        try { $x = Test-NetConnection -ComputerName $n -Port 5985 -WarningAction SilentlyContinue; if (-not $x.TcpTestSucceeded) { return $null } } catch { return $null }
      }
      if ($reqRPC) {
        try { $x = Test-NetConnection -ComputerName $n -Port 135  -WarningAction SilentlyContinue; if (-not $x.TcpTestSucceeded) { return $null } } catch { return $null }
      }
      return $n
    } -ArgumentList $name, $RequireWinRM, $RequireRPC
    while ((Get-Job -State Running).Count -ge $throttle) { Start-Sleep -Milliseconds 100 }
  }
  if ($jobs.Count -gt 0) {
    $online = Receive-Job -Job $jobs -Wait -AutoRemoveJob | Where-Object { $_ }
  }
}
Write-Host (">>> To check (ONLINE from AD): {0}" -f $online.Count) -ForegroundColor Cyan
if ($online.Count -eq 0) { Write-Host "No online hosts. Stopping." -ForegroundColor Red; return }

# ---------- REMOTE BLOCK (FULL DATA; MUST SUCCEED) ----------
$FullBlock = {
  # Windows
  $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
  $winVer = '—'
  if ($osInfo) { $winVer = "{0} {1} (Build {2})" -f $osInfo.Caption, $osInfo.Version, $osInfo.BuildNumber }
  Write-Host "[$env:COMPUTERNAME] [WINDOWS] $winVer" -ForegroundColor Green

  # RAM
  $ramTotalGB=$null; $ramFreeGB=$null
  if ($osInfo) {
    $ramTotalGB = [math]::Round($osInfo.TotalVisibleMemorySize/1024,2)
    $ramFreeGB  = [math]::Round($osInfo.FreePhysicalMemory/1024,2)
    Write-Host "[$env:COMPUTERNAME] [RAM] Free $ramFreeGB GB / Total $ramTotalGB GB" -ForegroundColor White
  }

  # CPU
  $cpuName='—'; $cpuLog=$null
  $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
  if ($cpu) {
    $t = ($cpu | Select-Object -First 1 -ExpandProperty Name); if ($t){$cpuName=$t}
    $l = ($cpu | Select-Object -First 1 -ExpandProperty NumberOfLogicalProcessors); if ($l -ne $null){$cpuLog=$l}
    if ($cpuLog -ne $null) { Write-Host "[$env:COMPUTERNAME] [CPU] $cpuName ($cpuLog logical)" -ForegroundColor Yellow }
    else { Write-Host "[$env:COMPUTERNAME] [CPU] $cpuName" -ForegroundColor Yellow }
  }

  # GPU
  $gpuOut='—'; $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
  if ($gpus) { $names = ($gpus | Select-Object -ExpandProperty Name); if ($names){ $gpuOut = ($names -join ', ') } }
  Write-Host "[$env:COMPUTERNAME] [GPU] $gpuOut" -ForegroundColor Yellow

  # Office (ClickToRun + MSI)
  $officeVer='—'
  try {
    $key1='HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $key2='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    if (Test-Path $key1){
      $p=Get-ItemProperty -Path $key1 -ErrorAction SilentlyContinue
      if ($p){
        if($p.VersionToReport){$officeVer=$p.VersionToReport}
        elseif($p.ClientVersionToReport){$officeVer=$p.ClientVersionToReport}
        elseif($p.ProductVersion){$officeVer=$p.ProductVersion}
      }
    }
    if ($officeVer -eq '—' -and (Test-Path $key2)){
      $p=Get-ItemProperty -Path $key2 -ErrorAction SilentlyContinue
      if ($p){
        if($p.VersionToReport){$officeVer=$p.VersionToReport}
        elseif($p.ClientVersionToReport){$officeVer=$p.ClientVersionToReport}
        elseif($p.ProductVersion){$officeVer=$p.ProductVersion}
      }
    }
    if ($officeVer -eq '—'){
      $msiVers=@('16.0','15.0','14.0','12.0')
      foreach($v in $msiVers){
        $k="HKLM:\SOFTWARE\Microsoft\Office\$v\Common"
        $w="HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\$v\Common"
        if (Test-Path $k){
          $pp=Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
          if($pp -and $pp.ProductVersion){$officeVer=$pp.ProductVersion; break}
        }
        if ($officeVer -eq '—' -and (Test-Path $w)){
          $pp=Get-ItemProperty -Path $w -ErrorAction SilentlyContinue
          if($pp -and $pp.ProductVersion){$officeVer=$pp.ProductVersion; break}
        }
      }
    }
  } catch { }
  Write-Host "[$env:COMPUTERNAME] [OFFICE] $officeVer" -ForegroundColor Green

  # Disks: SSD/NVMe volumes and worst free%
  $volInfos=@()
  $ssdDisks = Get-Disk | Where-Object { ($_.MediaType -eq 'SSD') -or ($_.BusType -eq 'NVMe') -or ($_.SpindleSpeed -eq 0) -or ($_.FriendlyName -match 'SSD|NVMe') }
  if ($ssdDisks){
    foreach($d in $ssdDisks){
      $parts = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
      foreach($p in $parts){
        $v = Get-Volume -Partition $p -ErrorAction SilentlyContinue
        if ($v -and $v.DriveLetter -and $v.DriveType -eq 'Fixed'){
          $freeGB=[math]::Round($v.SizeRemaining/1GB,2)
          $sizeGB=[math]::Round($v.Size/1GB,2)
          $pct=0; if($v.Size -gt 0){ $pct=[math]::Round(($v.SizeRemaining/$v.Size)*100,1) }
          $color='Green'; if($pct -lt 15){$color='Red'} elseif($pct -lt 30){$color='Yellow'}
          Write-Host "[$env:COMPUTERNAME] [DISK] $($v.DriveLetter): free $freeGB GB ($pct%) of $sizeGB GB" -ForegroundColor $color
          $row = New-Object psobject -Property @{ DriveLetter=$v.DriveLetter; FreeGB=$freeGB; SizeGB=$sizeGB; FreePct=$pct }
          $volInfos += $row
        }
      }
    }
  }
  $worstDrive='—'; $worstPct=$null; $worstFree=$null; $worstSize=$null
  if ($volInfos.Count -gt 0){
    $w = $volInfos | Sort-Object FreePct | Select-Object -First 1
    if ($w.DriveLetter){ $worstDrive = $w.DriveLetter + ':' }
    $worstPct  = $w.FreePct
    $worstFree = $w.FreeGB
    $worstSize = $w.SizeGB
  }

  # Network (default-route iface; fallback first Up)
  $netType='—'; $nicName='—'; $ipv4='—'; $mac='—'; $speed='—'; $ssid='—'
  $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
  $nic = $null
  if ($route){ $nic = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue }
  if (-not $nic){ $nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1 }
  if ($nic){
    $isWifi = ($nic.InterfaceDescription -match 'Wireless|Wi-?Fi|802\.11')
    if ($isWifi){ $netType='WiFi' } else { $netType='LAN' }
    $nicName=$nic.Name
    $ipconf = Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex -ErrorAction SilentlyContinue
    if ($ipconf -and $ipconf.IPv4Address){ $ipv4 = ($ipconf.IPv4Address | Select-Object -First 1 -ExpandProperty IPv4Address) }
    if ($nic.MacAddress){ $mac = $nic.MacAddress }
    if ($nic.LinkSpeed){ $speed = $nic.LinkSpeed }
    if ($isWifi){
      $ssidLine = netsh wlan show interfaces | Select-String -Pattern '^\s*SSID\s*:\s*(.+)$' | Select-Object -First 1
      if ($ssidLine){ $ssid = ($ssidLine.Matches[0].Groups[1].Value).Trim() }
    }
    $color = if ($isWifi) { 'Magenta' } else { 'Blue' }
    Write-Host "[$env:COMPUTERNAME] [NET] $netType — adapter: $nicName, IP: $ipv4, MAC: $mac, SSID: $ssid, Speed: $speed" -ForegroundColor $color
  } else {
    Write-Host "[$env:COMPUTERNAME] [NET] No active adapter." -ForegroundColor DarkYellow
  }

  # Domain
  $inDomain=$false; $domainName='—'
  try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs -and $cs.PartOfDomain){ $inDomain=$true; if($cs.Domain){ $domainName=$cs.Domain } }
  } catch { }

  # Return record
  $obj = New-Object psobject -Property @{
    Computer     = $env:COMPUTERNAME
    InDomain     = $inDomain
    Domain       = $domainName
    Windows      = $winVer
    RAM_TotalGB  = $ramTotalGB
    RAM_FreeGB   = $ramFreeGB
    CPU          = $cpuName
    CPU_Logical  = $cpuLog
    GPU          = $gpuOut
    Office       = $officeVer
    WorstDrive   = $worstDrive
    WorstFreePct = $worstPct
    WorstFreeGB  = $worstFree
    WorstSizeGB  = $worstSize
    NetType      = $netType   # WiFi or LAN
    NICName      = $nicName
    IPv4         = $ipv4
    MAC          = $mac
    Speed        = $speed
    SSID         = $ssid
  }
  return $obj
}

Write-Host ">>> Step 2/2: Collecting data from ONLINE hosts..." -ForegroundColor Cyan
foreach ($node in $online) {
  Write-Host ">>> Checking $node ..." -ForegroundColor Cyan

  $obj = $null
  try {
    $obj = Invoke-Command -ComputerName $node -Credential $cred -Authentication Kerberos -ScriptBlock $FullBlock -ErrorAction Stop
  } catch {
    Add-TrustedHost $node
    try {
      $obj = Invoke-Command -ComputerName $node -Credential $cred -Authentication Negotiate -ScriptBlock $FullBlock -ErrorAction Stop
    } catch {
      Write-Host "[$node] Could not collect details (WinRM). Skipping in report." -ForegroundColor DarkYellow
    }
  }

  if ($obj) {
    $Summary.Add($obj)       | Out-Null
    $FullSuccesses.Add($obj) | Out-Null
  }
}

# ---------- POST-PROCESS: PASS/FAIL EVALUATION & EXPORT ----------
# PASS: WorstFreePct >= 20 AND NetType == 'LAN'
function Get-FailReasons {
  param([psobject]$r)
  $reasons = @()
  if ($null -eq $r.WorstFreePct) { $reasons += 'NoDiskInfo' }
  elseif ($r.WorstFreePct -lt 20) { $reasons += ("LowDisk:{0}%" -f $r.WorstFreePct) }
  if ($r.NetType -ne 'LAN') { $reasons += ("Conn:{0}" -f ($r.NetType ? $r.NetType : 'Unknown')) }
  return ($reasons -join '; ')
}

$Evaluated = foreach ($r in $FullSuccesses) {
  $fail = @()
  $passDisk = ($null -ne $r.WorstFreePct) -and ($r.WorstFreePct -ge 20)
  $passNet  = ($r.NetType -eq 'LAN')
  $status = if ($passDisk -and $passNet) { 'Passed' } else { 'Failed' }
  $reasons = if ($status -eq 'Failed') { Get-FailReasons -r $r } else { 'OK' }

  # Вернём объект с ВСЕМИ полями + служебные
  [PSCustomObject]@{
    Computer     = $r.Computer
    InDomain     = $r.InDomain
    Domain       = $r.Domain
    Windows      = $r.Windows
    RAM_TotalGB  = $r.RAM_TotalGB
    RAM_FreeGB   = $r.RAM_FreeGB
    CPU          = $r.CPU
    CPU_Logical  = $r.CPU_Logical
    GPU          = $r.GPU
    Office       = $r.Office
    WorstDrive   = $r.WorstDrive
    WorstFreePct = $r.WorstFreePct
    WorstFreeGB  = $r.WorstFreeGB
    WorstSizeGB  = $r.WorstSizeGB
    NetType      = $r.NetType
    NICName      = $r.NICName
    IPv4         = $r.IPv4
    MAC          = $r.MAC
    Speed        = $r.Speed
    SSID         = $r.SSID
    Status       = $status
    FailReasons  = $reasons
    CheckedTime  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  }
}

# ---------- ON-SCREEN SUMMARY ----------
Write-Host "`n=== SUMMARY (successful collection only; with PASS/FAIL) ===" -ForegroundColor Cyan
$Evaluated |
  Sort-Object Computer |
  Select-Object `
    @{n='Computer'; e={$_.Computer}},
    @{n='Status';   e={$_.Status}},
    @{n='Reasons';  e={$_.FailReasons}},
    @{n='Windows';  e={$_.Windows}},
    @{n='Office';   e={$_.Office}},
    @{n='RAM GB (free/total)'; e={ if(($_.RAM_FreeGB -ne $null) -and ($_.RAM_TotalGB -ne $null)){ "$($_.RAM_FreeGB)/$($_.RAM_TotalGB)" } else { '-' } }},
    @{n='CPU'; e={ if($_.CPU_Logical -ne $null){ "$($_.CPU) ($($_.CPU_Logical))" } else { $_.CPU } }},
    @{n='GPU'; e={$_.GPU}},
    @{n='SSD worst'; e={$_.WorstDrive}},
    @{n='% free'; e={ if($_.WorstFreePct -ne $null){ "$($_.WorstFreePct)%" } else { '-' } }},
    @{n='Net'; e={$_.NetType}},
    @{n='Adapter'; e={$_.NICName}},
    @{n='IPv4'; e={$_.IPv4}},
    @{n='Speed'; e={$_.Speed}},
    @{n='SSID'; e={$_.SSID}} |
  Format-Table -AutoSize

# ---------- EXPORT DIR ----------
$ReportDir  = 'C:\temp'
try { if (-not (Test-Path $ReportDir)) { New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null } } catch { }

# ---------- CSV EXPORT (ALL successful; Status/FailReasons included) ----------
$csvPath = Join-Path $ReportDir ("audit_summary_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Evaluated | Export-Csv -Path $csvPath -NoTypeInformation -Delimiter ';' -Encoding utf8Bom

# ---------- TXT EXPORT (grouped: PASSED / FAILED) ----------
$txtPath = Join-Path $ReportDir ("audit_summary_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$passed = $Evaluated | Where-Object { $_.Status -eq 'Passed' } | Sort-Object Computer
$failed = $Evaluated | Where-Object { $_.Status -eq 'Failed' } | Sort-Object Computer

$sb = New-Object System.Text.StringBuilder
$sb.AppendLine(("Inventory report — {0}" -f (Get-Date))) | Out-Null
$sb.AppendLine(("Runner: {0}" -f $env:COMPUTERNAME)) | Out-Null
$sb.AppendLine(("Totals: Passed={0}, Failed={1}" -f $passed.Count, $failed.Count)) | Out-Null
$sb.AppendLine("Criteria: WorstFreePct >= 20% AND NetType == LAN") | Out-Null
$sb.AppendLine("======================================================================") | Out-Null

# Section: PASSED
$sb.AppendLine(("== PASSED ({0}) ==" -f $passed.Count)) | Out-Null
foreach ($r in $passed) {
  $ramStr = if (($r.RAM_FreeGB -ne $null) -and ($r.RAM_TotalGB -ne $null)) { "{0}/{1}" -f $r.RAM_FreeGB, $r.RAM_TotalGB } else { "-" }
  $cpuStr = if ($r.CPU_Logical -ne $null) { "{0} ({1})" -f $r.CPU, $r.CPU_Logical } else { $r.CPU }
  $pctStr = if ($r.WorstFreePct -ne $null) { "{0}%" -f $r.WorstFreePct } else { "-" }
  $inDom  = if ($r.InDomain) { "YES" } else { "NO" }

  @(
    ("Computer: {0}" -f $r.Computer),
    ("  Domain: {0} ({1})" -f $r.Domain, $inDom),
    ("  Windows: {0}" -f $r.Windows),
    ("  Office: {0}"  -f $r.Office),
    ("  RAM(GB): {0}" -f $ramStr),
    ("  CPU: {0}"     -f $cpuStr),
    ("  GPU: {0}"     -f $r.GPU),
    ("  Worst SSD: {0} | %free {1} | FreeGB {2} | SizeGB {3}" -f $r.WorstDrive, $pctStr, $r.WorstFreeGB, $r.WorstSizeGB),
    ("  Net: {0} | Adapter: {1} | IPv4: {2} | MAC: {3} | Speed: {4} | SSID: {5}" -f $r.NetType, $r.NICName, $r.IPv4, $r.MAC, $r.Speed, $r.SSID),
    ("  Status: {0} | Reasons: {1}" -f $r.Status, $r.FailReasons),
    ("----------------------------------------------------------------------")
  ) | ForEach-Object { $sb.AppendLine($_) | Out-Null }
}

# Section: FAILED
$sb.AppendLine("") | Out-Null
$sb.AppendLine(("== FAILED ({0}) ==" -f $failed.Count)) | Out-Null
foreach ($r in $failed) {
  $ramStr = if (($r.RAM_FreeGB -ne $null) -and ($r.RAM_TotalGB -ne $null)) { "{0}/{1}" -f $r.RAM_FreeGB, $r.RAM_TotalGB } else { "-" }
  $cpuStr = if ($r.CPU_Logical -ne $null) { "{0} ({1})" -f $r.CPU, $r.CPU_Logical } else { $r.CPU }
  $pctStr = if ($r.WorstFreePct -ne $null) { "{0}%" -f $r.WorstFreePct } else { "-" }
  $inDom  = if ($r.InDomain) { "YES" } else { "NO" }

  @(
    ("Computer: {0}" -f $r.Computer),
    ("  Domain: {0} ({1})" -f $r.Domain, $inDom),
    ("  Windows: {0}" -f $r.Windows),
    ("  Office: {0}"  -f $r.Office),
    ("  RAM(GB): {0}" -f $ramStr),
    ("  CPU: {0}"     -f $cpuStr),
    ("  GPU: {0}"     -f $r.GPU),
    ("  Worst SSD: {0} | %free {1} | FreeGB {2} | SizeGB {3}" -f $r.WorstDrive, $pctStr, $r.WorstFreeGB, $r.WorstSizeGB),
    ("  Net: {0} | Adapter: {1} | IPv4: {2} | MAC: {3} | Speed: {4} | SSID: {5}" -f $r.NetType, $r.NICName, $r.IPv4, $r.MAC, $r.Speed, $r.SSID),
    ("  Status: {0} | Reasons: {1}" -f $r.Status, $r.FailReasons),
    ("----------------------------------------------------------------------")
  ) | ForEach-Object { $sb.AppendLine($_) | Out-Null }
}

[IO.File]::WriteAllText($txtPath, $sb.ToString(), [System.Text.Encoding]::ASCII)

Write-Host ""
Write-Host ("CSV  saved: {0}" -f $csvPath) -ForegroundColor Green
Write-Host ("TXT  saved: {0}" -f $txtPath) -ForegroundColor Green
