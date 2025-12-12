# Disk-Only-From-List_NoPrompt.ps1
# PowerShell 5.1 / 7
# Проверяет диски ТОЛЬКО из фиксированного списка хостов.
# Результат всегда сохраняется в C:\Windows\database\auditdisk\auditdisk.txt

$HostList = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
)

# --- STATIC OUTPUT FILE ---
$OutDir = 'C:\Windows\database\auditdisk'
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$ReportFile = Join-Path $OutDir "auditdisk.txt"

Write-Host ">>> Checking ONLINE hosts from fixed list..." -ForegroundColor Cyan

# --- ONLINE check ---
$online = @()

foreach ($h in $HostList) {
    $ping = Test-Connection -ComputerName $h -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($ping) {
        Write-Host " - $h ONLINE" -ForegroundColor Green
        $online += $h
    } else {
        Write-Host " - $h OFFLINE" -ForegroundColor DarkYellow
    }
}

if ($online.Count -eq 0) {
    Write-Host "No online hosts. Stopping." -ForegroundColor Red
    return
}

# --- ScriptBlock for WMI Disk Query ---
$WmiDisksBlock = {
    $rows = @()
    try {
        $logical = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3"
        foreach($d in $logical){
            $sizeGB = if($d.Size){ [math]::Round(($d.Size/1GB),2) } else { $null }
            $freeGB = if($d.FreeSpace){ [math]::Round(($d.FreeSpace/1GB),2) } else { $null }
            $pct = 0
            if ($d.Size -gt 0) { $pct = [math]::Round(($d.FreeSpace/$d.Size)*100,1) }

            $rows += [pscustomobject]@{
                Computer = $env:COMPUTERNAME
                Drive    = $d.DeviceID
                FreeGB   = $freeGB
                SizeGB   = $sizeGB
                FreePct  = $pct
            }
        }
    } catch {}
    return $rows
}

Write-Host "`n>>> Collecting disk info..." -ForegroundColor Cyan

$allRows = New-Object System.Collections.Generic.List[object]

foreach ($node in $online | Sort-Object) {
    Write-Host " - Querying $node" -ForegroundColor DarkCyan

    $rows = $null
    try {
        $rows = Invoke-Command -ComputerName $node -ScriptBlock $WmiDisksBlock -ErrorAction Stop
    } catch {
        $rows = $null
    }

    if ($rows -and $rows.Count -gt 0) {
        foreach ($r in $rows) {
            Write-Host ("[{0}] [DISK] {1} free {2}GB ({3}%) of {4}GB" -f $r.Computer,$r.Drive,$r.FreeGB,$r.FreePct,$r.SizeGB) -ForegroundColor Green
            $allRows.Add($r) | Out-Null
        }
    } else {
        # ВАЖНО: используем ${node}, чтобы не ломался парсер из-за двоеточия
        Write-Host "   ${node}: Access denied or no disks found" -ForegroundColor DarkYellow
    }
}

# --- Save TSV (overwrite) ---
"Computer`tDrive`tFreeGB`tSizeGB`tFreePct" | Out-File -FilePath $ReportFile -Encoding ASCII -Force

foreach ($r in ($allRows | Sort-Object Computer,Drive)) {
    ("{0}`t{1}`t{2}`t{3}`t{4}" -f $r.Computer,$r.Drive,$r.FreeGB,$r.SizeGB,$r.FreePct) |
        Out-File -FilePath $ReportFile -Append -Encoding ASCII
}

Write-Host "`nDone. Saved to $ReportFile" -ForegroundColor Green
