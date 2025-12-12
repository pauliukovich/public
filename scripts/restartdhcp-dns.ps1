# Restart DHCP and DNS services with status log (PowerShell 7)

# Ensure log folder exists
$logPath = "C:\Temp"
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}

$logFile = "$logPath\dhcp_dns_restart_log.txt"
$date    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

# Create header
"===== DHCP & DNS Restart Log =====" | Out-File -FilePath $logFile -Encoding UTF8
"Date: $date"                         | Out-File -Append -FilePath $logFile

# Function to restart and log
function Restart-AndLog {
    param(
        [string]$serviceName,
        [string]$displayName
    )

    try {
        Restart-Service -Name $serviceName -Force -ErrorAction Stop
        $msg = "$displayName restarted successfully."
        Write-Host $msg -ForegroundColor Green
        $msg | Out-File -Append -FilePath $logFile
    }
    catch {
        $err = "$displayName restart FAILED: $($_.Exception.Message)"
        Write-Host $err -ForegroundColor Red
        $err | Out-File -Append -FilePath $logFile
    }
}

# Restart services
Restart-AndLog -serviceName "DHCPServer" -displayName "DHCP Server"
Restart-AndLog -serviceName "DNS"        -displayName "DNS Server"

"-----------------------------------" | Out-File -Append -FilePath $logFile
"Operation completed."                | Out-File -Append -FilePath $logFile

Write-Host "Log saved to: $logFile" -ForegroundColor Cyan
