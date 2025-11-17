# Find AD user location (OU path) by login (sAMAccountName)

$ErrorActionPreference = 'Stop'

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "ActiveDirectory module is required. Run this on a domain-joined machine with RSAT/AD tools."
    return
}

# Ask for login
$login = Read-Host "Enter AD username (sAMAccountName)"

if ([string]::IsNullOrWhiteSpace($login)) {
    Write-Warning "Username is empty. Aborting."
    return
}

try {
    # Exact match by sAMAccountName
    $user = Get-ADUser -Filter "SamAccountName -eq '$login'" -Properties CanonicalName, DistinguishedName
} catch {
    Write-Error "Error while searching for user: $_"
    return
}

if (-not $user) {
    Write-Warning "User with sAMAccountName '$login' not found."
    return
}

# DistinguishedName: CN=User,OU=...,DC=...
$dn = $user.DistinguishedName

# OU DN: cut off the leading CN=...,
$ouDn = $dn
if ($dn -like 'CN=*') {
    $firstComma = $dn.IndexOf(',')
    if ($firstComma -gt 0) {
        $ouDn = $dn.Substring($firstComma + 1)
    }
}

# CanonicalName: domain.local/OU1/OU2/User Name
$canonical = $user.CanonicalName
$ouCanonical = $canonical
$parts = $canonical -split '/'
if ($parts.Count -gt 1) {
    # everything except last element (user name)
    $ouCanonical = ($parts[0..($parts.Count - 2)] -join '/')
}

Write-Host ""
Write-Host "User found:" -ForegroundColor Green
Write-Host "  Name:      $($user.Name)"
Write-Host "  Login:     $($user.SamAccountName)"
Write-Host ""
Write-Host "Location in Active Directory:" -ForegroundColor Cyan
Write-Host "  OU DN:     $ouDn"
Write-Host "  Canonical: $ouCanonical"
Write-Host ""
Write-Host "Full DistinguishedName:" -ForegroundColor Yellow
Write-Host "  $dn"
