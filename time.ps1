# Force-TimeSync-WinRM.ps1
# PowerShell 7.x — WinRM sync with readable TXT log

# --- Computer list ---
$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
) | Sort-Object -Unique

# --- Log file (Readable TXT) ---
$TempDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $TempDir)) { 
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null 
}

$Stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$LogFile = Join-Path $TempDir ("Force-TimeSync-WinRM_{0}.txt" -f $Stamp)

# Header
"================ Force Time Sync Report ================" | Out-File $LogFile -Encoding UTF8
"Generated: $(Get-Date)"                                   | Out-File $LogFile -Append -Encoding UTF8
"=========================================================" | Out-File $LogFile -Append -Encoding UTF8
"" | Out-File $LogFile -Append -Encoding UTF8

# --- Session options ---
$SessionOption = New-PSSessionOption -OperationTimeout (New-TimeSpan -Seconds 25)

foreach ($Comp in $Computers) {
    try {
        $info = Invoke-Command -ComputerName $Comp `
                               -Authentication Default `
                               -ConfigurationName 'Microsoft.PowerShell' `
                               -SessionOption $SessionOption `
                               -ErrorAction Stop `
                               -ScriptBlock {

            Restart-Service w32time -Force -ErrorAction Stop
            w32tm /resync /rediscover /nowait > $null 2>&1

            $now    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $source = (w32tm /query /source 2>&1) -join ' '

            [pscustomobject]@{
                Host   = $env:COMPUTERNAME
                Time   = $now
                Source = $source
            }
        }

        Write-Host ("[OK]   {0} -> {1} | {2}" -f $info.Host, $info.Time, $info.Source) -ForegroundColor Green

        @"
Host:    $($info.Host)
Status:  OK
Time:    $($info.Time)
Source:  $($info.Source)
---------------------------------------------------------
"@ | Out-File $LogFile -Append -Encoding UTF8
    }
    catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }

        Write-Host ("[FAIL] {0} -> {1}" -f $Comp, $msg) -ForegroundColor Red

        @"
Host:    $Comp
Status:  FAIL
Error:   $msg
---------------------------------------------------------
"@ | Out-File $LogFile -Append -Encoding UTF8
    }
}

Write-Host ""
Write-Host ("Log saved to: {0}" -f $LogFile) -ForegroundColor Cyan

Read-Host -Prompt "Press Enter to exit"
