# Domain Controller Admin Rights Audit (SID-based, TXT output)

$ErrorActionPreference = 'Stop'

Write-Host "Scanning administrative accounts on domain controller $env:COMPUTERNAME ..." -ForegroundColor Cyan

# Ensure folder exists
$folder = "C:\Temp"
if (!(Test-Path $folder)) {
    New-Item -ItemType Directory -Path $folder | Out-Null
}

# Output file
$outFile = "$folder\Admins_$($env:COMPUTERNAME).txt"

# Load AD module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "ActiveDirectory module is required. Aborting."
    return
}

# Domain SID
$domainSid = (Get-ADDomain).DomainSID.Value

# Privileged groups using well-known SIDs
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

    # Log group
    if (-not $seenSid.ContainsKey($group.SID.Value)) {
        $seenSid[$group.SID.Value] = $true

        $result += [PSCustomObject]@{
            Account = $group.SamAccountName
            Class   = 'group'
            Via     = 'Privileged group'
            Type    = $g.Label
        }
    }

    # Expand and log users
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
                Via     = "Member of '$($g.Label)'"
                Type    = 'Admin privilege'
            }
        }
    }
}

# Write to console
if ($result.Count -eq 0) {
    Write-Host "`nNo administrative accounts found." -ForegroundColor Red
} else {
    Write-Host "`nAccounts with admin rights:`n" -ForegroundColor Green
    $result | Format-Table Account, Class, Type, Via -AutoSize
}

# Write to TXT
"Admin Rights Report for $env:COMPUTERNAME" | Out-File $outFile -Encoding UTF8
"Generated: $(Get-Date)"                    | Out-File $outFile -Append -Encoding UTF8
"==========================================" | Out-File $outFile -Append -Encoding UTF8
""                                           | Out-File $outFile -Append -Encoding UTF8

foreach ($entry in $result) {
    "Account: $($entry.Account)"                  | Out-File $outFile -Append -Encoding UTF8
    "Class:   $($entry.Class)"                    | Out-File $outFile -Append -Encoding UTF8
    "Type:    $($entry.Type)"                     | Out-File $outFile -Append -Encoding UTF8
    "Via:     $($entry.Via)"                      | Out-File $outFile -Append -Encoding UTF8
    "------------------------------------------"  | Out-File $outFile -Append -Encoding UTF8
}

Write-Host "`nReport saved to: $outFile" -ForegroundColor Cyan
