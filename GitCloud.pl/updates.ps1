[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Target path for GitCloud template
$folder = "C:\Windows\database\updates\"
$outFile = "$folder\updates.txt"

# Ensure folder exists
if (!(Test-Path $folder)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}

Write-Host "Checking Windows Update status on $env:COMPUTERNAME ..." -ForegroundColor Cyan

try {
    # Create Windows Update COM session
    $session  = New-Object -ComObject 'Microsoft.Update.Session'
    $searcher = $session.CreateUpdateSearcher()

    # Only software updates that are not installed
    $criteria = "IsInstalled=0 and Type='Software'"
    $searchResult = $searcher.Search($criteria)
} catch {
    Write-Error "Failed to query Windows Update via COM: $_"
    return
}

$pendingCount = $searchResult.Updates.Count

# Parse updates
$updates = @()

for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
    $u = $searchResult.Updates.Item($i)

    $isSecurity = $false

    if ($u.Categories) {
        foreach ($cat in $u.Categories) {
            if ($cat.Name -match 'Security') {
                $isSecurity = $true
                break
            }
        }
    }

    # Fallback check
    if (-not $isSecurity -and $u.Title -match 'Security Update') {
        $isSecurity = $true
    }

    $updates += [PSCustomObject]@{
        Title      = $u.Title
        IsSecurity = $isSecurity
    }
}

$securityCount = ($updates | Where-Object { $_.IsSecurity }).Count
$otherCount    = $pendingCount - $securityCount

$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# Build text report
$lines = @()
$lines += "===== WINDOWS UPDATE STATUS ====="
$lines += "Server : $env:COMPUTERNAME"
$lines += "Date   : $now"
$lines += ""
$lines += "Pending Updates : $pendingCount"
$lines += "Security Updates: $securityCount"
$lines += "Other Updates   : $otherCount"
$lines += ""
$lines += "Top pending updates:"

if ($pendingCount -eq 0) {
    $lines += " - No pending updates."
} else {
    $updates |
        Select-Object -First 10 |
        ForEach-Object {
            $lines += " - $($_.Title)"
        }
}

# Output to console
$lines | ForEach-Object { Write-Host $_ }

# Save to template file
$lines | Out-File -FilePath $outFile -Encoding UTF8 -Force

Write-Host "`nUpdate status saved to: $outFile" -ForegroundColor Cyan
