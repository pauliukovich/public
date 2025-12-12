<#
Prune-ADBackup.ps1
Purpose:
  - In \\backup\backup_server\AD keep ONLY the newest subdirectory
  - Delete all older ones (based on CreationTime)
Requirements:
  - Run with delete permissions on the share
#>

$Root = "\\backup\backup_server\AD"
$Keep = 1   # how many newest directories to keep

if (-not (Test-Path -LiteralPath $Root)) {
    Write-Error "Path not found: $Root"
    exit 1
}

# Get all subdirectories, sorted by CreationTime (newest first)
$dirs = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop |
        Sort-Object CreationTime -Descending

if ($dirs.Count -le $Keep) {
    Write-Host "Nothing to delete. Found $($dirs.Count) director$(if($dirs.Count -eq 1){'y'}else{'ies'}), Keep=$Keep."
    exit 0
}

$toKeep   = $dirs | Select-Object -First $Keep
$toDelete = $dirs | Select-Object -Skip $Keep

Write-Host "Keeping the newest directory:" -ForegroundColor Green
$toKeep | ForEach-Object {
    Write-Host ("  - {0} (Created: {1:yyyy-MM-dd HH:mm})" -f $_.FullName, $_.CreationTime)
}

Write-Host "Removing older directories:" -ForegroundColor Yellow
foreach ($d in $toDelete) {
    try {
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop
        Write-Host ("Deleted: {0}" -f $d.FullName) -ForegroundColor DarkGreen
    } catch {
        Write-Warning ("Failed to delete {0}: {1}" -f $d.FullName, $_.Exception.Message)
    }
}
