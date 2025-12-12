# Remote Power Options Policy Deployment
# Hides only "Shut down" button, keeps "Restart" and "Sign out"
# Runs via WinRM on multiple remote machines and generates TXT report.

# ===================== CONFIG =====================
$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP',
  'BIBLIOTEKA-PC1','BIBLIOTEKA-PC2','BIBLIOTEKA-PC3','BIBLIOTEKA-PC4'
)

# Folder for reports
$ReportFolder = "C:\Temp"

# ===================== PREPARE =====================
if (-not (Test-Path $ReportFolder)) {
    New-Item -ItemType Directory -Path $ReportFolder | Out-Null
}

$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$fileStamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile  = Join-Path $ReportFolder "PowerOptionsPolicyReport_$fileStamp.txt"

# Collection for per-machine results
$Results = @()

# ===================== REMOTE SCRIPT =====================
$remoteScript = {
    param()

    # Base path for PolicyManager Start settings
    $basePath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Start'

    if (-not (Test-Path $basePath)) {
        New-Item -Path $basePath -Force | Out-Null
    }

    # 1 = hidden, 0 = visible
    $settings = @{
        'HideShutDown'  = 1  # hide "Shut down"
        'HideRestart'   = 0  # keep "Restart"
        'HideSignOut'   = 0  # keep "Sign out"
        'HideSleep'     = 1  # hide "Sleep"
        'HideHibernate' = 1  # hide "Hibernate"
    }

    foreach ($name in $settings.Keys) {
        $keyPath = Join-Path $basePath $name

        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }

        New-ItemProperty -Path $keyPath -Name 'value' -PropertyType DWord -Value $settings[$name] -Force | Out-Null
    }

    # Read back values for logging
    $obj = [PSCustomObject]@{
        HideShutDown  = (Get-ItemProperty -Path (Join-Path $basePath 'HideShutDown')  -Name 'value' -ErrorAction SilentlyContinue).value
        HideRestart   = (Get-ItemProperty -Path (Join-Path $basePath 'HideRestart')   -Name 'value' -ErrorAction SilentlyContinue).value
        HideSignOut   = (Get-ItemProperty -Path (Join-Path $basePath 'HideSignOut')   -Name 'value' -ErrorAction SilentlyContinue).value
        HideSleep     = (Get-ItemProperty -Path (Join-Path $basePath 'HideSleep')     -Name 'value' -ErrorAction SilentlyContinue).value
        HideHibernate = (Get-ItemProperty -Path (Join-Path $basePath 'HideHibernate') -Name 'value' -ErrorAction SilentlyContinue).value
    }

    return $obj
}

# ===================== MAIN LOOP =====================
foreach ($pc in $Computers) {
    Write-Host "[$pc] Processing..." -ForegroundColor Cyan

    $reachable = $true
    $status    = "UNKNOWN"
    $errorMsg  = $null
    $hideShutdown  = $null
    $hideRestart   = $null
    $hideSignOut   = $null
    $hideSleep     = $null
    $hideHibernate = $null

    if (-not (Test-WSMan -ComputerName $pc -ErrorAction SilentlyContinue)) {
        Write-Host "[$pc] WinRM not reachable, skipping." -ForegroundColor Yellow
        $reachable = $false
        $status    = "UNREACHABLE"
    }
    else {
        try {
            $result = Invoke-Command -ComputerName $pc -ScriptBlock $remoteScript -ErrorAction Stop

            if ($result) {
                $status        = "SUCCESS"
                $hideShutdown  = $result.HideShutDown
                $hideRestart   = $result.HideRestart
                $hideSignOut   = $result.HideSignOut
                $hideSleep     = $result.HideSleep
                $hideHibernate = $result.HideHibernate

                Write-Host "[$pc] SUCCESS: shutdown hidden, restart/sign out allowed." -ForegroundColor Green
            }
            else {
                $status   = "NO_DATA"
                $errorMsg = "Remote script returned no data."
                Write-Host "[$pc] WARNING: remote script returned no data." -ForegroundColor Yellow
            }
        }
        catch {
            $status   = "FAILED"
            $errorMsg = $_.Exception.Message
            Write-Host "[$pc] ERROR: $errorMsg" -ForegroundColor Red
        }
    }

    $Results += [PSCustomObject]@{
        ComputerName  = $pc
        Reachable     = $reachable
        Status        = $status
        Error         = $errorMsg
        HideShutDown  = $hideShutdown
        HideRestart   = $hideRestart
        HideSignOut   = $hideSignOut
        HideSleep     = $hideSleep
        HideHibernate = $hideHibernate
    }
}

# ===================== BUILD TXT REPORT =====================
$total        = $Results.Count
$successful   = ($Results | Where-Object { $_.Status -eq 'SUCCESS' }).Count
$failed       = ($Results | Where-Object { $_.Status -eq 'FAILED' }).Count
$unreachable  = ($Results | Where-Object { $_.Status -eq 'UNREACHABLE' }).Count

$reportLines = @()

$reportLines += "¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦"
$reportLines += "        REMOTE POWER OPTIONS POLICY DEPLOYMENT"
$reportLines += "¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦"
$reportLines += ""
$reportLines += "Execution Date:     $timestamp"
$reportLines += "Executed By:        $($env:USERNAME)"
$reportLines += "Deployment Method:  WinRM Remote PowerShell"
$reportLines += 'Policy Applied:     Hide "Shut down" button'
$reportLines += '                   Keep "Restart" and "Sign out"'
$reportLines += '                   Hide "Sleep" and "Hibernate"'
$reportLines += ""
$reportLines += "¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦"
$reportLines += "              DEPLOYMENT SUMMARY BY COMPUTER"
$reportLines += "¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦"
$reportLines += ""

foreach ($r in $Results) {
    $reportLines += "Machine Name:       $($r.ComputerName)"
    $reportLines += "Reachable:          $($r.Reachable)"
    $reportLines += "Execution Status:   $($r.Status)"
    $reportLines += "Error Message:      $($r.Error)"
    $reportLines += "Applied Settings:"
    $reportLines += "    HideShutDown   = $($r.HideShutDown)"
    $reportLines += "    HideRestart    = $($r.HideRestart)"
    $reportLines += "    HideSignOut    = $($r.HideSignOut)"
    $reportLines += "    HideSleep      = $($r.HideSleep)"
    $reportLines += "    HideHibernate  = $($r.HideHibernate)"
    $reportLines += ""
    $reportLines += "¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦"
    $reportLines += ""
}

$reportLines += "OVERALL STATISTICS"
$reportLines += "¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦"
$reportLines += "Total Machines:       $total"
$reportLines += "Successful:           $successful"
$reportLines += "Failed:               $failed"
$reportLines += "Unreachable:          $unreachable"
$reportLines += ""
$reportLines += "Notes:"
$reportLines += "- Users may need to sign out or reboot for Start menu changes to fully apply."
$reportLines += "- If some machines revert settings, check for overriding Group Policy."
$reportLines += "- Fix WinRM connectivity issues for unreachable machines, then rerun."
$reportLines += ""
$reportLines += "¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦"
$reportLines += "                     END OF REPORT"
$reportLines += "¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦¦"

$reportLines | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host ""
Write-Host "Report saved to: $reportFile" -ForegroundColor Magenta
