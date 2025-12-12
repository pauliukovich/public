# dhcp_watcher.ps1
# Monitor DHCP service and auto-restart + Telegram notify
$dhcpServiceName = "DHCPServer"
$intervalSec = 60
$telegramToken = "PUT_YOUR_BOT_TOKEN_HERE"
$chatId = "PUT_YOUR_CHAT_ID_HERE"

function Send-Telegram($text){
    $url = "https://api.telegram.org/bot$telegramToken/sendMessage"
    try {
        Invoke-RestMethod -Uri $url -Method Post -Body @{ chat_id = $chatId; text = $text } -ErrorAction Stop | Out-Null
    } catch { Write-Host "Telegram send failed: $_" }
}

while ($true) {
    $svc = Get-Service -Name $dhcpServiceName -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Send-Telegram "ALERT: DHCP service not found on $(hostname)"
        Start-Sleep -Seconds $intervalSec
        continue
    }
    if ($svc.Status -ne "Running") {
        Send-Telegram "ALERT: DHCP service is $($svc.Status) on $(hostname). Attempting restart..."
        try {
            Restart-Service -Name $dhcpServiceName -Force -ErrorAction Stop
            Send-Telegram "OK: DHCP service restarted on $(hostname)."
        } catch {
            Send-Telegram "FAIL: Could not restart DHCP service on $(hostname): $_"
        }
    }
    Start-Sleep -Seconds $intervalSec
}
