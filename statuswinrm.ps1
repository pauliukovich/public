<#
.SYNOPSIS
  Check all AD computers (or a given list) and write summary of WinRM status into a text file.

.OUTPUT
  C:\Temp\WinRM_Summary.txt
#>

param(
    [string[]]$Computers,  # optional: explicit list of computers
    [string]$OutFile = "C:\Temp\WinRM_Summary.txt"
)

# Make sure output folder exists
$folder = Split-Path $OutFile -Parent
if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory | Out-Null }

# Build computer list: either from AD or parameter
if ($Computers -and $Computers.Count -gt 0) {
    $targets = $Computers
} else {
    Import-Module ActiveDirectory -ErrorAction Stop
    $targets = Get-ADComputer -Filter { Enabled -eq $true -and OperatingSystem -like "*Windows*" } |
               Select-Object -ExpandProperty DNSHostName
}

# Helper: test ping
function Test-Ping($Name) {
    try { Test-Connection -ComputerName $Name -Count 1 -Quiet -ErrorAction Stop }
    catch { $false }
}

# Helper: test WinRM
function Test-WinRM($Name) {
    try {
        Test-WSMan -ComputerName $Name -ErrorAction Stop | Out-Null
        $true
    } catch { $false }
}

# Collect results
$report = @()
foreach ($c in $targets) {
    if (-not $c) { continue }
    $ping = Test-Ping $c
    if (-not $ping) {
        $report += "[$c] - OFFLINE (no ping)"
        continue
    }

    $winrm = Test-WinRM $c
    if ($winrm) {
        $report += "[$c] - WinRM ENABLED"
    } else {
        $report += "[$c] - WinRM DISABLED/NOT RESPONDING"
    }
}

# Write summary to text file
$report | Out-File -FilePath $OutFile -Encoding UTF8

Write-Host "Summary saved to $OutFile" -ForegroundColor Green
