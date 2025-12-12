# Force-TimeSync-Manual-WinRM.ps1
# PowerShell 7.x (Windows)
# Uses current domain credentials (Kerberos)

# Ask for target computer
$Comp = Read-Host "Enter computer name"

if ([string]::IsNullOrWhiteSpace($Comp)) {
    Write-Host "No computer name provided. Exiting." -ForegroundColor Red
    exit 1
}

# Temp folder + log
$TempDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}
$Stamp   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$TmpFile = Join-Path $TempDir ("Force-TimeSync_{0}.log" -f $Stamp)

"Status;Host;Time;SourceOrError" | Out-File -FilePath $TmpFile -Encoding UTF8 -Force

# WinRM session options (faster fail)
$SessionOption = New-PSSessionOption -OperationTimeout (New-TimeSpan -Seconds 25)

Write-Host ""
Write-Host "Syncing time on $Comp ..." -ForegroundColor Cyan

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

    Write-Host ("[OK]   {0} -> Time: {1} | Source: {2}" -f $info.Host, $info.Time, $info.Source) -ForegroundColor Green
    ("OK;{0};{1};{2}" -f $info.Host, $info.Time, ($info.Source -replace ';',',')) | Out-File -FilePath $TmpFile -Append -Encoding UTF8
}
catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    Write-Host ("[FAIL] {0} -> {1}" -f $Comp, $msg) -ForegroundColor Red
    ("FAIL;{0};;{1}" -f $Comp, ($msg -replace ';',',')) | Out-File -FilePath $TmpFile -Append -Encoding UTF8
}

Write-Host ""
Write-Host ("Log saved to: {0}" -f $TmpFile) -ForegroundColor Yellow
Read-Host -Prompt "Press Enter to exit"
