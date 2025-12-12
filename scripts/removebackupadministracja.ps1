<#
Prune-MultiRoots.ps1
Purpose:
  - For each backup root, keep only the N most recently created subdirectories
  - Delete older subdirectories (based on CreationTime)
Features:
  - Works per-root independently
  - Preview mode to show actions without deleting
  - Optional name filter (regex) to target only timestamped folders, etc.

Usage examples:
  .\Prune-MultiRoots.ps1
  .\Prune-MultiRoots.ps1 -Keep 5 -Preview
  .\Prune-MultiRoots.ps1 -Roots "\\backup\kadry","\\backup\sekretariat" -Keep 3 -NameFilter '^\w+-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}$'

Notes:
  - Requires delete permissions on the shares.
  - CreationTime is used as the sort key; adjust to LastWriteTime if preferred.
#>

param(
  # Roots to prune (per-root retention applied)
  [string[]]$Roots = @(
    "\\backup\kadry",
    "\\backup\sekretariat",
    "\\backup\ksiegowosc"
  ),

  # How many newest folders to keep in EACH root
  [int]$Keep = 3,

  # If set, do not delete — only show what would be removed
  [switch]$Preview,

  # Optional regex to filter folder names to consider (e.g., timestamped ones)
  [string]$NameFilter
)

function Prune-Root {
  param(
    [string]$Root,
    [int]$Keep,
    [switch]$Preview,
    [string]$NameFilter
  )

  Write-Host "`n== Root: $Root ==" -ForegroundColor Cyan

  if (-not (Test-Path -LiteralPath $Root)) {
    Write-Warning "Path not found: $Root. Skipping."
    return
  }

  # Get subdirectories; optionally filter by name (regex)
  $dirs = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop
  if ($NameFilter) {
    $dirs = $dirs | Where-Object { $_.Name -match $NameFilter }
  }

  if (-not $dirs -or $dirs.Count -le $Keep) {
    Write-Host "Nothing to delete. Found $($dirs.Count) director$(if($dirs.Count -eq 1){'y'}else{'ies'}) ; Keep=$Keep."
    return
  }

  # Sort newest › oldest by CreationTime
  $dirs = $dirs | Sort-Object CreationTime -Descending

  $toKeep   = $dirs | Select-Object -First $Keep
  $toDelete = $dirs | Select-Object -Skip $Keep

  Write-Host "Keeping $Keep newest:" -ForegroundColor Green
  $toKeep | ForEach-Object {
    Write-Host ("  - {0}  (Created: {1:yyyy-MM-dd HH:mm})" -f $_.FullName, $_.CreationTime)
  }

  Write-Host "Removing older:" -ForegroundColor Yellow
  $toDelete | ForEach-Object {
    Write-Host ("  - {0}  (Created: {1:yyyy-MM-dd HH:mm})" -f $_.FullName, $_.CreationTime)
  }

  if ($Preview) {
    Write-Host "Preview mode: no deletions performed." -ForegroundColor Magenta
    return
  }

  foreach ($d in $toDelete) {
    try {
      Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop
      Write-Host ("Deleted: {0}" -f $d.FullName) -ForegroundColor DarkGreen
    } catch {
      Write-Warning ("Failed to delete {0}: {1}" -f $d.FullName, $_.Exception.Message)
    }
  }
}

# --- Run for all roots ---
foreach ($r in $Roots) {
  Prune-Root -Root $r -Keep $Keep -Preview:$Preview -NameFilter $NameFilter
}
