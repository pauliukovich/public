# ============================================================================
# Installed Applications Full Inventory
# Output: C:\Windows\database\apps\installed-apps.txt
# Works on PowerShell 7
# ============================================================================

$OutFile = "C:\Windows\database\apps\installed-apps.txt"
$OutDir  = Split-Path $OutFile -Parent

# Ensure directory exists
if (!(Test-Path $OutDir)) {
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
}

# --------------------------------------------
# Function: Read apps from registry uninstall
# --------------------------------------------
function Get-RegUninstallApps {
    param($Hive)

    $paths = @(
        "$Hive\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "$Hive\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            Get-ChildItem $path | ForEach-Object {
                $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue

                if ($p.DisplayName) {
                    [PSCustomObject]@{
                        Name            = $p.DisplayName
                        Version         = $p.DisplayVersion
                        Publisher       = $p.Publisher
                        InstallDateRaw  = $p.InstallDate
                        InstallDate     = if ($p.InstallDate -match '^\d{8}$') {
                                              [datetime]::ParseExact($p.InstallDate,'yyyyMMdd',$null)
                                          } else { $null }
                        InstallLocation = $p.InstallLocation
                        UninstallString = $p.UninstallString
                        EstimatedSizeMB = if ($p.EstimatedSize) { [math]::Round($p.EstimatedSize/1024,1) } else { $null }
                        RegistryPath    = $_.Name
                        Source          = "Registry"
                    }
                }
            }
        }
    }
}

# --------------------------------------------
# Function: Get apps from Win32_InstalledStoreProgram (UWP)
# --------------------------------------------
function Get-UWPApps {
    Get-CimInstance Win32_InstalledStoreProgram | ForEach-Object {
        [PSCustomObject]@{
            Name            = $_.Name
            Version         = $_.Version
            Publisher       = $_.Publisher
            InstallDateRaw  = $_.InstallDate
            InstallDate     = $_.InstallDate
            InstallLocation = $_.InstallLocation
            UninstallString = $null
            EstimatedSizeMB = $null
            RegistryPath    = $null
            Source          = "UWP"
        }
    }
}

# --------------------------------------------
# Collect everything
# --------------------------------------------

$apps = @()

# Registry: HKLM
$apps += Get-RegUninstallApps -Hive "HKLM:"

# Registry: HKCU
$apps += Get-RegUninstallApps -Hive "HKCU:"

# UWP apps
$apps += Get-UWPApps

# Remove duplicates
$apps = $apps | Sort-Object Name, Version -Unique

# --------------------------------------------
# Build report
# --------------------------------------------
$lines = @()
$lines += "===== INSTALLED APPLICATIONS INVENTORY ====="
$lines += "Server : $env:COMPUTERNAME"
$lines += "Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "Total applications: $($apps.Count)"
$lines += ""
$lines += "-----------------------------------------------------------"
$lines += ""

foreach ($app in $apps | Sort-Object Name) {
    $lines += "Name: $($app.Name)"
    $lines += "Version: $($app.Version)"
    $lines += "Publisher: $($app.Publisher)"
    $lines += "Install Date: $($app.InstallDate)"
    $lines += "Install Location: $($app.InstallLocation)"
    $lines += "Estimated Size (MB): $($app.EstimatedSizeMB)"
    $lines += "Uninstall String: $($app.UninstallString)"
    $lines += "Source: $($app.Source)"
    $lines += "Registry Key: $($app.RegistryPath)"
    $lines += ""
    $lines += "-----------------------------------------------------------"
}

# --------------------------------------------
# Save file
# --------------------------------------------
$lines | Out-File -FilePath $OutFile -Encoding UTF8

Write-Host "Application inventory saved to $OutFile" -ForegroundColor Green
