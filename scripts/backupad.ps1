<#
Backup-AD.ps1 (DATA-ONLY, no ACL/Owner)
- Full copy of C:\AD into \\backup\backup_server\AD\AD-YYYY-MM-DD_HH-mm
- Copies Data/Attributes/Timestamps (no ACL/Owner/SACL) -> avoids ERROR 1314
#>

$Source    = "C:\AD"
$RootDest  = "\\backup\backup_server\AD"
$Stamp     = Get-Date -Format "yyyy-MM-dd_HH-mm"
$Destination = Join-Path $RootDest ("AD-" + $Stamp)
$LogFile     = Join-Path $RootDest ("Backup-AD_" + $Stamp + ".log")

# --- Checks ---
if (-not (Test-Path -LiteralPath $Source)) { 
    Write-Error "Source not found: $Source"
    exit 1 
}
if (-not (Test-Path -LiteralPath $RootDest)) { 
    New-Item -Type Directory -Path $RootDest -Force | Out-Null 
}
if (-not (Test-Path -LiteralPath $Destination)) { 
    New-Item -Type Directory -Path $Destination -Force | Out-Null 
}

# --- Robocopy arguments ---
# /E        – all subdirectories including empty ones
# /COPY:DAT – copy Data, Attributes, Timestamps (skip ACL/Owner/Audit)
# /DCOPY:T  – preserve directory timestamps
# /R /W     – retry/wait
# /MT       – multithreaded copy
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

# --- Run robocopy ---
$proc = Start-Process -FilePath "robocopy" -ArgumentList $args -Wait -PassThru

if ($proc.ExitCode -le 3) {
    Write-Host "Backup completed: $Destination  (ExitCode=$($proc.ExitCode))"
    Write-Host "Log file: $LogFile"
} else {
    Write-Warning "Robocopy reported errors (ExitCode=$($proc.ExitCode)). Check log: $LogFile"
}
