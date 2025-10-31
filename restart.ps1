# PowerShell 7+
# Force reboot of multiple remote PCs via WinRM

$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
)

# Settings
$ForceRestart = $true
$DelayBeforeSeconds = 0
$ThrottleLimit = 24

$Cred = Get-Credential -Message "Enter account with rights to restart remotely"

Write-Host "Starting reboot for $($Computers.Count) computers..." -ForegroundColor Yellow

$results = $Computers | ForEach-Object -Parallel {
    try {
        $comp = $_
        $delay = $using:DelayBeforeSeconds
        $force = $using:ForceRestart
        $cred  = $using:Cred

        if ($delay -gt 0) {
            $args = '/r','/t',$delay,'/c','Planned restart by administrator'
            if ($force) { $args += '/f' }

            Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                param($a) Start-Process -FilePath "shutdown.exe" -ArgumentList $a -WindowStyle Hidden
            } -ArgumentList ($args -join " ") -ErrorAction Stop

            [pscustomobject]@{Computer=$comp;Status="OK";Mode="SCHEDULED:$delay"}
        }
        else {
            Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                Restart-Computer -Force
            } -ErrorAction Stop

            [pscustomobject]@{Computer=$comp;Status="OK";Mode="INSTANT"}
        }
    }
    catch {
        [pscustomobject]@{Computer=$_;Status="FAIL";Error=$_.Exception.Message}
    }
} -ThrottleLimit $ThrottleLimit

$results | Format-Table -AutoSize
