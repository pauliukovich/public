# Force-TimeSync-WinRM.ps1
# PowerShell 7.x (Windows)
# Forces time sync on multiple remote PCs via WinRM (WSMan).
# Output: Green = Success (shows current time + time source), Red = Fail.
# Prompts ONLY for the password of a fixed user.

# --- Computer list ---
$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
) | Sort-Object -Unique

# --- Fixed username (adjust domain if needed) ---
# Use 'sp6zabki\serwis' or 'sp6zabki.local\serwis' depending on your env.
$UserName = 'sp6zabki\serwis'

# --- Prompt only for password; build PSCredential ---
$SecurePwd = Read-Host -AsSecureString -Prompt "Enter password for '$UserName'"
$Cred = [pscredential]::new($UserName, $SecurePwd)

# --- Optional: faster failure on unreachable hosts ---
$SessionOption = New-PSSessionOption -OperationTimeout (New-TimeSpan -Seconds 25)

# --- Main loop (per-host try/catch to get clean per-target status) ---
foreach ($Comp in $Computers) {
    try {
        # In PowerShell 7, -ComputerName uses WSMan on Windows (requires WinRM on targets).
        $info = Invoke-Command -ComputerName $Comp `
                               -Credential $Cred `
                               -Authentication Default `
                               -ConfigurationName 'Microsoft.PowerShell' `
                               -SessionOption $SessionOption `
                               -ErrorAction Stop `
                               -ScriptBlock {
            # 1) Ensure Windows Time service is running, then force a resync
            Restart-Service w32time -Force -ErrorAction Stop
            # Rediscover NTP peers and resync; suppress noisy output
            w32tm /resync /rediscover /nowait > $null 2>&1

            # 2) Collect current time and source
            $now    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $source = (w32tm /query /source 2>&1) -join ' '

            [pscustomobject]@{
                Host   = $env:COMPUTERNAME
                Time   = $now
                Source = $source
            }
        }

        Write-Host ("[OK] {0} -> Time: {1} | Source: {2}" -f $info.Host, $info.Time, $info.Source) -ForegroundColor Green
    }
    catch {
        # Show concise root cause; common cases: WinRM disabled, firewall, DNS, creds
        $msg = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
        Write-Host ("[FAIL] {0} -> {1}" -f $Comp, $msg) -ForegroundColor Red
    }
}

# Keep console open if launched in a new window
Read-Host -Prompt "Press Enter to exit"
