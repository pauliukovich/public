# ==============================
# Atmystic AI World - Downloader (PS5/PS7)
# ==============================

# Force TLS 1.2 for old .NET stacks (IWR/WebClient reliability)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# --- Center helper ---
function Write-Center {
    param(
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Blue
    )
    $width = $Host.UI.RawUI.WindowSize.Width
    $pad = [math]::Max(0, [math]::Floor(($width - $Text.Length) / 2))
    Write-Host (" " * $pad + $Text) -ForegroundColor $Color
}

# --- Big green OM banner ---
Write-Host ""
Write-Center "Atmystic Design"
Write-Host ""

# --- Greeting & prompt (English UI) ---
Write-Center "Welcome to Atmystic AI World Scripts."
Write-Center "Please type the script filename you want to download from your repository."
Write-Center "Example: delete.ps1  (you may enter any .ps1 name located at the repo root)"
Write-Host ""
$FileName = Read-Host "Filename to download"

# --- Basic normalization/validation ---
if ([string]::IsNullOrWhiteSpace($FileName)) { $FileName = "delete.ps1" }
if ($FileName -notmatch '\.ps1$') { $FileName = "$FileName.ps1" }
if ($FileName -notmatch '^[\w\-. ]+\.ps1$') {
    Write-Center "Invalid filename. Allowed: letters, numbers, underscore, dash, dot, spaces; must end with .ps1" -Color Red
    exit 1
}

# --- Build URLs/paths ---
$BaseUrl = 'https://raw.githubusercontent.com/pauliukovich/public/refs/heads/main/'
$Url    = ($BaseUrl + $FileName)
$OutDir = 'C:\atmystic.pl'
$Out    = Join-Path $OutDir $FileName

# --- Ensure destination folder exists ---
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
}

# --- Download with IWR and fallback to WebClient ---
try {
    Write-Center "Downloading $Url -> $Out"
    Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing -ErrorAction Stop
    Write-Center "Done: $Out"
} catch {
    Write-Center ("Failed to download: {0}" -f $_.Exception.Message) -Color Red
    try {
        (New-Object System.Net.WebClient).DownloadFile($Url, $Out)
        Write-Center "Alternative download successful: $Out"
    } catch {
        Write-Center ("Alternative attempt failed: {0}" -f $_.Exception.Message) -Color Red
        exit 1
    }
}

# --- Farewell (English + Sanskrit) ---
Write-Host ""
Write-Center "Have a great day"
