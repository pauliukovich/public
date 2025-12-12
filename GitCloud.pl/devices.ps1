# =====================================================
# Device Manager Inventory
# Output: C:\Windows\database\devices\device-manager.txt
# =====================================================

$OutFile = "C:\Windows\database\devices\device-manager.txt"
$OutDir  = Split-Path $OutFile -Parent

# Ensure directory exists
if (!(Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# Collect all devices
$devices = Get-CimInstance Win32_PnPEntity

# Group by class
$grouped = $devices | Group-Object PNPClass | Sort-Object Name

# Build template
$lines = @()
$lines += "===== DEVICE MANAGER INVENTORY ====="
$lines += "Server : $env:COMPUTERNAME"
$lines += "Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "Total devices: $($devices.Count)"
$lines += ""
$lines += "-----------------------------------------------"

foreach ($grp in $grouped) {
    $class = if ($grp.Name) { $grp.Name } else { "Unknown" }
    $lines += ""
    $lines += "### CLASS: $class"
    $lines += "Count: $($grp.Group.Count)"
    $lines += ""

    foreach ($d in $grp.Group | Sort-Object Name) {
        $lines += "- Name: $($d.Name)"
        $lines += "  DeviceID: $($d.DeviceID)"
        $lines += "  Status: $($d.Status)"
        $lines += "  Manufacturer: $($d.Manufacturer)"
        $lines += ""
    }

    $lines += "-----------------------------------------------"
}

# Save
$lines | Out-File -FilePath $OutFile -Encoding UTF8

Write-Host "Device list saved to $OutFile" -ForegroundColor Green
