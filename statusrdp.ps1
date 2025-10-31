<# =====================================================================
 RDP AUDIT (Active Directory) – PowerShell 5.1
 - Enumerates all enabled computers from AD
 - For each host:
     1) Ping check
     2) TCP 3389 port check
     3) Registry value HKLM:\System\CurrentControlSet\Control\Terminal Server\fDenyTSConnections
 - Classification:
     ENABLED   = Port 3389 open OR registry says RDP enabled
     DISABLED  = Registry says RDP disabled AND port closed
     BLOCKED   = Registry says enabled but port closed (likely firewall/ACL)
     UNKNOWN   = Online but registry query failed
     OFFLINE   = Ping failed
 - Output: TXT report in %TEMP%\RDP_Audit_yyyyMMdd_HHmm.txt
 ====================================================================== #>

[CmdletBinding()]
param(
    [string]$OU,                           # e.g. "OU=PCs,OU=School,DC=domain,DC=local"
    [int]$PingTimeoutMs = 400,
    [int]$TcpTimeoutMs  = 600
)

# --- Prerequisite check ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "ActiveDirectory module not found. Please install RSAT-AD-PowerShell."
    return
}

# --- Helper function: Test TCP port ---
function Test-TcpPort {
    param([string]$Host,[int]$Port,[int]$TimeoutMs)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($Host,$Port,$null,$null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs,$false)
        if ($ok -and $client.Connected) {
            $client.EndConnect($iar) | Out-Null
            $client.Close()
            return $true
        }
        $client.Close()
        return $false
    } catch { return $false }
}

# --- Helper function: Registry check for RDP ---
function Get-RdpRegistryStatus {
    param([string]$ComputerName)
    try {
        $reg = Get-CimInstance -ClassName StdRegProv -Namespace root\cimv2 -ComputerName $ComputerName -ErrorAction Stop
        $HKLM = 2147483650
        $path = 'System\CurrentControlSet\Control\Terminal Server'
        $val  = 'fDenyTSConnections'
        $out  = Invoke-CimMethod -InputObject $reg -MethodName GetDWORDValue -Arguments @{ hDefKey=$HKLM; sSubKeyName=$path; sValueName=$val } -ErrorAction Stop
        if ($out.ReturnValue -eq 0 -and $null -ne $out.uValue) {
            return @{ Ok=$true; Deny=$out.uValue }
        } else {
            return @{ Ok=$false; Error="Return=$($out.ReturnValue)" }
        }
    } catch {
        return @{ Ok=$false; Error=$_.Exception.Message }
    }
}

# --- Collect computer list from AD ---
$computers = if ($OU) {
    Get-ADComputer -SearchBase $OU -Filter 'Enabled -eq $true' -Properties DNSHostName
} else {
    Get-ADComputer -Filter 'Enabled -eq $true' -Properties DNSHostName
}

$targets = $computers |
    Sort-Object Name |
    ForEach-Object { if ($_.DNSHostName) { $_.DNSHostName } else { $_.Name } } |
    Where-Object { $_ } |
    Select-Object -Unique

if (-not $targets) {
    Write-Error "No enabled computers found in AD."
    return
}

# --- Process each host ---
$results = foreach ($name in $targets) {
    $res = [ordered]@{
        Name     = $name
        Online   = $false
        Port3389 = $false
        RegOk    = $false
        Deny     = $null
        Error    = $null
        Status   = $null
    }

    # Step 1: Ping
    $res.Online = Test-Connection -ComputerName $name -Count 1 -Quiet -TimeoutMilliseconds $PingTimeoutMs
    if (-not $res.Online) {
        $res.Status = "OFFLINE"
        $res
        continue
    }

    # Step 2: TCP 3389
    $res.Port3389 = Test-TcpPort -Host $name -Port 3389 -TimeoutMs $TcpTimeoutMs

    # Step 3: Registry
    $rdp = Get-RdpRegistryStatus -ComputerName $name
    if ($rdp.Ok) {
        $res.RegOk = $true
        $res.Deny  = $rdp.Deny
    } else {
        $res.Error = $rdp.Error
    }

    # Classification
    if ($res.Port3389 -or ($res.RegOk -and $res.Deny -eq 0)) {
        if (-not $res.Port3389 -and $res.RegOk -and $res.Deny -eq 0) {
            $res.Status = "BLOCKED"
        } else {
            $res.Status = "ENABLED"
        }
    } elseif ($res.RegOk -and $res.Deny -eq 1 -and -not $res.Port3389) {
        $res.Status = "DISABLED"
    } elseif ($res.RegOk -eq $false) {
        $res.Status = "UNKNOWN"
    } else {
        $res.Status = "UNKNOWN"
    }

    $res
}

# --- Save report ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$outFile   = Join-Path $env:TEMP "RDP_Audit_$timestamp.txt"

$results |
    Sort-Object Status,Name |
    Format-Table -AutoSize |
    Out-String |
    Set-Content -Path $outFile -Encoding UTF8

Write-Host "RDP audit complete. Report saved to: $outFile"
