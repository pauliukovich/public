# DNS Cleanup Script (PowerShell 7)
# Silent mode: no confirmations

$ConfirmPreference = 'None'   # disable all confirmations globally

$logPath = "C:\Temp"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

$logFile = "$logPath\dns_cleanup_log.txt"
$date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

"===== DNS Cleanup Report ====="  | Out-File $logFile -Encoding UTF8
"Date: $date"                     | Out-File -Append -FilePath $logFile
"--------------------------------" | Out-File -Append -FilePath $logFile

try {
    $dnsConfig = Get-DnsServerScavenging -ErrorAction Stop

    if ($dnsConfig.ScavengingState -eq $false) {
        "Scavenging is disabled. Enabling..." | Out-File -Append -FilePath $logFile
        Set-DnsServerScavenging -ScavengingState $true -Force -Confirm:$false -ErrorAction Stop
        "Scavenging has been enabled." | Out-File -Append -FilePath $logFile
    } else {
        "Scavenging already enabled." | Out-File -Append -FilePath $logFile
    }

    "Starting scavenging..." | Out-File -Append -FilePath $logFile
    Start-DnsServerScavenging -Force -Confirm:$false -ErrorAction Stop
    "Scavenging started successfully." | Out-File -Append -FilePath $logFile

} catch {
    "ERROR: $($_.Exception.Message)" | Out-File -Append -FilePath $logFile
    Write-Host "DNS cleanup FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

"--------------------------------"  | Out-File -Append -FilePath $logFile
"DNS cleanup finished."            | Out-File -Append -FilePath $logFile

Write-Host "DNS cleanup completed silently. Log saved to $logFile" -ForegroundColor Green
