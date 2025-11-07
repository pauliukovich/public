<#
    Open port 22 and install OpenSSH on Windows (PowerShell 5.1)
    - Adds/ensures inbound firewall rule for TCP 22
    - Downloads OpenSSH MSI to C:\Temp
    - Installs it silently
#>

# --- Elevation check ---
function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}
if (-not (Test-IsAdmin)) {
    Write-Host "[ERROR] Run this script as Administrator." -ForegroundColor Red
    exit 1
}

# --- Settings ---
$RuleName   = "OpenSSH-In-TCP"
$Display    = "OpenSSH Server (TCP 22)"
$Port       = 22
$Url        = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi"
$DownloadTo = "C:\Temp\OpenSSH-Win64-v10.0.0.0.msi"

# --- Ensure TLS 1.2 for Invoke-WebRequest on older systems ---
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

# --- 1) Open inbound TCP/22 (idempotent) ---
$existing = Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[i] Firewall rule '$RuleName' already exists. Ensuring it's enabled and correct..." -ForegroundColor Yellow
    Set-NetFirewallRule -Name $RuleName -Enabled True -Action Allow -Direction Inbound | Out-Null
    Set-NetFirewallRule -Name $RuleName -Profile Any | Out-Null
    Set-NetFirewallRule -Name $RuleName -DisplayName $Display | Out-Null
    # Ensure port/protocol with a matching filter (recreate if needed)
    $ok = (Get-NetFirewallPortFilter -AssociatedNetFirewallRule $existing | Where-Object { $_.LocalPort -eq "$Port" -and $_.Protocol -eq "TCP" })
    if (-not $ok) {
        Remove-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
        New-NetFirewallRule -Name $RuleName -DisplayName $Display -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $Port -Profile Any | Out-Null
    }
} else {
    Write-Host "[i] Creating firewall rule for TCP $Port..." -ForegroundColor Cyan
    New-NetFirewallRule -Name $RuleName -DisplayName $Display -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $Port -Profile Any | Out-Null
}
Write-Host "[✓] Port 22 is allowed inbound by Windows Firewall." -ForegroundColor Green

# --- 2) Download OpenSSH MSI ---
$dir = Split-Path -Path $DownloadTo -Parent
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

Write-Host "[i] Downloading OpenSSH MSI..." -ForegroundColor Cyan
$downloaded = $false
try {
    Invoke-WebRequest -Uri $Url -OutFile $DownloadTo -UseBasicParsing -ErrorAction Stop
    $downloaded = $true
} catch {
    Write-Host "[!] Invoke-WebRequest failed, trying BITS..." -ForegroundColor Yellow
    try {
        Start-BitsTransfer -Source $Url -Destination $DownloadTo -ErrorAction Stop
        $downloaded = $true
    } catch {
        Write-Host "[x] Failed to download MSI: $($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }
}

if (-not (Test-Path $DownloadTo)) {
    Write-Host "[x] MSI file not found after download." -ForegroundColor Red
    exit 3
}
Write-Host "[✓] Downloaded: $DownloadTo" -ForegroundColor Green

# --- 3) Silent install ---
Write-Host "[i] Installing OpenSSH (silent)..." -ForegroundColor Cyan
$msiArgs = "/i `"$DownloadTo`" /qn /norestart"
$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Host "[x] msiexec failed with exit code $($proc.ExitCode)." -ForegroundColor Red
    exit $proc.ExitCode
}

Write-Host "[✓] OpenSSH installation completed." -ForegroundColor Green
Write-Host "[i] You may need to start and set services to auto-start:" -ForegroundColor Yellow
Write-Host "    Set-Service -Name sshd -StartupType Automatic; Start-Service sshd"
Write-Host "    Set-Service -Name ssh-agent -StartupType Manual; Start-Service ssh-agent"
