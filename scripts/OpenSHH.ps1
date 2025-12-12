<#
    Remote install of OpenSSH via WinRM (PowerShell 5.1)
    - Prompts for target computer
    - Checks WinRM connectivity
    - Opens inbound TCP/22 on the target
    - Downloads and installs OpenSSH MSI on the target
#>

# --- Prompt for target ---
$Target = Read-Host "Enter target computer (NetBIOS or FQDN)"
if ([string]::IsNullOrWhiteSpace($Target)) {
    Write-Host "[ERROR] Target computer is required." -ForegroundColor Red
    exit 1
}

# Optional: ask for creds (domain-joined often works without). Press Cancel for current context.
try {
    $Cred = Get-Credential -Message "Credentials for $Target (DOMAIN\User) — Cancel to use current context"
} catch { $Cred = $null }

# --- Quick WinRM reachability check ---
try {
    if ($Cred) { Test-WSMan -ComputerName $Target -Credential $Cred -ErrorAction Stop | Out-Null }
    else       { Test-WSMan -ComputerName $Target -ErrorAction Stop | Out-Null }
} catch {
    Write-Host "[ERROR] WinRM is not reachable on $Target. Ensure PS Remoting is enabled and firewall allows TCP 5985/5986." -ForegroundColor Red
    exit 2
}

Write-Host "[i] Connecting to $Target via WinRM..." -ForegroundColor Cyan

# --- Parameters for remote block ---
$RuleName   = "OpenSSH-In-TCP"
$Display    = "OpenSSH Server (TCP 22)"
$Port       = 22
$Url        = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi"
$DownloadTo = "C:\Temp\OpenSSH-Win64-v10.0.0.0.msi"

$ScriptBlock = {
    param($RuleName,$Display,$Port,$Url,$DownloadTo)

    function Test-IsAdmin {
        try {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $p  = New-Object Security.Principal.WindowsPrincipal($id)
            return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
        } catch { return $false }
    }

    if (-not (Test-IsAdmin)) {
        Write-Host "[ERROR] Remote session is not elevated. Run this from an elevated console or use an account with admin rights on the target." -ForegroundColor Red
        exit 10
    }

    # Ensure TLS 1.2 for older .NET
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    Write-Host "=== OpenSSH remote setup on $env:COMPUTERNAME ===" -ForegroundColor Cyan

    # 1) Firewall rule TCP/22 (idempotent)
    $existing = Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[i] Firewall rule '$RuleName' exists. Ensuring settings..." -ForegroundColor Yellow
        Set-NetFirewallRule -Name $RuleName -Enabled True -Action Allow -Direction Inbound -Profile Any -DisplayName $Display | Out-Null
        $ok = (Get-NetFirewallPortFilter -AssociatedNetFirewallRule $existing | Where-Object { $_.LocalPort -eq "$Port" -and $_.Protocol -eq "TCP" })
        if (-not $ok) {
            Remove-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
            New-NetFirewallRule -Name $RuleName -DisplayName $Display -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $Port -Profile Any | Out-Null
        }
    } else {
        Write-Host "[i] Creating firewall rule for TCP $Port..." -ForegroundColor Cyan
        New-NetFirewallRule -Name $RuleName -DisplayName $Display -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $Port -Profile Any | Out-Null
    }
    Write-Host "[✓] Port 22 allowed inbound." -ForegroundColor Green

    # 2) Download MSI
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
            exit 20
        }
    }
    if (-not (Test-Path $DownloadTo)) {
        Write-Host "[x] MSI missing after download." -ForegroundColor Red
        exit 21
    }
    Write-Host "[✓] Downloaded: $DownloadTo" -ForegroundColor Green

    # 3) Silent install
    Write-Host "[i] Installing OpenSSH (silent)..." -ForegroundColor Cyan
    $msiArgs = "/i `"$DownloadTo`" /qn /norestart"
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "[x] msiexec failed with exit code $($proc.ExitCode)." -ForegroundColor Red
        exit $proc.ExitCode
    }

    # 4) Service setup info
    Write-Host "[✓] OpenSSH installation completed on $env:COMPUTERNAME." -ForegroundColor Green
    Write-Host "[i] Enable/start services (recommended):" -ForegroundColor Yellow
    Write-Host "    Set-Service -Name sshd -StartupType Automatic; Start-Service sshd"
    Write-Host "    Set-Service -Name ssh-agent -StartupType Manual; Start-Service ssh-agent"
}

# --- Execute remotely ---
try {
    if ($Cred) {
        Invoke-Command -ComputerName $Target -Credential $Cred -ScriptBlock $ScriptBlock -ArgumentList $RuleName,$Display,$Port,$Url,$DownloadTo -ErrorAction Stop
    } else {
        Invoke-Command -ComputerName $Target -ScriptBlock $ScriptBlock -ArgumentList $RuleName,$Display,$Port,$Url,$DownloadTo -ErrorAction Stop
    }
    Write-Host "[DONE] OpenSSH deployment to $Target finished." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Remote execution failed on $Target: $($_.Exception.Message)" -ForegroundColor Red
    exit 99
}
