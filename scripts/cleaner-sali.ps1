$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
)

$ReportFile = "C:\database\cleaner\cleaner-sali.txt"
$ReportDir  = Split-Path $ReportFile -Parent

if (!(Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
}

"===== CLEANER REPORT =====" | Out-File $ReportFile -Encoding UTF8
"DATE=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content $ReportFile
"" | Add-Content $ReportFile

foreach ($Computer in $Computers) {

    Add-Content $ReportFile "[COMPUTER]"
    Add-Content $ReportFile "NAME=$Computer"

    if (-not (Test-Connection $Computer -Count 1 -Quiet)) {
        Add-Content $ReportFile "STATUS=OFFLINE"
        Add-Content $ReportFile ""
        Add-Content $ReportFile "----------------------------"
        Add-Content $ReportFile ""
        continue
    }

    try {
        $Data = Invoke-Command -ComputerName $Computer -ErrorAction Stop -ScriptBlock {

            function Get-FreeGB {
                (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
            }

            function Clean-Folder($Path) {
                if (Test-Path $Path) {
                    Remove-Item "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            $FreeBefore = Get-FreeGB

            Get-ChildItem C:\Users -Directory | ForEach-Object {
                Clean-Folder "$($_.FullName)\Downloads"
                Clean-Folder "$($_.FullName)\AppData\Local\Temp"
            }

            Clean-Folder "C:\Windows\Temp"

            Stop-Service wuauserv -Force
            Clean-Folder "C:\Windows\SoftwareDistribution\Download"
            Start-Service wuauserv

            $FreeAfter = Get-FreeGB

            return [PSCustomObject]@{
                FreeBefore = [math]::Round($FreeBefore, 2)
                FreeAfter  = [math]::Round($FreeAfter, 2)
                Freed      = [math]::Round(($FreeAfter - $FreeBefore), 2)
            }
        }

        Add-Content $ReportFile "STATUS=OK"
        Add-Content $ReportFile "DISK_C_BEFORE_GB=$($Data.FreeBefore)"
        Add-Content $ReportFile "DISK_C_AFTER_GB=$($Data.FreeAfter)"
        Add-Content $ReportFile "DISK_C_FREED_GB=$($Data.Freed)"
    }
    catch {
        Add-Content $ReportFile "STATUS=ERROR"
    }

    Add-Content $ReportFile ""
    Add-Content $ReportFile "----------------------------"
    Add-Content $ReportFile ""
}

Add-Content $ReportFile "===== END OF REPORT ====="
