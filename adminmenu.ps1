<# 
    Admin Utility Menu (PS5) — cleaned & ordered
    - Solid color wallpaper only (no file picker). Numbers strictly 1-2-3-4-5.
    - Power menu choices mapped 1-2-3-4-5 correctly.
    - Personalization submenu: 1..5, 0 returns to main menu.
    - Console colors: Green=OK, Red=Error, Yellow=Advice.
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

function Restart-Explorer {
    try {
        Stop-Process -Name explorer -Force -ErrorAction Stop
        Start-Process explorer.exe
        Start-Sleep -Milliseconds 400
        Say-Ok "Explorer restarted."
    } catch {
        Say-Adv "Sign out and sign back in if changes are not visible."
    }
}

# Solid-color wallpaper applier
function Set-SolidColorWallpaper([int]$R,[int]$G,[int]$B){
    try{
        Add-Type -AssemblyName System.Drawing
        $bmp = New-Object System.Drawing.Bitmap 1,1
        $c   = [System.Drawing.Color]::FromArgb($R,$G,$B)
        $bmp.SetPixel(0,0,$c)
        $path = Join-Path $env:TEMP "solid_wallpaper.bmp"
        $bmp.Save($path,[System.Drawing.Imaging.ImageFormat]::Bmp)
        $bmp.Dispose()

        # Set wallpaper in registry
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name Wallpaper -Value $path -Force
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "0" -Force   # Center (1x1 => solid fill)
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name TileWallpaper   -Value "0" -Force

        # Broadcast change (SPI_SETDESKWALLPAPER)
        $sig = @"
using System;
using System.Runtime.InteropServices;
public class SPI {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
        Add-Type $sig -ErrorAction SilentlyContinue | Out-Null
        [void][SPI]::SystemParametersInfo(20,0,$path, 1+2)  # UPDATEINIFILE|SENDCHANGE

        Restart-Explorer
        Say-Ok "Solid color wallpaper applied."
    } catch {
        Say-Err "Failed to set solid wallpaper: $($_.Exception.Message)"
    }
}

# ---------------------------
# Base actions 1-3
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

# ---------------------------
# New actions 4-8
# ---------------------------
function Action-EnableRDP {
    try{
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -PropertyType DWord -Value 1 -Force | Out-Null
        if (Get-Command Enable-NetFirewallRule -ErrorAction SilentlyContinue) {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
        } else {
            netsh advfirewall firewall set rule group="remote desktop" new enable=Yes | Out-Null
        }
        Say-Ok "RDP enabled (NLA on, firewall opened)."
    } catch {
        Say-Err "Failed to enable RDP: $($_.Exception.Message)"
    }
}

function Action-EnableWinRM {
    try{
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        Set-Service -Name WinRM -StartupType Automatic
        Start-Service -Name WinRM
        Say-Ok "WinRM enabled and set to Automatic."
    } catch {
        Say-Err "Failed to enable WinRM: $($_.Exception.Message)"
    }
}

function Action-EnableAutomaticUpdates {
    try{
        $base = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        New-Item -Path $base -Force | Out-Null
        New-ItemProperty -Path $base -Name "NoAutoUpdate" -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $base -Name "AUOptions"     -PropertyType DWord -Value 4 -Force | Out-Null  # Auto download & schedule
        New-ItemProperty -Path $base -Name "ScheduledInstallDay"  -PropertyType DWord -Value 0 -Force | Out-Null # Every day
        New-ItemProperty -Path $base -Name "ScheduledInstallTime" -PropertyType DWord -Value 3 -Force | Out-Null # 03:00
        sc.exe config wuauserv start= demand | Out-Null
        net start wuauserv | Out-Null
        Say-Ok "Automatic Updates configured (daily 03:00)."
        Say-Adv "Settings may show 'managed by your organization' — expected."
    } catch {
        Say-Err "Failed to configure Automatic Updates: $($_.Exception.Message)"
    }
}

function Action-ConfigurePowerTimeouts {
    # Clean sequential menus with proper mapping
    Write-Host "DISPLAY OFF (AC/DC). Choose:" -ForegroundColor Yellow
    Write-Host "  1) Never"
    Write-Host "  2) 5 minutes"
    Write-Host "  3) 10 minutes"
    Write-Host "  4) 15 minutes"
    Write-Host "  5) 30 minutes"
    $d = Read-Host "Select 1-5"
    switch ($d) {
        '1' { $display = 0 }
        '2' { $display = 5 }
        '3' { $display = 10 }
        '4' { $display = 15 }
        '5' { $display = 30 }
        default { Say-Err "Invalid choice."; return }
    }

    Write-Host "SLEEP (AC/DC). Choose:" -ForegroundColor Yellow
    Write-Host "  1) Never"
    Write-Host "  2) 15 minutes"
    Write-Host "  3) 30 minutes"
    Write-Host "  4) 60 minutes"
    Write-Host "  5) 120 minutes"
    $s = Read-Host "Select 1-5"
    switch ($s) {
        '1' { $sleep = 0 }
        '2' { $sleep = 15 }
        '3' { $sleep = 30 }
        '4' { $sleep = 60 }
        '5' { $sleep = 120 }
        default { Say-Err "Invalid choice."; return }
    }

    try{
        powercfg -change -monitor-timeout-ac $display | Out-Null
        powercfg -change -monitor-timeout-dc $display | Out-Null
        powercfg -change -standby-timeout-ac $sleep | Out-Null
        powercfg -change -standby-timeout-dc $sleep | Out-Null
        Say-Ok "Display off: $display min; Sleep: $sleep min (AC & DC)."
    } catch {
        Say-Err "Failed to set power timeouts: $($_.Exception.Message)"
    }
}

function Action-Personalization {
    while ($true) {
        Clear-Host
        Write-Host "=== PERSONALIZATION ===" -ForegroundColor Yellow
        Write-Host "1) Desktop background: SOLID COLOR"
        Write-Host "2) Theme: Dark or Light"
        Write-Host "3) Hide Widgets button (Win11)"
        Write-Host "4) Hide Task View button"
        Write-Host "5) Taskbar alignment (Left/Center)"
        Write-Host "0) Back"
        $choice = Read-Host "Choose 0-5"

        switch ($choice) {
            '1' {
                # Strictly solid colors, sequential 1..14
                Write-Host "Choose color:" -ForegroundColor Yellow
                Write-Host "  1) Windows Blue"
                Write-Host "  2) Dark Blue"
                Write-Host "  3) Teal"
                Write-Host "  4) Green"
                Write-Host "  5) Purple"
                Write-Host "  6) Magenta"
                Write-Host "  7) Crimson"
                Write-Host "  8) Orange"
                Write-Host "  9) Gold"
                Write-Host " 10) Yellow"
                Write-Host " 11) Gray"
                Write-Host " 12) Dark Gray"
                Write-Host " 13) Black"
                Write-Host " 14) White"
                $c = Read-Host "Select 1-14"
                switch ($c) {
                    '1'  { $rgb=0,120,215 }
                    '2'  { $rgb=0,99,177 }
                    '3'  { $rgb=0,153,188 }
                    '4'  { $rgb=16,124,16 }
                    '5'  { $rgb=124,0,124 }
                    '6'  { $rgb=195,0,82 }
                    '7'  { $rgb=229,20,0 }
                    '8'  { $rgb=240,150,9 }
                    '9'  { $rgb=255,185,0 }
                    '10' { $rgb=255,241,0 }
                    '11' { $rgb=118,118,118 }
                    '12' { $rgb=51,51,51 }
                    '13' { $rgb=0,0,0 }
                    '14' { $rgb=255,255,255 }
                    default { Say-Err "Invalid choice."; continue }
                }
                Set-SolidColorWallpaper -R $rgb[0] -G $rgb[1] -B $rgb[2]
                Pause
            }
            '2' {
                Write-Host "Theme: 1) Dark  2) Light" -ForegroundColor Yellow
                $t = Read-Host "Select 1-2"
                try{
                    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
                    New-Item -Path $key -Force | Out-Null
                    switch ($t) {
                        '1' { Set-ItemProperty $key -Name AppsUseLightTheme -Type DWord -Value 0 -Force; Set-ItemProperty $key -Name SystemUsesLightTheme -Type DWord -Value 0 -Force; Say-Ok "Dark theme applied." }
                        '2' { Set-ItemProperty $key -Name AppsUseLightTheme -Type DWord -Value 1 -Force; Set-ItemProperty $key -Name SystemUsesLightTheme -Type DWord -Value 1 -Force; Say-Ok "Light theme applied." }
                        default { Say-Err "Invalid choice."; continue }
                    }
                } catch { Say-Err "Failed to set theme: $($_.Exception.Message)" }
                Restart-Explorer
                Pause
            }
            '3' {
                try{
                    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Type DWord -Value 0 -Force
                    Say-Ok "Widgets button hidden."
                } catch { Say-Err "Failed: $($_.Exception.Message)" }
                Restart-Explorer
                Pause
            }
            '4' {
                try{
                    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 0 -Force
                    Say-Ok "Task View button hidden."
                } catch { Say-Err "Failed: $($_.Exception.Message)" }
                Restart-Explorer
                Pause
            }
            '5' {
                Write-Host "Taskbar alignment: 1) Left  2) Center" -ForegroundColor Yellow
                $a = Read-Host "Select 1-2"
                $val = switch ($a) { '1' {0} '2' {1} default {-1} }
                if($val -eq -1){ Say-Err "Invalid choice."; continue }
                try{
                    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Type DWord -Value $val -Force
                    Say-Ok "Taskbar alignment applied."
                } catch { Say-Err "Failed: $($_.Exception.Message)" }
                Restart-Explorer
                Pause
            }
            '0' { return }   # <-- immediately return to main menu
            default { Say-Err "Unknown option."; Start-Sleep 1 }
        }
    }
}

# ---------------------------
# Main Menu
# ---------------------------
function Show-Menu{
    Clear-Host
    Write-Host "=============================" -ForegroundColor Yellow
    Write-Host "   ADMIN UTILITY MENU (PS5)  " -ForegroundColor Yellow
    Write-Host "=============================" -ForegroundColor Yellow
    Write-Host "1) Rename computer"
    Write-Host "2) Enable Administrator & set password"
    Write-Host "3) Create new user (custom name, password never expires)"
    Write-Host "4) Enable RDP"
    Write-Host "5) Enable WinRM"
    Write-Host "6) Enable Automatic Updates"
    Write-Host "7) Power: set Sleep & Display-Off timers"
    Write-Host "8) Personalization"
    Write-Host "0) Exit"
}

do{
    Show-Menu
    $c=Read-Host "Choose option (0-8)"
    switch($c){
        '1'{Action-RenameComputer;Pause}
        '2'{Action-EnableAdministratorAndSetPassword;Pause}
        '3'{Action-CreateCustomUser;Pause}
        '4'{Action-EnableRDP;Pause}
        '5'{Action-EnableWinRM;Pause}
        '6'{Action-EnableAutomaticUpdates;Pause}
        '7'{Action-ConfigurePowerTimeouts;Pause}
        '8'{Action-Personalization}
        '0'{break}
        default{Say-Err "Invalid choice.";Start-Sleep 1}
    }
}while($true)

Say-Adv "Tip: if you renamed the computer or changed UI settings, a reboot or Explorer restart may be needed."
