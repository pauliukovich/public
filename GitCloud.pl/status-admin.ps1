# Domain Controller Admin Rights Audit (SID-based, language-independent)
# Saves results to: C:\Windows\database\statusadmin\serwer-admin.txt

$ErrorActionPreference = 'Stop'

Write-Host "Scanning administrative accounts on domain controller $env:COMPUTERNAME ..." -ForegroundColor Cyan

# Create target folder if missing
$folder = "C:\Windows\database\statusadmin"
if (!(Test-Path $folder)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}

# Output file
$outFile = "$folder\serwer-admin.txt"

# Load AD module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "ActiveDirectory module is required. Aborting."
    return
}

# Domain SID
$domainSid = (Get-ADDomain).DomainSID.Value

# Privileged groups SIDs
$groupSids = @(
    @{ Label = 'Builtin Administrators'; Sid = 'S-1-5-32-544' }
    @{ Label = 'Server Operators';       Sid = 'S-1-5-32-549' }
    @{ Label = 'Account Operators';      Sid = 'S-1-5-32-548' }
    @{ Label = 'Backup Operators';       Sid = 'S-1-5-32-551' }
    @{ Label = 'Print Operators';        Sid = 'S-1-5-32-550' }
    @{ Label = 'Domain Admins';          Sid = "$domainSid-512" }
    @{ Label = 'Enterprise Admins';      Sid = "$domainSid-519" }
)

$result  = @()
$seenSid = @{}

foreach ($g in $groupSids) {

    Write-Host "`nProcessing group: $($g.Label) [$($g.Sid)] ..." -ForegroundColor Yellow

    try {
        $group = Get-ADGroup -Identity $g.Sid -ErrorAction Stop
    } catch {
        Write-Warning "Group '$($g.Label)' not found. Skipping."
        continue
    }

    # Add the group itself
    if (-not $seenSid.ContainsKey($group.SID.Value)) {
        $seenSid[$group.SID.Value] = $true

        $result += [PSCustomObject]@{
            Account = $group.SamAccountName
            Class   = 'group'
            Source  = 'AD'
            Via     = 'Privileged group'
            Type    = $g.Label
        }
    }

    # Expand members
    try {
        $members = Get-ADGroupMember -Identity $group -Recursive
    } catch {
        Write-Warning "Cannot expand members of '$($g.Label)': $_"
        continue
    }

    foreach ($m in $members) {
        if ($m.ObjectClass -ne 'user') { continue }

        if (-not $seenSid.ContainsKey($m.SID.Value)) {
            $seenSid[$m.SID.Value] = $true

            $result += [PSCustomObject]@{
                Account = $m.SamAccountName
                Class   = 'user'
                Source  = 'AD'
                Via     = "Member of '$($g.Label)'"
                Type    = 'User with admin rights'
            }
        }
    }
}

# Write readable text report
$lines = @()

$lines += "DOMAIN CONTROLLER ADMIN RIGHTS REPORT"
$lines += "Server: $env:COMPUTERNAME"
$lines += "Date: $(Get-Date)"
$lines += "====================================="
$lines += ""

if ($result.Count -eq 0) {
    $lines += "No administrative accounts found."
} else {
    $lines += "Accounts with administrative rights:"
    $lines += "-------------------------------------"
    foreach ($r in $result) {
        $lines += "Account: $($r.Account)"
        $lines += "Class:   $($r.Class)"
        $lines += "Type:    $($r.Type)"
        $lines += "Via:     $($r.Via)"
        $lines += ""
    }
}

# Save text report
$lines | Out-File -FilePath $outFile -Encoding UTF8 -Force

Write-Host "`nReport saved to: $outFile" -ForegroundColor Cyan
