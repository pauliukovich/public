<# 
Reset AD user password in OU=Nauczyciele,DC=sp6zabki,DC=local
List users alphabetically and set new password by selecting number.
#>

# --- Check admin rights ---
function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}
if (-not (Test-Admin)) {
    Write-Host "[ERROR] Run this script as Administrator." -ForegroundColor Red
    exit 1
}

# --- Import AD module ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "[ERROR] ActiveDirectory module not found. Install RSAT AD tools." -ForegroundColor Red
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

# --- OU target ---
$OU = "OU=Nauczyciele,DC=sp6zabki,DC=local"

# --- Get users ---
try {
    $users = Get-ADUser -SearchBase $OU -SearchScope Subtree -Filter * `
        -Properties GivenName,Surname,DisplayName,Enabled,sAMAccountName |
        Where-Object { $_.Enabled -eq $true } |
        Sort-Object @{Expression="Surname";Descending=$false},
                    @{Expression="GivenName";Descending=$false} |
        Select-Object @{n='FullName';e={
                            if ($_.GivenName -or $_.Surname) {
                                ($_.GivenName, $_.Surname) -join ' '
                            } else {
                                $_.DisplayName -ne '' ? $_.DisplayName : $_.Name
                            }
                        }},
                      sAMAccountName,DistinguishedName
} catch {
    Write-Host "[ERROR] Failed to query users: $_" -ForegroundColor Red
    exit 1
}

if (-not $users -or $users.Count -eq 0) {
    Write-Host "[INFO] No users found in OU=Nauczyciele." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== Nauczyciele (sorted A→Z) ===" -ForegroundColor Cyan
$menu = @()
$i=0
foreach ($u in $users) {
    $i++
    "{0,3}. {1}   [{2}]" -f $i, $u.FullName, $u.sAMAccountName | Write-Host
    $menu += $u
}
Write-Host "Total: $i user(s)"
Write-Host ""

function Compare-SecureStringsEqual {
    param(
        [Parameter(Mandatory)][System.Security.SecureString]$A,
        [Parameter(Mandatory)][System.Security.SecureString]$B
    )
    $ptrA = [IntPtr]::Zero
    $ptrB = [IntPtr]::Zero
    try {
        $ptrA = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($A)
        $ptrB = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($B)
        $sa = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptrA)
        $sb = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptrB)
        return [string]::Equals($sa, $sb)
    } finally {
        if ($ptrA -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptrA) }
        if ($ptrB -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptrB) }
    }
}

while ($true) {
    $sel = Read-Host "Select user number (1-$i) or Enter to quit"
    if ([string]::IsNullOrWhiteSpace($sel)) { break }
    if (-not [int]::TryParse($sel, [ref]([int]$null))) {
        Write-Host "[WARN] Enter a valid number." -ForegroundColor Yellow
        continue
    }
    $n = [int]$sel
    if ($n -lt 1 -or $n -gt $i) {
        Write-Host "[WARN] Number out of range." -ForegroundColor Yellow
        continue
    }

    $target = $menu[$n-1]
    Write-Host ("Selected: {0} [{1}]" -f $target.FullName, $target.sAMAccountName) -ForegroundColor Cyan

    $p1 = Read-Host "Enter NEW password" -AsSecureString
    $p2 = Read-Host "Confirm NEW password" -AsSecureString
    if (-not (Compare-SecureStringsEqual -A $p1 -B $p2)) {
        Write-Host "[ERROR] Passwords do not match." -ForegroundColor Red
        continue
    }

    try {
        Set-ADAccountPassword -Identity $target.sAMAccountName -Reset -NewPassword $p1 -ErrorAction Stop
        Set-ADUser -Identity $target.sAMAccountName -ChangePasswordAtLogon $true -ErrorAction SilentlyContinue
        Unlock-ADAccount -Identity $target.sAMAccountName -ErrorAction SilentlyContinue | Out-Null
        Write-Host "[OK] Password changed successfully for $($target.sAMAccountName)" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

Write-Host "Done."
