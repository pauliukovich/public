# speed-drive.ps1
# Realtime disk read/write speed (MB/s) for C: and G:
# Uses Win32_PerfFormattedData_PerfDisk_LogicalDisk instead of Get-Counter

$OutFile = "C:\Windows\database\drive\speed-drive.txt"
$targetDrives = @("C:", "G:")

function To-MB {
    param($bytes)
    return [math]::Round(($bytes / 1MB), 2)
}

# Get logical disk performance data
$cimData = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_LogicalDisk

$time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$report = "Disk speed report ($time)`r`n"
$report += "----------------------------------------`r`n"

foreach ($drive in $targetDrives) {
    $row = $cimData | Where-Object { $_.Name -eq $drive }

    if ($null -ne $row) {
        $readMB  = To-MB $row.DiskReadBytesPerSec
        $writeMB = To-MB $row.DiskWriteBytesPerSec

        $report += "Drive: $drive`r`n"
        $report += "Read:  $readMB MB/s`r`n"
        $report += "Write: $writeMB MB/s`r`n"
        $report += "`r`n"
    }
    else {
        $report += "Drive: $drive`r`n"
        $report += "No data available`r`n`r`n"
    }
}

$report | Out-File -FilePath $OutFile -Encoding UTF8
