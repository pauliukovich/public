# ==========================================
# Download + Run GitHub Script + Log Output
# ==========================================

$Url        = "https://raw.githubusercontent.com/pauliukovich/gitcloud.pl/refs/heads/scripts/backup_data.ps1?token=GHSAT0AAAAAADQIOMWNUJ3ATQ7JTQYCWEVA2JLBV3A"
$TempDir    = "C:\Temp"
$TempScript = Join-Path $TempDir "remote_backup_run.ps1"
$LogFile    = Join-Path $TempDir "backup_log1.txt"

# Create C:\Temp if it doesn't exist
if (!(Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# Download file
try {
    Invoke-WebRequest -Uri $Url -OutFile $TempScript -UseBasicParsing
} catch {
    $msg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ERROR: Failed to download script from GitHub."
    Add-Content -Path $LogFile -Value $msg
    exit 1
}

# Run script and capture output
try {
    $output = & pwsh $TempScript 2>&1
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$timestamp SUCCESS:"
    Add-Content -Path $LogFile -Value $output
    Add-Content -Path $LogFile -Value "------------------------------------"
} catch {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$timestamp ERROR while executing script:"
    Add-Content -Path $LogFile -Value $_
    Add-Content -Path $LogFile -Value "------------------------------------"
}

# Remove temp file
Remove-Item $TempScript -Force -ErrorAction SilentlyContinue
