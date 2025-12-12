<# 
AD OU Navigator + User Password Reset
- Navigate OUs (root -> child -> subchild ...).
- List users in the currently selected OU (OneLevel only).
- Pick a user by number and reset password with confirmation.
Requirements: RSAT ActiveDirectory module. Run as Administrator (domain admin or delegated).
#>

[CmdletBinding()]
param(
    # Optional: pre-set starting DN. If empty, defaults to domain root.
    [string]$StartDN = ""
)

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

# Ensure AD module
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "[ERROR] ActiveDirectory module not found. Install RSAT AD tools." -ForegroundColor Red
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

# --- Utils ---
function Get-ParentDN {
    param([Parameter(Mandatory)][string]$DN)
    if (-not $DN.Contains(',')) { return $null }
    return $DN.Substring($DN.IndexOf(',') + 1)
}

function Get-ChildOUs {
    param(
        [Parameter(Mandatory)][string]$BaseDN
    )
    try {
        # OneLevel OUs only
        return Get-ADOrganizationalUnit -SearchBase $BaseDN -SearchScope OneLevel -LDAPFilter '(objectClass=organizationalUnit)' `
               -Properties name,distinguishedName |
               Sort-Object Name
    } catch {
        Write-Host "[ERROR] Failed to enumerate child OUs: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Get-UsersInOU {
    param(
        [Parameter(Mandatory)][string]$BaseDN,
        [switch]$IncludeDisabled
    )
    try {
        $users = Get-ADUser -SearchBase $BaseDN -SearchScope OneLevel -Filter * `
            -Properties GivenName,Surname,DisplayName,Enabled,sAMAccountName |
            Where-Object { $IncludeDisabled.IsPresent -or $_.Enabled -eq $true } |
            Select-Object @{n='FullName';e={
                                if ($_.GivenName -or $_.Surname) { ($_.GivenName, $_.Surname) -join ' ' }
                                elseif ($_.DisplayName) { $_.DisplayName }
                                else { $_.Name }
                            }},
                          Surname,GivenName,sAMAccountName,DistinguishedName,Enabled |
            Sort-Object @{Expression='Surname';Descending=$false},
                        @{Expression='GivenName';Descending=$false},
                        @{Expression='FullName';Descending=$false}
        return $users
    } catch {
        Write-Host "[ERROR] Failed to query users: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

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

# --- Determine start DN ---
if ([string]::IsNullOrWhiteSpace($StartDN)) {
    try {
        $domain = Get-ADDomain
        $StartDN = $domain.DistinguishedName
    } catch {
        Write-Host "[ERROR] Cannot resolve domain DN automatically. Provide -StartDN." -ForegroundColor Red
        exit 1
    }
}

# Validate starting container (domain DN or OU DN)
try {
    # Try OU first; if fails, try domain (partition)
    $null = Get-ADOrganizationalUnit -Identity $StartDN -ErrorAction Stop
} catch {
    try {
        $null = Get-ADDomain | Out-Null  # just to ensure AD is reachable
        # If StartDN equals domain DN, it's fine (we'll enumerate one level OUs under it)
    } catch {
        Write-Host "[ERROR] StartDN is invalid and domain is not reachable." -ForegroundColor Red
        exit 1
    }
}

# Navigation stack
$stack = New-Object System.Collections.Stack
$currentDN = $StartDN

Write-Host ""
Write-Host "=== AD OU Navigator ===" -ForegroundColor Cyan
Write-Host "Start DN: $currentDN"
Write-Host ""

:NavLoop while ($true) {
    Write-Host ("Current: {0}" -f $currentDN) -ForegroundColor Cyan

    # List child OUs
    $children = Get-ChildOUs -BaseDN $currentDN
    $i = 0
    if ($children.Count -gt 0) {
        Write-Host ""
        Write-Host "Child OUs:" -ForegroundColor Gray
        foreach ($ou in $children) { $i++; "{0,3}. {1}" -f $i, $ou.Name | Write-Host }
    } else {
        Write-Host "[INFO] No child OUs here." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Actions:" -ForegroundColor Gray
    Write-Host "  U  - List users in this OU (OneLevel)"
    if ($children.Count -gt 0) { Write-Host "  #  - Enter child OU by number (1..$i)" }
    if ($stack.Count -gt 0)     { Write-Host "  P  - Go to parent OU" }
    Write-Host "  G  - Go to a specific DN (manual input)"
    Write-Host "  Q  - Quit"
    Write-Host ""

    $choice = Read-Host "Select action"
    if ([string]::IsNullOrWhiteSpace($choice)) { continue }

    switch -Regex ($choice.Trim()) {
        '^[Qq]$' { break NavLoop }

        '^[Pp]$' {
            if ($stack.Count -gt 0) {
                $currentDN = $stack.Pop()
            } else {
                Write-Host "[WARN] Already at the top." -ForegroundColor Yellow
            }
            continue
        }

        '^[Gg]$' {
            $dn = Read-Host "Enter DN (e.g. OU=Uczniowie,DC=example,DC=local)"
            if ([string]::IsNullOrWhiteSpace($dn)) { continue }
            try {
                # Validate OU DN; if not an OU, allow switching if it equals domain DN
                $null = Get-ADOrganizationalUnit -Identity $dn -ErrorAction Stop
                $stack.Push($currentDN) | Out-Null
                $currentDN = $dn
            } catch {
                # Allow jumping to domain root DN
                $domainDN = (Get-ADDomain).DistinguishedName
                if ($dn -eq $domainDN) {
                    $stack.Push($currentDN) | Out-Null
                    $currentDN = $dn
                } else {
                    Write-Host "[ERROR] Invalid DN: $dn" -ForegroundColor Red
                }
            }
            continue
        }

        '^[Uu]$' {
            $includeDisabled = $false
            $ans = Read-Host "Include disabled accounts? (Y/N) [default: N]"
            if ($ans -and $ans.Trim().ToUpper() -eq 'Y') { $includeDisabled = $true }

            $users = Get-UsersInOU -BaseDN $currentDN -IncludeDisabled:$includeDisabled
            if (-not $users -or $users.Count -eq 0) {
                Write-Host "[INFO] No users in this OU (OneLevel)." -ForegroundColor Yellow
                continue
            }

            Write-Host ""
            Write-Host "=== Users (sorted A→Z by Surname, GivenName) ===" -ForegroundColor Cyan
            $menu = @()
            $k=0
            foreach ($u in $users) {
                $k++
                $flag = $u.Enabled ? "" : " (disabled)"
                "{0,4}. {1}  [{2}]{3}" -f $k, $u.FullName, $u.sAMAccountName, $flag | Write-Host
                $menu += $u
            }
            Write-Host "Total: $k user(s)"
            Write-Host ""

            while ($true) {
                $sel = Read-Host "Pick user number to reset password (1-$k), or Enter to go back"
                if ([string]::IsNullOrWhiteSpace($sel)) { break }
                if (-not [int]::TryParse($sel, [ref]([int]$null))) {
                    Write-Host "[WARN] Enter a valid number." -ForegroundColor Yellow
                    continue
                }
                $n = [int]$sel
                if ($n -lt 1 -or $n -gt $k) {
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

                $chg = Read-Host "Force 'Change password at next logon'? (Y/N) [default: Y]"
                if ([string]::IsNullOrWhiteSpace($chg)) { $chg = 'Y' }
                $unlock = Read-Host "Unlock account if locked? (Y/N) [default: Y]"
                if ([string]::IsNullOrWhiteSpace($unlock)) { $unlock = 'Y' }

                try {
                    Set-ADAccountPassword -Identity $target.sAMAccountName -Reset -NewPassword $p1 -ErrorAction Stop
                    if ($chg.ToUpper() -eq 'Y') {
                        Set-ADUser -Identity $target.sAMAccountName -ChangePasswordAtLogon $true -ErrorAction Stop
                    }
                    if ($unlock.ToUpper() -eq 'Y') {
                        Unlock-ADAccount -Identity $target.sAMAccountName -ErrorAction SilentlyContinue | Out-Null
                    }
                    Write-Host "[OK] Password reset successfully." -ForegroundColor Green
                } catch {
                    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
                }

                Write-Host ""
            }
            continue
        }

        '^\d+$' {
            if ($children.Count -eq 0) {
                Write-Host "[WARN] No child OUs to enter." -ForegroundColor Yellow
                continue
            }
            $num = [int]$choice
            if ($num -lt 1 -or $num -gt $children.Count) {
                Write-Host "[WARN] Number out of range." -ForegroundColor Yellow
                continue
            }
            $stack.Push($currentDN) | Out-Null
            $currentDN = $children[$num-1].DistinguishedName
            continue
        }

        default {
            Write-Host "[WARN] Unknown option." -ForegroundColor Yellow
            continue
        }
    }
}

Write-Host ""
Write-Host "Bye."
