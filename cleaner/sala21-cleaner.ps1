$Computer = "sala21-lap"

Invoke-Command -ComputerName $Computer -ScriptBlock {

    function Get-FolderSize {
        param($Path)
        if (-not (Test-Path $Path)) { return 0 }

        (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
         Where-Object { -not $_.PSIsContainer } |
         Measure-Object Length -Sum).Sum
    }

    Write-Host "=== CLEANUP PREVIEW (NO PROFILE DELETION) ===" -ForegroundColor Cyan

    $TotalBytes = 0
    $Report = @()

    Get-ChildItem C:\Users -Directory | ForEach-Object {

        $User = $_.Name
        $UserBytes = 0

        $Paths = @(
            "$($_.FullName)\Downloads",
            "$($_.FullName)\AppData\Local\Temp"
        )

        foreach ($Path in $Paths) {
            $size = Get-FolderSize $Path
            $UserBytes += $size
            $TotalBytes += $size
        }

        if ($UserBytes -gt 0) {
            $Report += [PSCustomObject]@{
                User = $User
                SizeMB = [math]::Round($UserBytes / 1MB, 2)
            }
        }
    }

    # Windows-level cleanup targets
    $WinTemp = Get-FolderSize "C:\Windows\Temp"
    $WUCache = Get-FolderSize "C:\Windows\SoftwareDistribution\Download"

    $TotalBytes += $WinTemp + $WUCache

    $TotalMB = [math]::Round($TotalBytes / 1MB, 2)
    $TotalGB = [math]::Round($TotalBytes / 1GB, 2)

    Write-Host ""
    Write-Host "Per-user cleanup estimate:" -ForegroundColor White
    $Report | Sort-Object SizeMB -Descending | Format-Table -AutoSize

    Write-Host ""
    Write-Host "Windows Temp   : $([math]::Round($WinTemp / 1MB,2)) MB"
    Write-Host "Update Cache   : $([math]::Round($WUCache / 1MB,2)) MB"

    Write-Host ""
    Write-Host "--------------------------------------------"
    Write-Host "TOTAL SPACE TO BE FREED:" -ForegroundColor White
    Write-Host "$TotalMB MB  ($TotalGB GB)" -ForegroundColor Yellow
    Write-Host "--------------------------------------------"
    Write-Host ""

    # =========================
    # CLEANUP (NO PROFILES)
    # =========================

    Write-Host "Starting cleanup..." -ForegroundColor Cyan

    Get-ChildItem C:\Users -Directory | ForEach-Object {

        $Temp = "$($_.FullName)\AppData\Local\Temp"
        if (Test-Path $Temp) {
            Remove-Item "$Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        }

        $Downloads = "$($_.FullName)\Downloads"
        if (Test-Path $Downloads) {
            Remove-Item "$Downloads\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

    Stop-Service wuauserv -Force
    Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv

    Write-Host ""
    Write-Host "=== CLEANUP COMPLETED (PROFILES PRESERVED) ===" -ForegroundColor Green
}
