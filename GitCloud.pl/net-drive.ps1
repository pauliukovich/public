# Net-Drive-Status.ps1
# PowerShell 7
# Reports usage of network share (Gitcloud.pl)
# Output: C:\Windows\database\drive\net-drive.txt

$OutFile = "C:\Windows\database\drive\net-drive.txt"

# UNC path of your network drive (G:)
$netPath = "\\192.168.20.3\Gitcloud.pl"   # при необходимости поменяй

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

Write-Line "===== NET DRIVE STATUS ====="
Write-Line "Server : $serverName"
Write-Line "Date   : $now"
Write-Line ""

# --- WinAPI wrapper for GetDiskFreeSpaceEx ---

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class DiskFreeSpaceHelper {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool GetDiskFreeSpaceEx(
        string lpDirectoryName,
        out ulong lpFreeBytesAvailable,
        out ulong lpTotalNumberOfBytes,
        out ulong lpTotalNumberOfFreeBytes
    );
}
"@ -ErrorAction SilentlyContinue

[ulong]$freeAvail = 0
[ulong]$total     = 0
[ulong]$free      = 0

$ok = [DiskFreeSpaceHelper]::GetDiskFreeSpaceEx($netPath, [ref]$freeAvail, [ref]$total, [ref]$free)

if (-not $ok -or $total -eq 0) {
    Write-Line "Path         : $netPath"
    Write-Line "Status       : ERROR - cannot read size (check access / path)"
    return
}

$totalGB = [Math]::Round($total     / 1GB, 1)
$freeGB  = [Math]::Round($free      / 1GB, 1)
$usedGB  = [Math]::Round($totalGB - $freeGB, 1)

if ($totalGB -gt 0) {
    $usedPct = [Math]::Round(($usedGB / $totalGB) * 100, 1)
} else {
    $usedPct = 0
}

Write-Line "Path         : $netPath"
Write-Line ""
Write-Line ("Total Space  : {0} GB" -f $totalGB)
Write-Line ("Used Space   : {0} GB" -f $usedGB)
Write-Line ("Free Space   : {0} GB" -f $freeGB)
Write-Line ("Used Percent : {0} %"  -f $usedPct)
