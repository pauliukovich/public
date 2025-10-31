<#
 ServiceTrim.ps1 — Safe Windows 11 Pro service diet (Windows PowerShell 5.1)
 Keeps: Print, RDP, WinRM, Network, Firewall
 Backups: C:\Logs\ServiceTrim\services-backup_*.csv
 Usage:
   .\ServiceTrim.ps1
   .\ServiceTrim.ps1 -WhatIf
   .\ServiceTrim.ps1 -Revert
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$Revert)

function Assert-Admin {
  # Ensure script is running as Administrator
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run PowerShell as Administrator."
  }
}

function New-LogDir {
  # Prepare log directory and backup filenames
  $global:LogRoot = 'C:\Logs\ServiceTrim'
  if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
  $global:Stamp   = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
  $global:Backup  = Join-Path $LogRoot "services-backup_$Stamp.csv"
  $global:LastBackupLink = Join-Path $LogRoot "services-backup_latest.csv"
}

function Backup-Services {
  # Backup all services with their current startup type and state
  Write-Verbose "Backing up current service states -> $Backup"
  Get-WmiObject -Class Win32_Service |
    Select-Object Name, DisplayName, StartMode, State |
    Export-Csv -NoTypeInformation -Encoding UTF8 -Path $Backup
  Copy-Item $Backup $LastBackupLink -Force
}

function Restore-Services([string]$CsvPath) {
  # Restore services from previous backup (PS5-safe)
  if (-not (Test-Path $CsvPath)) { throw "Backup not found: $CsvPath" }
  $items = Import-Csv -Path $CsvPath
  foreach ($s in $items) {
    $mode = $s.StartMode
    if ($mode -eq 'Auto') { $mode = 'Automatic' } # normalize

    if ($PSCmdlet.ShouldProcess($s.Name, "Set start=$mode")) {
      try {
        Set-Service -Name $s.Name -StartupType $mode -ErrorAction Stop
      } catch {
        # Fallback via sc.exe for stubborn services (PS5 has no ?: operator)
        $m = 'demand'
        if ($mode -eq 'Disabled') { $m = 'disabled' }
        elseif ($mode -eq 'Automatic') { $m = 'auto' }
        sc.exe config "$($s.Name)" start= $m | Out-Null
      }
    }
  }
}

function Set-StartTypeSafe([string]$Name,[string]$Mode) {
  # Safely change startup type (Automatic / Manual / Disabled) without ternary
  try {
    Set-Service -Name $Name -StartupType $Mode -ErrorAction Stop
  } catch {
    $m = 'demand'
    if ($Mode -eq 'Disabled') { $m = 'disabled' }
    elseif ($Mode -eq 'Automatic') { $m = 'auto' }
    sc.exe config "$Name" start= $m | Out-Null
  }
}

function Stop-ServiceSafe([string]$Name) {
  # Stop service safely if possible
  try { Stop-Service -Name $Name -Force -ErrorAction Stop } catch { }
}

# ----------------- MAIN -----------------
Assert-Admin
New-LogDir

if ($Revert) {
  $csv = Get-ChildItem $LogRoot -Filter 'services-backup_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $csv) { throw "No backups found in $LogRoot." }
  Write-Host "Restoring from: $($csv.FullName)"
  Restore-Services -CsvPath $csv.FullName
  Write-Host "Done. Reboot recommended."
  return
}

# Critical services to keep
$Keep = @(
  'Spooler',                   # Print Spooler
  'TermService','UmRdpService',# Remote Desktop
  'WinRM',                     # Windows Remote Management
  'MpsSvc','BFE',              # Firewall / BFE
  'LanmanServer','LanmanWorkstation',
  'Dhcp','Dnscache','nsi','NlaSvc', # Networking core
  'EventLog','W32Time','CryptSvc','PlugPlay',
  'RpcSs','DcomLaunch','LSM',
  'Audiosrv','AudioEndpointBuilder' # Audio (optional, but harmless)
) | Sort-Object -Unique

# Disable candidates (only if present)
$ToDisable = @(
  'DiagTrack','dmwappushservice','RetailDemo',
  'Fax','WMPNetworkSvc',
  'XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc',
  'RemoteRegistry','SharedAccess','SSDPSRV','upnphost',
  'WbioSrvc','SCardSvr','TrkWks','SEMgrSvc','WalletService',
  'TapiSrv','PhoneSvc','SmsRouter','MixedRealityOpenXRSvc'
)

# Set to Manual (available but not auto-start)
$ToManual = @(
  'WSearch',    # Windows Search
  'SysMain',    # Superfetch
  'MapsBroker',
  'lfsvc'       # Geolocation
)

# Backup current state
Backup-Services

# Resolve available services
$all = Get-Service | Select-Object -ExpandProperty Name

# Apply Disable
foreach ($name in $ToDisable) {
  if ($Keep -contains $name) { continue }
  if ($all -contains $name) {
    if ($PSCmdlet.ShouldProcess($name,"Disable")) {
      Stop-ServiceSafe $name
      Set-StartTypeSafe $name 'Disabled'
      Write-Host "[Disabled] $name"
    }
  }
}

# Apply Manual
foreach ($name in $ToManual) {
  if ($Keep -contains $name) { continue }
  if ($all -contains $name) {
    if ($PSCmdlet.ShouldProcess($name,"Manual")) {
      Stop-ServiceSafe $name
      Set-StartTypeSafe $name 'Manual'
      Write-Host "[Manual]   $name"
    }
  }
}

# Ensure essentials are Automatic and running
$MustAutoAndRunning = @('Spooler','TermService','UmRdpService','WinRM','MpsSvc','BFE','LanmanServer','LanmanWorkstation','Dhcp','Dnscache','nsi','NlaSvc')
foreach ($name in $MustAutoAndRunning) {
  if ($all -contains $name) {
    if ($PSCmdlet.ShouldProcess($name,"Ensure Automatic & Running")) {
      Set-StartTypeSafe $name 'Automatic'
      try { Start-Service -Name $name -ErrorAction SilentlyContinue } catch {}
    }
  }
}

Write-Host "`nAll done. Backup saved to: $Backup"
Write-Host "Dry-run available with: -WhatIf"
Write-Host "To revert: .\ServiceTrim.ps1 -Revert"
Write-Host "Reboot recommended."
