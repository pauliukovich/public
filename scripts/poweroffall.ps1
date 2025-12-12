<#
Shutdown-SelectedHosts-NoPrompt-Diag.ps1
- Uses current process credentials (no prompts).
- Writes a detailed transcript + report to C:\temp.
- Keeps the window open at the end (Read-Host "Press Enter...").
- Safe timeouts so it won't hang on dead hosts.
#>

# --- Session safety & visibility ---
$ErrorActionPreference = 'Stop'                # make errors terminating so we can catch them
$ProgressPreference    = 'SilentlyContinue'    # no noisy progress bars
Set-StrictMode -Version Latest

# --- Quick execution policy escape for this process only (harmless if already ok) ---
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch {}

# --- Paths & logs ---
$ReportDir = 'C:\temp'
if (-not (Test-Path $ReportDir)) { New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null }
$ts          = (Get-Date).ToString('yyyyMMdd_HHmmss')
$ReportPath  = Join-Path $ReportDir "shutdown_report_$ts.txt"
$Transcript  = Join-Path $ReportDir "shutdown_transcript_$ts.log"

# Start full transcript (captures console + errors)
try { Start-Transcript -Path $Transcript -Append -ErrorAction SilentlyContinue } catch {}

# --- Elevation check (warn, but don't hard-exit) ---
function Test-IsElevated {
    try {
        $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
        $wp = New-Object Security.Principal.WindowsPrincipal($wi)
        return $wp.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}
if (-not (Test-IsElevated)) {
    Write-Warning "Not running elevated. Run PowerShell as Administrator for reliable WinRM access."
}

# --- Parameters ---
[int]   $PingTimeoutMs       = 1000
[int]   $OperationTimeoutSec = 20

# --- Targets ---
$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP',
  'BIBLIOTEKA-PC1','BIBLIOTEKA-PC2','BIBLIOTEKA-PC3','BIBLIOTEKA-PC4'
)

# --- Helper: ping check ---
function Test-HostOnline {
    param([string]$HostName, [int]$TimeoutMs)
    try {
        $sec = [math]::Ceiling($TimeoutMs/1000)
        return Test-Connection -ComputerName $HostName -Count 1 -Quiet -TimeoutSeconds $sec
    } catch { return $false }
}

# --- Report header ---
$report = [System.Collections.Generic.List[string]]::new()
$report.Add("Shutdown Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("RunningAs       = $(whoami)")
$report.Add("PingTimeoutMs   = $PingTimeoutMs")
$report.Add("OpTimeoutSec    = $OperationTimeoutSec")
$report.Add("PowerShell      = $($PSVersionTable.PSVersion)")
$report.Add("--------------------------------------------------")

# --- WinRM session options ---
$sessionOption = New-PSSessionOption -OperationTimeout (1000 * $OperationTimeoutSec)

# --- Main ---
foreach ($comp in $Computers) {
    $prefix = "[$comp]"
    try {
        if (-not (Test-HostOnline -HostName $comp -TimeoutMs $PingTimeoutMs)) {
            $msg = "$prefix Offline (ping failed) - skipped"
            Write-Host $msg -ForegroundColor Yellow
            $report.Add($msg)
            continue
        }

        Write-Host "$prefix Creating PSSession..." -ForegroundColor Cyan
        $sess = New-PSSession -ComputerName $comp -SessionOption $sessionOption -ErrorAction Stop

        try {
            Write-Host "$prefix Sending Stop-Computer..." -ForegroundColor Cyan
            Invoke-Command -Session $sess -ScriptBlock { Stop-Computer -Force -Confirm:$false } -ErrorAction Stop
            $msg = "$prefix Shutdown command sent successfully."
            Write-Host $msg -ForegroundColor Green
            $report.Add($msg)
        }
        catch {
            $err = ($_.Exception.Message -replace "`r`n"," ").Trim()
            $msg = "$prefix ERROR during Invoke-Command: $err"
            Write-Host $msg -ForegroundColor Red
            $report.Add($msg)
        }
        finally {
            if ($sess) { try { Remove-PSSession -Session $sess -ErrorAction SilentlyContinue } catch {} }
        }
    }
    catch {
        $err = ($_.Exception.Message -replace "`r`n"," ").Trim()
        $msg = "$prefix Failed to create PSSession (WinRM/Permission/DNS?): $err"
        Write-Host $msg -ForegroundColor Magenta
        $report.Add($msg)
    }
}

$report.Add("--------------------------------------------------")
$report.Add("End: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report | Out-File -FilePath $ReportPath -Encoding UTF8

# Stop transcript and keep window open
try { Stop-Transcript | Out-Null } catch {}
Write-Host "`nReport: $ReportPath" -ForegroundColor Green
Write-Host "Transcript: $Transcript" -ForegroundColor Green
[void](Read-Host "Press Enter to exit")
