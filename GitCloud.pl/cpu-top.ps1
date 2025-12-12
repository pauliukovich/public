# Cpu-Top-Processes.ps1
# PowerShell 7
# Top CPU consumers snapshot
# Output: C:\Windows\database\cpu-load\cpu-top.txt

$OutFile = "C:\Windows\database\cpu-load\cpu-top.txt"

# Ensure directory exists
$dir = Split-Path $OutFile
if (!(Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

function Write-Line {
    param([string]$Text = "")
    $Text | Out-File $OutFile -Append -Encoding UTF8
}

# Clear file
"" | Out-File $OutFile -Encoding UTF8

$serverName = $env:COMPUTERNAME
$now        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# Interval for measurement (seconds)
$intervalSec = 2

# Get logical CPUs
$logicalCpus = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
if (-not $logicalCpus -or $logicalCpus -lt 1) { $logicalCpus = 1 }

# First snapshot
$sample1 = Get-Process | Select-Object Id, ProcessName, CPU

Start-Sleep -Seconds $intervalSec

# Second snapshot
$sample2 = Get-Process | Select-Object Id, ProcessName, CPU

# Join snapshots by PID and compute CPU%
$stats = foreach ($p2 in $sample2) {
    $p1 = $sample1 | Where-Object { $_.Id -eq $p2.Id } | Select-Object -First 1
    if (-not $p1) { continue }

    if ($p2.CPU -eq $null -or $p1.CPU -eq $null) { continue }

    $deltaCpu = $p2.CPU - $p1.CPU       # seconds of CPU time
    if ($deltaCpu -lt 0) { continue }

    $cpuPercent = ($deltaCpu / $intervalSec) / $logicalCpus * 100
    $cpuPercent = [Math]::Round($cpuPercent, 1)

    if ($cpuPercent -lt 0) { continue }

    [PSCustomObject]@{
        Id          = $p2.Id
        ProcessName = $p2.ProcessName
        CpuPercent  = $cpuPercent
    }
}

$top = $stats | Sort-Object CpuPercent -Descending | Select-Object -First 5

Write-Line "===== CPU TOP PROCESSES ====="
Write-Line "Server   : $serverName"
Write-Line "Date     : $now"
Write-Line "Interval : ${intervalSec}s"
Write-Line ""

if (-not $top) {
    Write-Line "No processes data available."
    return
}

Write-Line "TOP 5 PROCESSES:"
foreach ($p in $top) {
    Write-Line ("{0} (PID {1}) - {2} %" -f $p.ProcessName, $p.Id, $p.CpuPercent)
}
