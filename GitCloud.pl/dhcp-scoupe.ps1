# DHCP-Scope-Usage.ps1
# Creates human-readable DHCP scope usage report for dashboard
# Output: C:\Windows\database\dhcp\dhcp-scope.txt
# PowerShell 7 compatible

[CmdletBinding()]
param(
    [string]$DhcpServer = "localhost"
)

# Output path
$OutFile = "C:\Windows\database\dhcp\dhcp-scope.txt"

# Ensure directory exists
$dir = Split-Path $OutFile
if (!(Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# Load DHCP module via compatibility
try {
    Import-Module DhcpServer -ErrorAction Stop
}
catch {
    Write-Output "Cannot load DhcpServer module. Run on DHCP server or install RSAT." | Out-File $OutFile
    exit
}

# Get scopes
$scopes = Get-DhcpServerv4Scope -ComputerName $DhcpServer -ErrorAction Stop

if (-not $scopes) {
    "No DHCP scopes found." | Out-File $OutFile
    exit
}

# Start writing file
"===== DHCP SCOPE USAGE =====" | Out-File $OutFile -Encoding UTF8
"Server : $DhcpServer"       | Out-File $OutFile -Append -Encoding UTF8
"Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $OutFile -Append -Encoding UTF8
""                          | Out-File $OutFile -Append -Encoding UTF8

foreach ($scope in $scopes) {

    $stat = Get-DhcpServerv4ScopeStatistics -ComputerName $DhcpServer -ScopeId $scope.ScopeId

    $total = $stat.InUse + $stat.Free + $stat.Reserved + $stat.Pending
    if ($total -le 0) { continue }

    $used = $stat.InUse + $stat.Reserved + $stat.Pending
    $free = $stat.Free

    $usedPct = [Math]::Round(($used / $total) * 100, 1)
    $freePct = [Math]::Round(($free / $total) * 100, 1)

    "Scope: $($scope.Name)"                    | Out-File $OutFile -Append -Encoding UTF8
    "ID: $($scope.ScopeId)"                    | Out-File $OutFile -Append -Encoding UTF8
    "State: $($scope.State)"                   | Out-File $OutFile -Append -Encoding UTF8
    "Total IPs: $total"                        | Out-File $OutFile -Append -Encoding UTF8
    "Used IPs : $used  (${usedPct}%)"          | Out-File $OutFile -Append -Encoding UTF8
    "Free IPs : $free  (${freePct}%)"          | Out-File $OutFile -Append -Encoding UTF8
    ""                                         | Out-File $OutFile -Append -Encoding UTF8
}

# SUMMARY
$sumTotal = ($scopes | ForEach-Object { 
    $st = Get-DhcpServerv4ScopeStatistics -ScopeId $_.ScopeId
    $st.InUse + $st.Free + $st.Reserved + $st.Pending
} | Measure-Object -Sum).Sum

$sumUsed = ($scopes | ForEach-Object { 
    $st = Get-DhcpServerv4ScopeStatistics -ScopeId $_.ScopeId
    $st.InUse + $st.Reserved + $st.Pending
} | Measure-Object -Sum).Sum

$sumFree = ($scopes | ForEach-Object { 
    (Get-DhcpServerv4ScopeStatistics -ScopeId $_.ScopeId).Free
} | Measure-Object -Sum).Sum

if ($sumTotal -gt 0) {
    $sumUsedPct = [Math]::Round(($sumUsed / $sumTotal) * 100, 1)
    $sumFreePct = [Math]::Round(($sumFree / $sumTotal) * 100, 1)

    "===== SUMMARY ====="                      | Out-File $OutFile -Append -Encoding UTF8
    "Total IPs: $sumTotal"                     | Out-File $OutFile -Append -Encoding UTF8
    "Used  IPs: $sumUsed (${sumUsedPct}%)"     | Out-File $OutFile -Append -Encoding UTF8
    "Free  IPs: $sumFree (${sumFreePct}%)"     | Out-File $OutFile -Append -Encoding UTF8
}
