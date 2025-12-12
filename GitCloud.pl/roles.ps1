# ==========================================
# Export installed Windows Server roles
# Output: C:\Windows\database\roles\roles.txt
# ==========================================

$OutFile = "C:\Windows\database\roles\roles.txt"
$OutDir  = Split-Path $OutFile -Parent

# Ensure directory exists
if (!(Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# Collect installed roles and features
$roles = Get-WindowsFeature | Where-Object { $_.Installed -eq $true }

# Build report
$lines = @()
$lines += "===== INSTALLED ROLES & FEATURES ====="
$lines += "Server : $env:COMPUTERNAME"
$lines += "Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "Total installed: $($roles.Count)"
$lines += ""

foreach ($r in $roles) {
    $lines += "- $($r.Name)  [$($r.DisplayName)]"
}

# Save file
$lines | Out-File -FilePath $OutFile -Encoding UTF8

Write-Host "Roles exported to $OutFile" -ForegroundColor Green
