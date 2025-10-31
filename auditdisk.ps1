# Disk-Only-Selected-Hosts.ps1
# PowerShell 5.1 compatible
# Purpose: Check ONLY the specified computers, list all fixed logical disks (DriveType=3),
#          and save results as a plain text (TSV-like) file to C:\temp.

# --- Domain credentials (will prompt for password) ---
$domainUser = 'sp6zabki\serwis'
$cred = Get-Credential -UserName $domainUser -Message "Enter password for $domainUser"

# --- Optional ONLINE checks (in addition to ping) ---
$RequireWinRM = $false    # also require TCP 5985 to treat as ONLINE
$RequireRPC   = $false    # also require TCP 135 to treat as ONLINE

# --- Only these hostnames will be checked (short NetBIOS names as provided) ---
$TargetList = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
)

# --- Helper: add host to WSMan TrustedHosts for NTLM fallback ---
function Add-TrustedHost([string]$fqdn){
  try{
    $current = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($current)) {
      Set-Item WSMan:\localhost\Client\TrustedHosts -Value $fqdn -Force | Out-Null
    } elseif ($current -notmatch [regex]::Escape($fqdn)) {
      Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$current,$fqdn" -Force | Out-Null
    }
  }catch{}
}

# --- Output file (plain text, TSV-like) ---
$OutDir = 'C:\temp'
try{ if(-not (Test-Path $OutDir)){ New-Item -Path $OutDir -ItemType Directory -Force | Out-Null } }catch{}
$ReportFile = Join-Path $OutDir ("Disk_Audit_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

Write-Host ">>> Step 1/3: Resolve selected hosts via AD (prefer FQDN), fallback to raw names..." -ForegroundColor Cyan
$resolved = New-Object System.Collections.Generic.List[string]

# Try to use AD to get FQDNs for the specific targets only; if not, use the short name directly
$adAvailable = $false
try{
  if(Get-Module -ListAvailable -Name ActiveDirectory){
    Import-Module ActiveDirectory -ErrorAction Stop
    $adAvailable = $true
  }
}catch{}

foreach($n in $TargetList){
  $candidate = $null
  if($adAvailable){
    try{
      $obj = Get-ADComputer -Filter "Name -eq '$n'" -Properties DNSHostName,Enabled -ErrorAction Stop
      if($obj -and $obj.Enabled -and $obj.DNSHostName){ $candidate = $obj.DNSHostName }
    }catch{}
  }
  if(-not $candidate){ $candidate = $n } # fallback to short name
  $resolved.Add($candidate) | Out-Null
}

$namesToCheck = $resolved | Sort-Object -Unique
Write-Host (" - Selected hosts to check: {0}" -f ($namesToCheck -join ", ")) -ForegroundColor DarkYellow

# --- ONLINE filter (ping + optional ports) ---
Write-Host ">>> Step 2/3: Verifying ONLINE hosts..." -ForegroundColor Cyan
$online=@(); $jobs=@(); $throttle=150
foreach($name in $namesToCheck){
  $jobs += Start-Job -ScriptBlock {
    param($n,$reqWinRM,$reqRPC)
    $isUp = $false
    try{ $isUp = Test-Connection -ComputerName $n -Count 1 -Quiet -ErrorAction SilentlyContinue }catch{ $isUp=$false }
    if(-not $isUp){ return $null }
    if($reqWinRM){
      try{ $t=Test-NetConnection -ComputerName $n -Port 5985 -WarningAction SilentlyContinue; if(-not $t.TcpTestSucceeded){ return $null } }catch{ return $null }
    }
    if($reqRPC){
      try{ $t=Test-NetConnection -ComputerName $n -Port 135  -WarningAction SilentlyContinue; if(-not $t.TcpTestSucceeded){ return $null } }catch{ return $null }
    }
    return $n
  } -ArgumentList $name,$RequireWinRM,$RequireRPC
  while((Get-Job -State Running).Count -ge $throttle){ Start-Sleep -Milliseconds 100 }
}
if($jobs.Count -gt 0){ $online = Receive-Job -Job $jobs -Wait -AutoRemoveJob | Where-Object { $_ } }
Write-Host (">>> ONLINE selected hosts: {0}" -f $online.Count) -ForegroundColor Cyan
if($online.Count -eq 0){ Write-Host "No online hosts from the selected list. Stopping." -ForegroundColor Red; return }

# --- Remote block: list ALL fixed logical disks (DriveType=3) via WMI ---
$WmiDisksBlock = {
  # Return rows: Computer, Drive, FreeGB, SizeGB, FreePct
  $rows = @()
  try{
    $logical = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    foreach($d in $logical){
      $sizeGB = if($d.Size){ [math]::Round(($d.Size/1GB),2) } else { $null }
      $freeGB = if($d.FreeSpace){ [math]::Round(($d.FreeSpace/1GB),2) } else { $null }
      $pct    = 0
      if($d.Size -gt 0){ $pct = [math]::Round(($d.FreeSpace/$d.Size)*100,1) }
      $rows += [pscustomobject]@{
        Computer = $env:COMPUTERNAME
        Drive    = $d.DeviceID
        FreeGB   = $freeGB
        SizeGB   = $sizeGB
        FreePct  = $pct
      }
    }
  }catch{}
  return $rows
}

Write-Host ">>> Step 3/3: Gathering disk free space from ONLINE hosts..." -ForegroundColor Cyan
$allRows = New-Object System.Collections.Generic.List[object]

foreach($node in $online | Sort-Object){
  Write-Host (" - {0}" -f $node) -ForegroundColor DarkCyan
  $rows = $null
  try{
    $rows = Invoke-Command -ComputerName $node -Credential $cred -Authentication Kerberos -ScriptBlock $WmiDisksBlock -ErrorAction Stop
  }catch{
    # fallback: add to TrustedHosts then try Negotiate (NTLM)
    Add-TrustedHost $node
    try{ $rows = Invoke-Command -ComputerName $node -Credential $cred -Authentication Negotiate -ScriptBlock $WmiDisksBlock -ErrorAction Stop }catch{ $rows=$null }
  }

  if($rows -and $rows.Count -gt 0){
    foreach($r in $rows){
      $line = ("[{0}] [DISK] {1} free {2} GB ({3}%) of {4} GB" -f $r.Computer,$r.Drive,$r.FreeGB,$r.FreePct,$r.SizeGB)
      Write-Host $line -ForegroundColor Green
      $allRows.Add($r) | Out-Null
    }
  }else{
    Write-Host ("[{0}] No fixed logical disks found or access failed." -f $node) -ForegroundColor DarkYellow
  }
}

# --- Save plain text report (TSV-like) to C:\temp ---
"Computer`tDrive`tFreeGB`tSizeGB`tFreePct" | Out-File -FilePath $ReportFile -Encoding ASCII
foreach($r in ($allRows | Sort-Object Computer,Drive)){
  ("{0}`t{1}`t{2}`t{3}`t{4}" -f $r.Computer,$r.Drive,$r.FreeGB,$r.SizeGB,$r.FreePct) |
    Out-File -FilePath $ReportFile -Append -Encoding ASCII
}

Write-Host ("`nDone. Disk report saved: {0}" -f $ReportFile) -ForegroundColor Green
