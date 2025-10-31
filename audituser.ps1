<#
.SYNOPSIS
 Check a user's folder size on a fixed list of computers and save results + timestamp file.

.DESCRIPTION
 Prompts for serwis password and target folder name. Iterates only the specified hosts.
 Shows human-readable sizes inline and writes CSV and a timestamp TXT to C:\temp.
#>

# ---------- Prompt ----------
$targetUser = Read-Host "Enter the target user folder name (folder name, e.g. 'serwis')"
if ([string]::IsNullOrWhiteSpace($targetUser)) {
    Write-Error "Target user folder name cannot be empty. Exiting."
    exit 1
}

$serviceAccount = "$($env:USERDOMAIN)\serwis"
$securePass = Read-Host -Prompt "Enter password for $serviceAccount" -AsSecureString
$credential = New-Object System.Management.Automation.PSCredential($serviceAccount, $securePass)

# ---------- Exact list of computers ----------
$computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
) | Select-Object -Unique

# ---------- Paths to check remotely ----------
$basePaths = @("C:\dane","C:\ad","C:\Users")

# ---------- Helper: bytes -> readable ----------
function Convert-BytesToReadable {
    param([long]$bytes)
    if ($bytes -lt 1KB) { return ("{0} B" -f $bytes) }
    $sizes = "B","KB","MB","GB","TB","PB"
    $i = 0
    $d = [double]$bytes
    while ($d -ge 1024 -and $i -lt $sizes.Length-1) {
        $d = $d / 1024
        $i++
    }
    return ("{0:N2} {1}" -f $d, $sizes[$i])
}

# ---------- Results collection ----------
$results = @()

Write-Host "Scanning $($computers.Count) computers for folder '$targetUser'..." -ForegroundColor Cyan

foreach ($comp in $computers) {
    Write-Host -NoNewline ("{0,-18} : " -f $comp)
    try {
        $remote = Invoke-Command -ComputerName $comp -Credential $credential -ScriptBlock {
            param($userName, $bases)
            foreach ($base in $bases) {
                $fullPath = Join-Path -Path $base -ChildPath $userName
                if (Test-Path -LiteralPath $fullPath) {
                    $bytes = 0
                    try {
                        $sum = Get-ChildItem -LiteralPath $fullPath -Recurse -Force -ErrorAction Stop |
                               Where-Object { -not $_.PSIsContainer } |
                               Measure-Object -Property Length -Sum -ErrorAction Stop
                        $bytes = [long]$sum.Sum
                    } catch {
                        $bytes = 0
                        try {
                            $stack = New-Object System.Collections.Stack
                            $stack.Push((Get-Item -LiteralPath $fullPath -ErrorAction Stop))
                            while ($stack.Count -gt 0) {
                                $item = $stack.Pop()
                                if ($item.PSIsContainer) {
                                    try { 
                                        $children = Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop 
                                        foreach ($c in $children) { $stack.Push($c) }
                                    } catch {}
                                } else {
                                    try { $bytes += $item.Length } catch {}
                                }
                            }
                        } catch {}
                    }
                    return [PSCustomObject]@{
                        Computer  = $env:COMPUTERNAME
                        Path      = $fullPath
                        Exists    = $true
                        SizeBytes = $bytes
                    }
                }
            }
            return [PSCustomObject]@{
                Computer  = $env:COMPUTERNAME
                Path      = $null
                Exists    = $false
                SizeBytes = 0
            }
        } -ArgumentList $targetUser, $basePaths -ErrorAction Stop

        if ($remote.Exists -and $remote.SizeBytes -gt 0) {
            $sizeHR = Convert-BytesToReadable -bytes $remote.SizeBytes
            Write-Host ("{0} ({1})" -f $sizeHR, $remote.Path) -ForegroundColor Green
            $results += [PSCustomObject]@{
                Computer  = $comp; Path = $remote.Path; Exists = $true
                SizeBytes = $remote.SizeBytes; SizeHR = $sizeHR; Error = $null
            }
        } elseif ($remote.Exists -and $remote.SizeBytes -eq 0) {
            Write-Host ("0 B ({0})" -f $remote.Path) -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                Computer  = $comp; Path = $remote.Path; Exists = $true
                SizeBytes = 0; SizeHR = "0 B"; Error = $null
            }
        } else {
            Write-Host "Not found" -ForegroundColor DarkYellow
            $results += [PSCustomObject]@{
                Computer  = $comp; Path = $null; Exists = $false
                SizeBytes = 0; SizeHR = "Not found"; Error = $null
            }
        }
    } catch {
        $err = $_.Exception.Message
        Write-Host ("ERROR: {0}" -f $err) -ForegroundColor Red
        $results += [PSCustomObject]@{
            Computer = $comp; Path = $null; Exists = $false
            SizeBytes = 0; SizeHR = "ERROR"; Error = $err
        }
    }
}

# ---------- Save CSV ----------
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$outFile = "C:\temp\user-folder-sizes_$($targetUser)_$timestamp.csv"
if (-not (Test-Path "C:\temp")) { New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null }
$results | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

# ---------- Save TXT summary ----------
$txtFile = "C:\temp\scan_$($targetUser)_$timestamp.txt"
$txtContent = @()
$txtContent += "Scan timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$txtContent += "Target folder: $targetUser"
$txtContent += "Scanned hosts: $($computers.Count)"
$txtContent += "CSV output: $outFile"
$txtContent += ""
$txtContent += "Summary:"
foreach ($r in $results) {
    $txtContent += ("{0} - {1}" -f $r.Computer, $r.SizeHR)
}
$txtContent | Out-File -FilePath $txtFile -Encoding UTF8 -Force

Write-Host "`nSaved results to: $outFile" -ForegroundColor Cyan
Write-Host "Summary file: $txtFile" -ForegroundColor Cyan
Write-Host "Done." -ForegroundColor Green
