<#
    Server hardware & OS inventory
    - Disks (vendor, model, logical disks, free/used)
    - CPU (all key properties)
    - RAM (per module + total/used + extra info)
    - Network adapters (IP, DNS)
    - Windows Server version + domain
    Output: C:\Windows\database\drive\serverdrive.txt
#>

[CmdletBinding()]
param()

$OutFile = "C:\Windows\database\drive\serverdrive.txt"
$OutDir  = Split-Path $OutFile -Parent

# Ensure target directory exists
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$lines = @()

# =========================
# BASIC INFO / OS / DOMAIN
# =========================

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem

# safer install date conversion
$installDate = "N/A"
try {
    if ($os.InstallDate) {
        $installDate = [Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate)
    }
} catch {
    $installDate = $os.InstallDate
}

$lines += "===== SERVER INVENTORY ====="
$lines += "Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "Server : $env:COMPUTERNAME"
$lines += ""

$lines += "[OPERATING SYSTEM]"
$lines += "Caption      : $($os.Caption)"
$lines += "Version      : $($os.Version)"
$lines += "Build Number : $($os.BuildNumber)"
$lines += "Architecture : $($os.OSArchitecture)"
$lines += "Install Date : $installDate"
$lines += ""
$lines += "[DOMAIN]"
$lines += "Domain       : $($cs.Domain)"
$lines += "Domain Role  : $($cs.DomainRole)"
$lines += "Workgroup    : $($cs.Workgroup)"
$lines += ""

# ==========
# CPU
# ==========

$cpuList = Get-CimInstance Win32_Processor
foreach ($cpu in $cpuList) {
    $lines += "[CPU - $($cpu.DeviceID)]"
    $lines += "Name                  : $($cpu.Name)"
    $lines += "Manufacturer          : $($cpu.Manufacturer)"
    $lines += "Description           : $($cpu.Description)"
    $lines += "Socket                : $($cpu.SocketDesignation)"
    $lines += "Cores                 : $($cpu.NumberOfCores)"
    $lines += "Logical Processors    : $($cpu.NumberOfLogicalProcessors)"
    $lines += "Max Clock Speed (MHz) : $($cpu.MaxClockSpeed)"
    $lines += "Current Clock (MHz)   : $($cpu.CurrentClockSpeed)"
    $lines += "L2 Cache (KB)         : $($cpu.L2CacheSize)"
    $lines += "L3 Cache (KB)         : $($cpu.L3CacheSize)"
    $lines += "Processor Id          : $($cpu.ProcessorId)"
    $lines += ""
}

# ==========
# RAM
# ==========

$ramModules = Get-CimInstance Win32_PhysicalMemory
$totalRamBytes = ($ramModules | Measure-Object -Property Capacity -Sum).Sum

# OS memory is reported in KB
$totalVisibleKB  = [int64]$os.TotalVisibleMemorySize
$freeKB          = [int64]$os.FreePhysicalMemory
$usedKB          = $totalVisibleKB - $freeKB
$totalVisibleGB  = [math]::Round(($totalVisibleKB * 1KB) / 1GB, 2)
$usedGB          = [math]::Round(($usedKB * 1KB) / 1GB, 2)
$freeGB          = [math]::Round(($freeKB * 1KB) / 1GB, 2)
$usedPct         = if ($totalVisibleGB -ne 0) { [math]::Round(($usedGB / $totalVisibleGB) * 100, 1) } else { 0 }

$lines += "[RAM - SUMMARY]"
$lines += "Total Physical (GB)   : $([math]::Round($totalRamBytes / 1GB, 2))"
$lines += "Total Visible (GB)    : $totalVisibleGB"
$lines += "Used (GB)             : $usedGB"
$lines += "Free (GB)             : $freeGB"
$lines += "Used (%)              : $usedPct"
$lines += ""

$index = 0
foreach ($m in $ramModules) {
    $index++
    $capacityGB = [math]::Round($m.Capacity / 1GB, 2)

    # Memory type decoding from SMBIOSMemoryType
    $memTypeCode = $m.SMBIOSMemoryType
    $memType = switch ($memTypeCode) {
        20 { "DDR" }
        21 { "DDR2" }
        22 { "DDR2 FB-DIMM" }
        24 { "DDR3" }
        26 { "DDR4" }
        27 { "LPDDR4" }
        28 { "LPDDR4X" }
        29 { "LPDDR5" }
        30 { "LPDDR5X" }
        34 { "DDR5" }
        default {
            if ($memTypeCode) { "SMBIOS code $memTypeCode" } else { "Unknown" }
        }
    }

    # ECC detection via TotalWidth vs DataWidth
    $ecc = "Unknown"
    if ($m.TotalWidth -and $m.DataWidth) {
        if ($m.TotalWidth -gt $m.DataWidth) {
            $ecc = "Yes"
        }
        else {
            $ecc = "No"
        }
    }

    # Voltage in volts (if reported, millivolts -> volts)
    $voltageV = $null
    if ($m.ConfiguredVoltage -and $m.ConfiguredVoltage -gt 0) {
        $voltageV = [math]::Round($m.ConfiguredVoltage / 1000, 3)
    }

    $lines += "[RAM MODULE #$index]"
    $lines += "Bank / Slot    : $($m.BankLabel) / $($m.DeviceLocator)"
    $lines += "Manufacturer   : $($m.Manufacturer)"
    $lines += "Model          : $($m.Model)"
    $lines += "Part Number    : $($m.PartNumber)"
    $lines += "Serial Number  : $($m.SerialNumber)"
    $lines += "Capacity (GB)  : $capacityGB"
    $lines += "Speed (MHz)    : $($m.Speed)"
    $lines += "ConfiguredClk  : $($m.ConfiguredClockSpeed)"
    $lines += "Memory Type    : $memType"
    $lines += "Form Factor    : $($m.FormFactor)"
    $lines += "Data Width (b) : $($m.DataWidth)"
    $lines += "Total Width(b) : $($m.TotalWidth)"
    $lines += "ECC            : $ecc"
    if ($voltageV) {
        $lines += "Voltage (V)    : $voltageV"
    }
    $lines += ""
}

# ==========
# DISKS
# ==========

$physDisks    = Get-CimInstance Win32_DiskDrive
$logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3"

foreach ($d in $physDisks) {
    $sizeGB = if ($d.Size) { [math]::Round($d.Size / 1GB, 2) } else { 0 }
    $lines += "[PHYSICAL DISK - $($d.DeviceID)]"
    $lines += "Model            : $($d.Model)"
    $lines += "Manufacturer     : $($d.Manufacturer)"
    $lines += "Serial Number    : $($d.SerialNumber)"
    $lines += "Interface Type   : $($d.InterfaceType)"
    $lines += "Media Type       : $($d.MediaType)"
    $lines += "Firmware         : $($d.FirmwareRevision)"
    $lines += "Size (GB)        : $sizeGB"
    $lines += ""
}

$lines += "[LOGICAL DISKS]"
foreach ($ld in $logicalDisks) {
    $totalGB = if ($ld.Size) { [math]::Round($ld.Size / 1GB, 2) } else { 0 }
    $freeGB  = if ($ld.FreeSpace) { [math]::Round($ld.FreeSpace / 1GB, 2) } else { 0 }
    $usedGB  = $totalGB - $freeGB
    $usedPct = if ($totalGB -ne 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

    $lines += "Drive            : $($ld.DeviceID)"
    $lines += "Label            : $($ld.VolumeName)"
    $lines += "File System      : $($ld.FileSystem)"
    $lines += "Size (GB)        : $totalGB"
    $lines += "Used (GB)        : $usedGB"
    $lines += "Free (GB)        : $freeGB"
    $lines += "Used (%)         : $usedPct"
    $lines += ""
}

# ==========
# NETWORK
# ==========

$lines += "[NETWORK ADAPTERS]"

try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface -eq $true }
} catch {
    $adapters = @()
}

foreach ($a in $adapters) {
    $lines += "Adapter Name     : $($a.Name)"
    $lines += "Description      : $($a.InterfaceDescription)"
    $lines += "MAC Address      : $($a.MacAddress)"

    # LinkSpeed can be numeric or string like '1 Gbps' – handle both
    $linkSpeedRaw = $a.LinkSpeed
    if ($linkSpeedRaw) {
        $lines += "Link Speed Raw   : $linkSpeedRaw"

        $speedGbps = $null

        if ($linkSpeedRaw -is [string]) {
            if ($linkSpeedRaw -match '([\d\.,]+)') {
                $num = $matches[1] -replace ',', '.'
                $value = [double]$num

                if ($linkSpeedRaw -match '(gbit|gbps|gigabit)') {
                    $speedGbps = [math]::Round($value, 2)
                }
                elseif ($linkSpeedRaw -match '(mbps|mibit|mps)') {
                    $speedGbps = [math]::Round($value / 1000, 2)
                }
            }
        }
        else {
            # assume bits per second
            $speedGbps = [math]::Round(([double]$linkSpeedRaw) / 1e9, 2)
        }

        if ($null -ne $speedGbps) {
            $lines += "Link Speed (Gbps): $speedGbps"
        }
    }

    $ipv4List = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    foreach ($ip in $ipv4List) {
        $lines += "IPv4 Address     : $($ip.IPAddress)/$($ip.PrefixLength)"
    }

    $ipv6List = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue
    foreach ($ip6 in $ipv6List) {
        $lines += "IPv6 Address     : $($ip6.IPAddress)/$($ip6.PrefixLength)"
    }

    $dnsInfo = Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($dnsInfo -and $dnsInfo.ServerAddresses) {
        $lines += "DNS Servers      : $($dnsInfo.ServerAddresses -join ', ')"
    }

    $lines += ""
}

# ==========
# SAVE TO FILE
# ==========

Set-Content -Path $OutFile -Value $lines -Encoding UTF8
Write-Host "Inventory saved to: $OutFile"
