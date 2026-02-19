# Set encoding for correct character display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = "https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi"
$dest = "$env:TEMP\tailscale-setup.msi"

if (Test-Path $dest) { Remove-Item $dest -Force }

Write-Host "--- Starting Tailscale download process ---" -ForegroundColor Yellow

# 1. Download with progress
try {
    Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
    Write-Host "Download completed successfully!" -ForegroundColor Yellow
} catch {
    Write-Host "Download error: $_" -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = [System.Console]::ReadKey($true)
    exit
}

# 2. Installation
Write-Host "--- Starting Tailscale installation ---" -ForegroundColor Yellow
Write-Progress -Activity "Installing Tailscale" -Status "Running MSI package..." -PercentComplete 50

$installProcess = Start-Process msiexec.exe -ArgumentList "/i `"$dest`" /quiet /norestart" -Wait -PassThru

if ($installProcess.ExitCode -ne 0) {
    Write-Host "Installation failed. Exit Code: $($installProcess.ExitCode)" -ForegroundColor Red
    Write-Host "Ensure you are running PowerShell as Administrator." -ForegroundColor Red
    Write-Host "Press any key to exit..."
    $null = [System.Console]::ReadKey($true)
    exit
}

Write-Progress -Activity "Installing Tailscale" -Status "Done" -PercentComplete 100
Write-Host "Installation successful!" -ForegroundColor Yellow

# Wait for the service to initialize
Start-Sleep -Seconds 5

# 3. Authentication (Yellow text)
Write-Host ""
Write-Host "Enter your authentication code (AuthKey):" -ForegroundColor Yellow -NoNewline
$authKey = Read-Host " "

$tailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"

if (Test-Path $tailscaleExe) {
    Write-Host "Connecting to Tailscale..." -ForegroundColor Yellow
    
    # Execute connect command
    & $tailscaleExe up --authkey=$authKey --unattended --accept-routes
    
    # Wait a bit for the connection to establish
    Start-Sleep -Seconds 3
    
    # Verify connection status
    $status = & $tailscaleExe status
    if ($LASTEXITCODE -eq 0) {
        Write-Host "--- Connected successfully! ---" -ForegroundColor Green
        Write-Host $status -ForegroundColor Gray
    } else {
        Write-Host "Connection failed. Please check your AuthKey or network settings." -ForegroundColor Red
    }
} else {
    Write-Host "Critical error: tailscale.exe not found at $tailscaleExe" -ForegroundColor Red
}

# Cleanup and wait
if (Test-Path $dest) { Remove-Item $dest -Force }
Write-Host "`nProcess finished. Press any key to exit..." -ForegroundColor Gray
$null = [System.Console]::ReadKey($true)
