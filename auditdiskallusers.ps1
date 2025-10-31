# Profile-Sizes-Selected-Hosts.ps1
# PowerShell 5.1 compatible
# Purpose: For a fixed list of computers, enumerate local user profiles and measure folder sizes.
#          Output a TXT (TSV-like) report to C:\temp with:
#          1) per-computer, per-profile sizes
#          2) totals aggregated by profile name across all computers.

# --- Domain credentials (will prompt for password) ---
$domainUser = 'sp6zabki\serwis'
$cred = Get-Credential -UserName $domainUser -Message "Enter password for $domainUser"

# --- Optional ONLINE checks (in addition to ping) ---
$RequireWinRM = $false    # also require TCP 5985 to treat as ONLINE
$RequireRPC   = $false    # also require TCP 135 to treat as ONLINE

# --- Only these hostnames will be checked ---
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

# --- Output file ---
$OutDir = 'C:\temp'
try{ if(-not (Test-Path $OutDir)){ New-Item -Path $OutDir -ItemType Directory -Force | Out-Null } }catch{}
$ReportFile = Join-Path $OutDir ("Profile_Audit_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

Write-Host ">>> Step 1/3: Resolve selected hosts (no AD dependency required)..." -ForegroundColor Cyan
$namesToCheck = $TargetList | Sort-Object -Unique
Write-Host (" - Selected hosts: {0}" -f ($namesToCheck -join ", ")) -ForegroundColor DarkYellow

# --- ONLINE filter (ping + optional ports) ---
Write-Host ">>> Step 2/3: Verifying ONLINE hosts..." -ForegroundColor Cyan
$online=@(); $jobs=@(); $throttle=100
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

# --- Remote block: enumerate profile folders and compute sizes ---
$ProfileSizesBlock = {
  param(
    [string[]] $Roots = @('C:\Users','C:\ad','C:\dane') # check these roots; only existing ones will be used
  )
  # Returns rows: Computer, ProfileRoot, ProfileName, Path, SizeBytes, SizeGB
  function Get-FolderSizeBytes {
    param([string]$Path)
    $sum = 0
    try{
      # Enumerate files; skip reparse points to avoid double counting
      Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $sum += $_.Length }
    }catch{}
    return $sum
  }

  # Exclude well-known/system profiles by name (case-insensitive)
  $exclude = @('Default','Default User','Public','All Users','DefaultAppPool','WDAGUtilityAccount','TEMP')
  $rows = @()
  $computer = $env:COMPUTERNAME

  foreach($root in $Roots){
    try{
      if(-not (Test-Path -LiteralPath $root)){ continue }
      # Only top-level directories (each is a user profile folder)
      Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.Name
        if($exclude -contains $name){ return }
        # Skip hidden or obviously technical profiles that start with '.'
        if($name.StartsWith('.')){ return }

        $path = $_.FullName
        # Safety: ensure it's not a junction we would endlessly recurse into
        if(($_.Attributes.ToString()) -match 'ReparsePoint'){ return }

        $bytes = Get-FolderSizeBytes -Path $path
        $gb = [math]::Round(($bytes/1GB),2)

        $rows += [pscustomobject]@{
          Computer    = $computer
          ProfileRoot = $root
          ProfileName = $name
          Path        = $path
          SizeBytes   = $bytes
          SizeGB      = $gb
        }
      }
    }catch{}
  }
  return $rows
}

Write-Host ">>> Step 3/3: Gathering profile sizes from ONLINE hosts..." -ForegroundColor Cyan
$allRows = New-Object System.Collections.Generic.List[object]

foreach($node in $online | Sort-Object){
  Write-Host (" - {0}" -f $node) -ForegroundColor DarkCyan
  $rows = $null
  try{
    $rows = Invoke-Command -ComputerName $node -Credential $cred -Authentication Kerberos -ScriptBlock $ProfileSizesBlock -ErrorAction Stop
  }catch{
    Add-TrustedHost $node
    try{ $rows = Invoke-Command -ComputerName $node -Credential $cred -Authentication Negotiate -ScriptBlock $ProfileSizesBlock -ErrorAction Stop }catch{ $rows=$null }
  }

  if($rows -and $rows.Count -gt 0){
    foreach($r in $rows){
      $line = ("[{0}] [PROFILE] {1} -> {2} GB ({3})" -f $r.Computer,$r.ProfileName,$r.SizeGB,$r.Path)
      Write-Host $line -ForegroundColor Green
      $allRows.Add($r) | Out-Null
    }
  }else{
    Write-Host ("[{0}] No user profiles found or access failed." -f $node) -ForegroundColor DarkYellow
  }
}

# --- Write report (TXT, TSV-like) ---
"=== PER-COMPUTER PROFILE SIZES ==="        | Out-File -FilePath $ReportFile -Encoding ASCII
"Computer`tProfile`tRoot`tPath`tSizeGB`tSizeBytes" | Out-File -FilePath $ReportFile -Append -Encoding ASCII
foreach($r in ($allRows | Sort-Object Computer,ProfileName)){
  ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $r.Computer,$r.ProfileName,$r.ProfileRoot,$r.Path,$r.SizeGB,$r.SizeBytes) |
    Out-File -FilePath $ReportFile -Append -Encoding ASCII
}

# --- Aggregate totals by ProfileName across all computers ---
$totals = $allRows | Group-Object -Property ProfileName | ForEach-Object {
  $name = $_.Name
  $sumBytes = ($_.Group | Measure-Object -Property SizeBytes -Sum).Sum
  $gb = [math]::Round(($sumBytes/1GB),2)
  [pscustomobject]@{
    ProfileName = $name
    TotalGB     = $gb
    TotalBytes  = $sumBytes
    Computers   = ($_.Group | Select-Object -ExpandProperty Computer -Unique | Sort-Object) -join ','
    CountHosts  = ($_.Group | Select-Object -ExpandProperty Computer -Unique).Count
  }
}

"`n=== TOTALS BY PROFILE (ACROSS ALL COMPUTERS) ===" | Out-File -FilePath $ReportFile -Append -Encoding ASCII
"Profile`tTotalGB`tTotalBytes`tHostsCount`tHosts"     | Out-File -FilePath $ReportFile -Append -Encoding ASCII
foreach($t in ($totals | Sort-Object -Property TotalBytes -Descending)){
  ("{0}`t{1}`t{2}`t{3}`t{4}" -f $t.ProfileName,$t.TotalGB,$t.TotalBytes,$t.CountHosts,$t.Computers) |
    Out-File -FilePath $ReportFile -Append -Encoding ASCII
}

Write-Host ("`nDone. Profile report saved: {0}" -f $ReportFile) -ForegroundColor Green
