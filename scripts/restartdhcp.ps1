# dhcp_quick_fix.ps1
# English comments only per user's preference
# Quick diagnostic and repair script for Windows DHCP server

# --- Settings ---
$dhcpServiceName = "DHCPServer"
$logDir = "C:\Temp\dhcp_incidents"
New-Item -Path $logDir -ItemType Directory -Force | Out-Null

# --- Helper: timestamped logfile ---
function Save-Output($name, $text){
    $file = Join-Path $logDir ("{0}_{1}.log" -f $name, (Get-Date -Format "yyyyMMdd_HHmmss"))
    $text | Out-File -FilePath $file -Encoding utf8
}

# --- 1) Basic state collection ---
"=== IPCONFIG ===" | Out-String | Save-Output -name "ipconfig"
ipconfig /all | Out-String | Save-Output -name "ipconfig_all"
"=== Net Adapters ===" | Out-String | Save-Output -name "netadapters"
Get-NetAdapter | Format-Table -AutoSize | Out-String | Save-Output -name "netadapter_status"
"=== Routes ===" | Out-String | Save-Output -name "routes"
Get-NetRoute | Out-String | Save-Output -name "routes"

# --- 2) Service status ---
$svc = Get-Service -Name $dhcpServiceName -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    "DHCP service not found: $dhcpServiceName" | Save-Output -name "service_check"
} else {
    $svc | Out-String | Save-Output -name "service_check"
}

# --- 3) Try graceful restart if service is stopped or faulted ---
if ($svc.Status -ne "Running") {
    "Service not running. Attempting Start-Service..." | Save-Output -name "service_action"
    try {
        Start-Service -Name $dhcpServiceName -ErrorAction Stop
        "Service started." | Save-Output -name "service_action"
    } catch {
        "Start failed: $_" | Save-Output -name "service_action"
    }
} else {
    "Service running. Attempting Restart-Service to refresh." | Save-Output -name "service_action"
    try { Restart-Service -Name $dhcpServiceName -Force -ErrorAction Stop; "Restart done." | Save-Output -name "service_action" }
    catch { "Restart failed: $_" | Save-Output -name "service_action" }
}

# --- 4) Flush DNS & renew server IP (if DHCP server has dynamic) ---
ipconfig /flushdns | Out-String | Save-Output -name "flushdns"
# If server uses DHCP for its own IP (rare), uncomment:
# ipconfig /release
# ipconfig /renew

# --- 5) Export relevant EventLog entries (System, Application) ---
Get-EventLog -LogName System -Newest 200 | Out-String | Save-Output -name "system_events"
Get-EventLog -LogName Application -Newest 200 | Out-String | Save-Output -name "app_events"

# --- 6) Optional: restart problematic network adapter by name (use with caution) ---
#$adapterName = "Ethernet"
#Restart-NetAdapter -Name $adapterName -Confirm:$false
#"Adapter restarted" | Save-Output -name "adapter_action"

# --- 7) If you have network diagnostic cmdlets: test connectivity to gateway and DNS ---
$gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object -First 1).NextHop
Test-Connection -ComputerName $gw -Count 3 | Out-String | Save-Output -name "gw_ping"
Resolve-DnsName -Name "google.com" -ErrorAction SilentlyContinue | Out-String | Save-Output -name "dns_test"

# --- 8) Pack summary ---
$files = Get-ChildItem -Path $logDir | Sort-Object LastWriteTime -Descending
"Saved logs to $logDir. Latest files:`n" + ($files | Select-Object -First 10 | Out-String) | Out-String | Save-Output -name "summary"
Write-Host "Diagnostics saved to $logDir"
