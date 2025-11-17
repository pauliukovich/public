# ==============================
# Safe remote cleanup menu (verbose)
# Runs on AD server / admin PC (PowerShell 7)
# ==============================

# List of domain computers
$Computers = @(
    'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
    'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
    'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
    'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
    'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
    'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP',
    'BIBLIOTEKA-PC1','BIBLIOTEKA-PC2','BIBLIOTEKA-PC3','BIBLIOTEKA-PC4'
)

# Script that will run on each remote computer
$CleanupScript = @'
param()

$Computer = $env:COMPUTERNAME

# ----- Logging -----
$LogRoot = "C:\Temp\CleanupLogs"
if (-not (Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}
$LogFile = Join-Path $LogRoot ("Cleanup_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))

function Write-LogLine {
    param([string]$Message)
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
    $line | Tee-Object -FilePath $LogFile -Append | Out-Null
}

function Write-Status {
    param(
        [string]$Message,
        [string]$Color = "Gray"
    )
    $prefix = "[{0}] {1}" -f $Computer, $Message
    Write-Host $prefix -ForegroundColor $Color
    Write-LogLine $Message
}

Write-Status "===== Cleanup started =====" "Cyan"

# Free space before cleanup (disk C)
$drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
$FreeBefore = if ($drive) { [int64]$drive.Free } else { 0 }

# Helper: safe folder size
function Get-FolderSizeSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $sum = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Measure-Object -Property Length -Sum
        return [int64]($sum.Sum)
    } catch {
        return 0
    }
}

$EstimatedBytes = 0

Write-Status "Step 1/6: scanning folders to estimate reclaimable space..." "Yellow"

# ----- 1. Temp folders (system + users) -----
$tempPaths = @(
    "$env:SystemRoot\Temp",
    "C:\Windows\Temp",
    "$env:TEMP",
    "$env:TMP"
)

# Per-user temp folders
$userTemp = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('Public','Default','Default User','All Users') } |
    ForEach-Object { "C:\Users\{0}\AppData\Local\Temp" -f $_.Name }

$allTemp = ($tempPaths + $userTemp) | Sort-Object -Unique

foreach ($path in $allTemp) {
    if (Test-Path $path) {
        $EstimatedBytes += Get-FolderSizeSafe -Path $path
    }
}

# ----- 2. Windows Update download cache -----
$wuPath = "C:\Windows\SoftwareDistribution\Download"
if (Test-Path $wuPath) {
    $EstimatedBytes += Get-FolderSizeSafe -Path $wuPath
}

# ----- 3. Previous Windows installation (Windows.old) -----
$oldPath = "C:\Windows.old"
if (Test-Path $oldPath) {
    $EstimatedBytes += Get-FolderSizeSafe -Path $oldPath
}

$EstimatedGB = [Math]::Round($EstimatedBytes / 1GB, 2)
Write-Status ("Estimated reclaimable space: {0} GB" -f $EstimatedGB) "Green"

# ----- 2/6: clean temp -----
Write-Status "Step 2/6: cleaning temp folders..." "Yellow"

foreach ($path in $allTemp) {
    if (Test-Path $path) {
        Write-Status ("Cleaning temp folder: {0}" -f $path) "DarkGray"
        try {
            Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Status ("Error cleaning folder {0} - {1}" -f $path, $_.Exception.Message) "Red"
        }
    }
}

# ----- 3/6: recycle bin -----
Write-Status "Step 3/6: emptying recycle bins..." "Yellow"
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
} catch {
    Write-Status ("Clear-RecycleBin error - {0}" -f $_.Exception.Message) "Red"
}

# ----- 4/6: Windows Update cache -----
Write-Status "Step 4/6: cleaning Windows Update download cache..." "Yellow"
if (Test-Path $wuPath) {
    try {
        Write-Status "Stopping Windows Update services (wuauserv, bits)..." "DarkGray"
        net stop wuauserv /y | Out-Null
        net stop bits /y | Out-Null

        Write-Status "Removing files from SoftwareDistribution\Download..." "DarkGray"
        Get-ChildItem $wuPath -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        Write-Status "Starting Windows Update services..." "DarkGray"
        net start wuauserv | Out-Null
        net start bits | Out-Null
    } catch {
        Write-Status ("Windows Update cache cleanup error - {0}" -f $_.Exception.Message) "Red"
    }
} else {
    Write-Status "Windows Update cache folder not found, skipping." "DarkGray"
}

# ----- 5/6: DISM component cleanup -----
Write-Status "Step 5/6: running DISM /StartComponentCleanup (this may take a long time)..." "Yellow"
try {
    & dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null
    Write-Status "DISM component cleanup finished." "Green"
} catch {
    Write-Status ("DISM error - {0}" -f $_.Exception.Message) "Red"
}

# ----- 6/6: Windows.old -----
Write-Status "Step 6/6: removing Windows.old (if present)..." "Yellow"
if (Test-Path $oldPath) {
    try {
        Write-Status "Removing C:\Windows.old..." "DarkGray"
        Remove-Item $oldPath -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Status ("Error removing Windows.old - {0}" -f $_.Exception.Message) "Red"
    }
} else {
    Write-Status "Windows.old not found, skipping." "DarkGray"
}

# Free space after cleanup
$drive2 = Get-PSDrive -Name C -ErrorAction SilentlyContinue
$FreeAfter = if ($drive2) { [int64]$drive2.Free } else { 0 }
$FreedBytes = $FreeAfter - $FreeBefore
if ($FreedBytes -lt 0) { $FreedBytes = 0 }

$FreedGB = [Math]::Round($FreedBytes / 1GB, 2)

Write-Status ("Cleanup finished. Freed (by disk diff): {0} GB" -f $FreedGB) "Cyan"
Write-Status "===== Cleanup finished =====" "Cyan"

[PSCustomObject]@{
    ComputerName = $Computer
    EstimatedGB  = $EstimatedGB
    FreedGB      = $FreedGB
}
'@

function Show-Menu {
    Write-Host ""
    Write-Host "Available computers:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Computers.Count; $i++) {
        $index = $i + 1
        Write-Host ("{0,2}. {1}" -f $index, $Computers[$i])
    }
    Write-Host ""
    Write-Host "Type numbers separated by commas (e.g. 1,3,5) or 'all'" -ForegroundColor Yellow
}

# ---- Main menu ----
Show-Menu
$selection = Read-Host "Selection"

if ([string]::IsNullOrWhiteSpace($selection)) {
    Write-Host "No selection, exiting." -ForegroundColor Red
    return
}

if ($selection.Trim().ToLower() -eq "all") {
    $Targets = $Computers
} else {
    $numbers = $selection.Split(",") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }

    $indexes = @()
    foreach ($n in $numbers) {
        $tmp = 0
        if (-not [int]::TryParse($n, [ref]$tmp)) {
            Write-Host "Invalid number: $n" -ForegroundColor Red
            return
        }
        $idx = [int]$n
        if ($idx -lt 1 -or $idx -gt $Computers.Count) {
            Write-Host "Number out of range: $n" -ForegroundColor Red
            return
        }
        $indexes += ($idx - 1)
    }
    $Targets = $indexes | Sort-Object -Unique | ForEach-Object { $Computers[$_] }
}

if (-not $Targets -or $Targets.Count -eq 0) {
    Write-Host "No valid targets, exiting." -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "Selected computers:" -ForegroundColor Cyan
$Targets | ForEach-Object { Write-Host " - $_" }

$confirm = Read-Host "Start cleanup on these computers? (Y/N)"
if ($confirm.ToUpper() -ne "Y") {
    Write-Host "Canceled by user." -ForegroundColor Yellow
    return
}

# ---- Run cleanup on selected computers ----
$sb = [ScriptBlock]::Create($CleanupScript)
$total = $Targets.Count
$count = 0

foreach ($comp in $Targets) {
    $count++
    $percent = [int](($count / $total) * 100)

    Write-Progress -Activity "Remote cleanup" `
                   -Status "Cleaning $comp ($count of $total)" `
                   -PercentComplete $percent

    Write-Host ""
    Write-Host "[$count/$total] $comp - testing connectivity..." -ForegroundColor Yellow

    if (-not (Test-Connection -ComputerName $comp -Count 1 -Quiet)) {
        Write-Host "[$comp] Offline or unreachable." -ForegroundColor Red
        continue
    }

    Write-Host "[$comp] Connected, starting cleanup..." -ForegroundColor Green

    try {
        $result = Invoke-Command -ComputerName $comp -ScriptBlock $sb -ErrorAction Stop

        if ($result) {
            $est = "{0:N2}" -f $result.EstimatedGB
            $fre = "{0:N2}" -f $result.FreedGB
            Write-Host "[$comp] Summary → Estimated: $est GB, Freed (real): $fre GB" -ForegroundColor Green
        } else {
            Write-Host "[$comp] Cleanup finished, but no summary returned." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[$comp] Cleanup failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Progress -Activity "Remote cleanup" -Completed -Status "Done"
Write-Host ""
Write-Host "All tasks finished." -ForegroundColor Cyan
