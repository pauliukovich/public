<#
    Admin Utility Menu (PS5) — core + reboot
    - Базовые функции: 1) Rename, 2) Enable Admin+Pass, 3) Create User, 4) Reboot.
    - Без RDP/WinRM/Updates/Power/Personalization.
    - Цвета консоли: Green=OK, Red=Error, Yellow=Advice.
#>

# ---------------------------
# Elevation check
# ---------------------------
function Test-IsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}
if (-not (Test-IsElevated)) { Write-Host "[ERROR] Run as Administrator." -ForegroundColor Red; exit 1 }

# ---------------------------
# Helpers
# ---------------------------
function Say-Ok ($m){Write-Host $m -ForegroundColor Green}
function Say-Err($m){Write-Host $m -ForegroundColor Red}
function Say-Adv($m){Write-Host $m -ForegroundColor Yellow}

function Test-LocalAccountsModule { [bool](Get-Command Get-LocalUser -ErrorAction SilentlyContinue) }

function Read-ConfirmedPassword([string]$prompt="Enter password"){
    while($true){
        $p1 = Read-Host "$prompt" -AsSecureString
        $p2 = Read-Host "Confirm password" -AsSecureString
        $s1=[Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
        $s2=[Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
        if($s1 -ceq $s2){
            return (ConvertTo-SecureString -AsPlainText $s1 -Force)
        } else { Say-Err "Passwords do not match. Try again." }
    }
}

function Get-BuiltinAdministratorName {
    try { (Get-WmiObject Win32_UserAccount -Filter "LocalAccount=True AND SID LIKE '%-500'").Name } catch { "Administrator" }
}

function Set-PasswordNeverExpires($UserName){
    try{
        if(Test-LocalAccountsModule){
            Set-LocalUser -Name $UserName -PasswordNeverExpires $true -ErrorAction Stop
        } else {
            wmic UserAccount where "Name='$UserName' AND LocalAccount='True'" set PasswordExpires=False | Out-Null
        }
        return $true
    }catch{return $false}
}

# ---------------------------
# Actions 1-4
# ---------------------------
function Action-RenameComputer{
    try{
        $n=Read-Host "Enter new computer name"
        if(-not $n){Say-Err "Empty name.";return}
        Rename-Computer -NewName $n -Force -ErrorAction Stop
        Say-Ok "Computer name set to '$n'."
        Say-Adv "Restart required to apply."
    }catch{Say-Err "Rename failed: $($_.Exception.Message)"}
}

function Action-EnableAdministratorAndSetPassword{
    $a=Get-BuiltinAdministratorName
    Say-Adv "Built-in admin detected: '$a'"
    $p=Read-ConfirmedPassword "Set password for $a"
    try{
        if(Test-LocalAccountsModule){
            Enable-LocalUser -Name $a
            Set-LocalUser -Name $a -Password $p
        } else {
            $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))
            cmd /c "net user `"$a`" `"$plain`" /active:yes" | Out-Null
        }
        if(Set-PasswordNeverExpires $a){Say-Ok "Enabled '$a' (password never expires)."}
    }catch{Say-Err "Error: $($_.Exception.Message)"}
}

function Action-CreateCustomUser{
    $u=Read-Host "Enter username for new local account"
    if(-not $u){Say-Err "Username cannot be empty.";return}
    $p=Read-ConfirmedPassword "Set password for $u"
    try{
        if(Test-LocalAccountsModule){
            if(Get-LocalUser -Name $u -ErrorAction SilentlyContinue){
                Set-LocalUser -Name $u -Password $p
            } else {
                New-LocalUser -Name $u -Password $p -FullName $u -ErrorAction Stop | Out-Null
            }
            Add-LocalGroupMember -Group "Users" -Member $u -ErrorAction SilentlyContinue
        } else {
            $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))
            cmd /c "net user `"$u`" `"$plain`" /add" | Out-Null
            cmd /c "net localgroup Users `"$u`" /add" | Out-Null
        }
        if(Set-PasswordNeverExpires $u){Say-Ok "User '$u' created (password never expires)."}
        Say-Ok "[CONFIRMATION] Password for '$u' set successfully."
    }catch{Say-Err "Failed to create user '$u': $($_.Exception.Message)"}
}

function Action-Reboot{
    $confirm = Read-Host "Reboot now? (Y/N)"
    if ($confirm -match '^[Yy]$') {
        Say-Adv "Restarting computer..."
        try {
            Restart-Computer -Force
        } catch {
            Say-Err "Failed to restart: $($_.Exception.Message)"
        }
    } else {
        Say-Adv "Reboot cancelled."
    }
}

# ---------------------------
# Menu
# ---------------------------
function Show-Menu{
    Clear-Host
    Write-Host "=============================" -ForegroundColor Yellow
    Write-Host "   ADMIN UTILITY MENU (PS5)  " -ForegroundColor Yellow
    Write-Host "=============================" -ForegroundColor Yellow
    Write-Host "1) Rename computer"
    Write-Host "2) Enable Administrator & set password"
    Write-Host "3) Create new user (custom name, password never expires)"
    Write-Host "4) Reboot computer"
    Write-Host "0) Exit"
}

do{
    Show-Menu
    $c=Read-Host "Choose option (0-4)"
    switch($c){
        '1'{Action-RenameComputer;Pause}
        '2'{Action-EnableAdministratorAndSetPassword;Pause}
        '3'{Action-CreateCustomUser;Pause}
        '4'{Action-Reboot;Pause}
        '0'{break}
        default{Say-Err "Invalid choice.";Start-Sleep 1}
    }
}while($true)

Say-Adv "Tip: After renaming the computer, reboot to apply."
