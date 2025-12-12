# RAM Top 5 Consumers Report
# PowerShell 7 compatible

$OutFile = "C:\Windows\database\ram\ram-top.txt"

# Ensure directory exists
$dir = Split-Path $OutFile
if (!(Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# Get top 5 processes by RAM usage
$top = Get-Process |
    Sort-Object -Property WorkingSet64 -Descending |
    Select-Object -First 5 Name, Id, @{Name="RAM_MB";Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}}

# Build report text
$time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$lines = @()
$lines += "RAM TOP 5 PROCESSES"
$lines += "Time: $time"
$lines += "------------------------------------"

foreach ($p in $top) {
    $lines += "{0} (PID {1}) - {2} MB" -f $p.Name, $p.Id, $p.RAM_MB
}

$lines += "------------------------------------"

# Write to file
$lines | Out-File -FilePath $OutFile -Encoding UTF8 -Force
