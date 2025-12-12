<# 
  New-InternetMonitoringReport.ps1
  Creates a human-readable internet monitoring template.

  Outputs:
    C:\Windows\database\monitoring\monitoring.txt

  Data collected:
    - Timestamp and server name
    - External IP and ISP (via ipinfo.io)
    - Routing info (default gateway, route metric, profile)
    - Latency and packet loss to key targets
    - DNS resolution test
    - Basic connection statistics (active TCP sessions)
#>

[CmdletBinding()]
param()

# ---------- Paths ----------
$OutputDir  = "C:\Windows\database\monitoring"
$OutputFile = Join-Path $OutputDir "monitoring.txt"

if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

# ---------- Basic info ----------
$now    = Get-Date
$server = $env:COMPUTERNAME

# ---------- Helper: ping stats ----------
function Get-PingStats {
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        [int]$Count = 4
    )

    try {
        $p = Test-Connection -ComputerName $Target -Count $Count -ErrorAction Stop
        $avg = ($p | Measure-Object -Property Latency -Average).Average
        $received = $p.Count
        $sent = $Count
        $lost = $sent - $received
        $lossPct = if ($sent -gt 0) { [math]::Round(($lost / $sent) * 100, 1) } else { 100 }

        return [pscustomobject]@{
            Target     = $Target
            Sent       = $sent
            Received   = $received
            Lost       = $lost
            Loss       = if ($sent -gt 0) { "$lossPct %" } else { "N/A" }
            AvgLatency = if ($avg -ne $null) { ("{0:N1} ms" -f $avg) } else { "N/A" }
            Online     = ($received -gt 0)
        }
    }
    catch {
        return [pscustomobject]@{
            Target     = $Target
            Sent       = $Count
            Received   = 0
            Lost       = $Count
            Loss       = "100 %"
            AvgLatency = "N/A"
            Online     = $false
        }
    }
}

# ---------- External IP & ISP (ipinfo.io) ----------
$extIp      = "N/A"
$ispName    = "N/A"
$ispCity    = "N/A"
$ispCountry = "N/A"

try {
    $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/json" -TimeoutSec 10
    if ($ipInfo) {
        if ($ipInfo.ip)      { $extIp      = $ipInfo.ip }
        if ($ipInfo.org)     { $ispName    = $ipInfo.org }
        if ($ipInfo.city)    { $ispCity    = $ipInfo.city }
        if ($ipInfo.country) { $ispCountry = $ipInfo.country }
    }
}
catch {
    # Keep defaults if request fails
}

# ---------- Routing info ----------
$gateway        = "N/A"
$routeMetric    = "N/A"
$ifaceAlias     = "N/A"
$profileName    = "N/A"
$profileType    = "N/A"

try {
    $defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
                    Sort-Object -Property RouteMetric |
                    Select-Object -First 1

    if ($defaultRoute) {
        if ($defaultRoute.NextHop)      { $gateway     = $defaultRoute.NextHop }
        if ($defaultRoute.RouteMetric)  { $routeMetric = $defaultRoute.RouteMetric }

        if ($defaultRoute.InterfaceIndex) {
            $iface = Get-NetIPInterface -InterfaceIndex $defaultRoute.InterfaceIndex -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($iface) {
                $ifaceAlias = $iface.InterfaceAlias
            }

            $profile = Get-NetConnectionProfile -InterfaceIndex $defaultRoute.InterfaceIndex -ErrorAction SilentlyContinue
            if ($profile) {
                $profileName = $profile.Name
                $profileType = $profile.NetworkCategory
            }
        }
    }
}
catch {
    # Keep defaults
}

# ---------- Latency / packet loss ----------
$pingTargets = @(
    "1.1.1.1",
    "8.8.8.8",
    "google.com"
)

$pingStats = foreach ($t in $pingTargets) {
    Get-PingStats -Target $t -Count 4
}

$internetOnline = $pingStats.Online -contains $true
$internetStatus = if ($internetOnline) { "ONLINE" } else { "OFFLINE" }

# ---------- DNS test ----------
$dnsStatus   = "N/A"
$dnsGoogleIp = "N/A"

try {
    $dnsRes = Resolve-DnsName -Name "google.com" -Type A -ErrorAction Stop
    $ips    = $dnsRes | Where-Object { $_.IPAddress } | Select-Object -First 3 | ForEach-Object { $_.IPAddress }
    if ($ips) {
        $dnsGoogleIp = $ips -join ", "
        $dnsStatus   = "OK"
    }
    else {
        $dnsStatus = "No A records returned"
    }
}
catch {
    $dnsStatus = "ERROR: $($_.Exception.Message)"
}

# ---------- Connection statistics ----------
$tcpEstablished = 0
try {
    $tcpEstablished = (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue).Count
}
catch {
    $tcpEstablished = 0
}

# ---------- Build output ----------
$lines = @()
$lines += "===== INTERNET MONITORING ====="
$lines += "Date   : {0}" -f $now.ToString("yyyy-MM-dd HH:mm:ss")
$lines += "Server : $server"
$lines += ""

$lines += "[ISP]"
$lines += "External IP     : $extIp"
$lines += "Provider        : $ispName"
$lines += "Location        : $ispCity, $ispCountry"
$lines += ""

$lines += "[ROUTING]"
$lines += "Internet Status : $internetStatus"
$lines += "Default Gateway : $gateway"
$lines += "Route Metric    : $routeMetric"
$lines += "Interface Alias : $ifaceAlias"
$lines += "Network Profile : $profileName ($profileType)"
$lines += ""

$lines += "[INTERNET QUALITY]"
foreach ($ps in $pingStats) {
    $lines += "Target {0,-10} : Avg {1,-8} Loss {2} (Sent {3}, Recv {4})" -f `
        $ps.Target, $ps.AvgLatency, $ps.Loss, $ps.Sent, $ps.Received
}
$lines += ""

$lines += "[DNS]"
$lines += "Resolver Status : $dnsStatus"
$lines += "google.com A    : $dnsGoogleIp"
$lines += ""

$lines += "[CONNECTIONS]"
$lines += "TCP Established : $tcpEstablished"
$lines += ""

# Write file
$lines | Set-Content -Path $OutputFile -Encoding UTF8

Write-Host "Monitoring report created: $OutputFile"
