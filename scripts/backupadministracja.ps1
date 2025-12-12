<#
Multi-Backup.ps1
Purpose:
 - Create full timestamped backups of three local folders:
      C:\Kadry       › \\backup\kadry
      C:\Sekretariat › \\backup\sekretariat
      C:\Ksiegowosc  › \\backup\ksiegowosc
 - Each run creates a new folder named FolderName-YYYY-MM-DD_HH-mm
 - Copies data, attributes, and timestamps (no ACL/Owner to avoid ERROR 1314)
 - Creates a separate log file for each backup
Requirements:
 - Run with permissions to access source and destination paths
 - robocopy must be available (default in Windows)
#>

# --- Backup job definitions ---
$BackupJobs = @(
    @{ Source = "C:\Nowy folder\Kadry";        DestRoot = "\\backup\kadry" },
    @{ Source = "C:\Nowy folder\Sekretariat";  DestRoot = "\\backup\sekretariat" },
    @{ Source = "C:\Nowy folder\Ksiêgowoœæ";   DestRoot = "\\backup\ksiegowosc" }
)

# Timestamp used for all backups in this run
$Stamp = Get-Date -Format "yyyy-MM-dd_HH-mm"

foreach ($job in $BackupJobs) {
    $Source      = $job.Source
    $RootDest    = $job.DestRoot
    $DestFolder  = (Split-Path $Source -Leaf) + "-" + $Stamp
    $Destination = Join-Path $RootDest $DestFolder
    $LogFile     = Join-Path $RootDest ("Backup-" + (Split-Path $Source -Leaf) + "_" + $Stamp + ".log")

    Write-Host "=== Backing up $Source › $Destination ===" -ForegroundColor Cyan

    # Check if source exists
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Warning "Source $Source not found. Skipping."
        continue
    }

    # Ensure root destination exists
    if (-not (Test-Path -LiteralPath $RootDest)) {
        New-Item -ItemType Directory -Path $RootDest -Force | Out-Null
    }

    # Ensure target backup folder exists
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    # Robocopy arguments:
    # /E        – copy all subdirectories (including empty)
    # /COPY:DAT – copy Data, Attributes, Timestamps (skip ACL/Owner/Audit)
    # /DCOPY:T  – copy directory timestamps
    # /R:2 /W:5 – retry 2 times, wait 5 sec between retries
    # /MT:16    – multi-threading for faster copy
    # /LOG+     – append log file
    # /TEE      – show output in console as well as in log
    $args = @(
        "`"$Source`"",
        "`"$Destination`"",
        "/E",
        "/COPY:DAT",
        "/DCOPY:T",
        "/R:2",
        "/W:5",
        "/MT:16",
        "/LOG+:$LogFile",
        "/TEE"
    )

    # Run robocopy
    $proc = Start-Process -FilePath "robocopy" -ArgumentList $args -Wait -PassThru

    # Robocopy exit codes 0–3 are considered success/minor warnings
    if ($proc.ExitCode -le 3) {
        Write-Host "Backup completed: $Destination  (ExitCode=$($proc.ExitCode))" -ForegroundColor Green
        Write-Host "Log file: $LogFile"
    } else {
        Write-Warning "Robocopy reported errors (ExitCode=$($proc.ExitCode)). Check: $LogFile"
    }
}
