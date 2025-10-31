<#
.SYNOPSIS
  Permanently delete a file or folder after removing all protections, with an interactive progress bar.

.DESCRIPTION
  Prompts for a target path, elevates if required, removes ReadOnly/Hidden/System attributes,
  takes ownership, resets ACLs, disables inheritance, enumerates items and deletes them one-by-one
  while showing a progress bar and percentage. Includes safety checks for system-critical paths.

.NOTES
  PowerShell 5.1 / 7+. Run as Administrator.
#>

# ---------- Colored Output Helpers ----------
function Write-Info   ($m){ Write-Host "[i] $m" -ForegroundColor Cyan }
function Write-Warn   ($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-ErrorX ($m){ Write-Host "[x] $m" -ForegroundColor Red }
function Write-Ok     ($m){ Write-Host "[✓] $m" -ForegroundColor Green }
function Write-Step   ($m){ Write-Host "── $m" -ForegroundColor Magenta }

# ---------- Elevation ----------
function Ensure-Elevated {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not $isAdmin){
        Write-Warn "Administrator privileges required. Restarting with elevation..."
        if([string]::IsNullOrEmpty($PSCommandPath)){
            Write-ErrorX "Cannot auto-elevate: PSCommandPath is empty. Save and run the script file."
            exit 1
        }
        $exe  = (Get-Process -Id $PID).Path
        $args = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $psi  = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = $exe
        $psi.Arguments = $args
        $psi.Verb      = "runas"
        try   { [Diagnostics.Process]::Start($psi) | Out-Null } 
        catch { Write-ErrorX "Elevation request denied."; exit 1 }
        exit 0
    }
}

# ---------- Safety Guard ----------
function Test-DangerousPath {
    param([string]$Path)
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return $true }

    $dangerRoots = @(
        '^([A-Za-z]:\\)?$',
        '^[A-Za-z]:\\$',
        '^[A-Za-z]:\\Windows(\\.*)?$',
        '^[A-Za-z]:\\Program Files( \(x86\))?(\\.*)?$',
        '^[A-Za-z]:\\ProgramData(\\.*)?$',
        '^[A-Za-z]:\\Users\\?$',
        '^[A-Za-z]:\\Users\\[^\\]+\\AppData(\\.*)?$'
    )
    foreach($rx in $dangerRoots){ if($full -match $rx){ return $true } }

    $userProfile = [Environment]::GetFolderPath("UserProfile")
    if($full -ieq $userProfile){ return $true }
    return $false
}

# ---------- Long Path Support ----------
function Get-ExtendedPath {
    param([string]$Path)
    if($Path -like "\\?\*"){ return $Path }
    if($Path.StartsWith("\\\\")){ return "\\?\UNC\" + $Path.Substring(2) }
    return "\\?\$Path"
}

# ---------- Reset Ownership and ACLs ----------
function Reset-OwnershipAndAcl {
    param([string]$Target)
    Write-Step "Removing ReadOnly/Hidden/System attributes..."
    try { & attrib -r -h -s "$Target" /s /d 2>$null } catch {}

    Write-Step "Taking ownership and resetting ACLs..."
    try {
        & takeown /f "$Target" /r /d y                       | Out-Null
        & icacls "$Target" /grant *S-1-5-32-544:(F) /T /C    | Out-Null  # Administrators full control
        & icacls "$Target" /inheritance:d /T /C              | Out-Null
        & icacls "$Target" /reset /T /C                      | Out-Null
    } catch { Write-Warn "takeown/icacls returned errors, continuing..." }
}

# ---------- Delete With Progress ----------
function Delete-WithProgress {
    param([string]$Target)

    if((Test-Path -LiteralPath $Target) -and -not (Get-Item -LiteralPath $Target).PSIsContainer){
        $name = Split-Path -Leaf $Target
        Write-Step ("Deleting file: {0}" -f $name)
        Write-Progress -Activity "Deleting" -Status "Removing file" -PercentComplete 0 -Id 1
        try {
            Remove-Item -LiteralPath $Target -Force -ErrorAction Stop
            Write-Progress -Activity "Deleting" -Completed -Id 1
            return $true
        } catch {
            Write-Progress -Activity "Deleting" -Status "Failed" -PercentComplete 100 -Id 1
            Write-Warn ("Remove-Item failed for file: {0}" -f $_.Exception.Message)
            return $false
        }
    }

    Write-Step "Collecting items to delete (this may take a while for large trees)..."
    $items = @()
    try {
        $items = Get-ChildItem -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue |
                 Select-Object -ExpandProperty FullName
    } catch {
        Write-Warn ("Enumeration error: {0}" -f $_.Exception.Message)
    }

    # Include the target itself as the last item
    $itemsList = @()
    if($items){ $itemsList += $items }
    $itemsList += $Target

    $total = $itemsList.Count
    if($total -eq 0){
        Write-Warn "No items found under target. Attempting direct removal..."
        try { Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction Stop; return $true }
        catch { Write-Warn ("Direct removal failed: {0}" -f $_.Exception.Message); return $false }
    }

    $index = 0
    foreach($it in $itemsList){
        $index++
        $percent = [int](($index / $total) * 100)
        $short = if($it.Length -gt 60){ '...' + $it.Substring($it.Length - 57) } else { $it }
        # <<< fixed: no variable directly before ':'; using -f formatting >>>
        Write-Progress -Activity "Deleting items" -Status ("{0} of {1}: {2}" -f $index, $total, $short) -PercentComplete $percent -Id 1

        try {
            if(Test-Path -LiteralPath $it){
                Remove-Item -LiteralPath $it -Recurse -Force -ErrorAction Stop -Confirm:$false
            }
        } catch {
            try {
                if((Test-Path -LiteralPath $it) -and (Get-Item -LiteralPath $it).PSIsContainer){
                    & cmd /c "rmdir /s /q `"$it`"" 2>$null
                } else {
                    & cmd /c "del /f /q `"$it`"" 2>$null
                }
            } catch { }
        }
    }

    Write-Progress -Activity "Deleting items" -Completed -Id 1
    return -not (Test-Path -LiteralPath $Target)
}

# ---------- Fallback Bulk Delete ----------
function Fallback-BulkDelete {
    param([string]$Target)
    Write-Step "Attempting bulk fallback removal via cmd..."
    try {
        if((Test-Path -LiteralPath $Target) -and (Get-Item -LiteralPath $Target).PSIsContainer){
            & cmd /c "rmdir /s /q `"$Target`"" 2>$null
        } else {
            & cmd /c "del /f /q `"$Target`"" 2>$null
        }
        Start-Sleep -Milliseconds 300
        return -not (Test-Path -LiteralPath $Target)
    } catch {
        Write-Warn ("Fallback bulk removal exception: {0}" -f $_.Exception.Message)
        return $false
    }
}

# ---------- Main ----------
Ensure-Elevated

$rawPath = Read-Host "Enter the full path of the file or folder to permanently delete"
if([string]::IsNullOrWhiteSpace($rawPath)){ Write-ErrorX "No path specified."; exit 1 }

try { $resolved = Resolve-Path -LiteralPath $rawPath -ErrorAction Stop; $target = $resolved.ProviderPath }
catch { $target = $rawPath }

if(-not (Test-Path -LiteralPath $target)){ Write-Warn "Object not found (continuing)."; }

if(Test-DangerousPath -Path $target){
    Write-ErrorX "Critical system path detected. Aborting to prevent damage."
    exit 2
}

$ext = Get-ExtendedPath -Path $target
Write-Info ("Target: {0}"        -f $target)
Write-Info ("Extended path: {0}" -f $ext)

Reset-OwnershipAndAcl -Target $ext

$deleted = $false
try { $deleted = Delete-WithProgress -Target $ext } catch { Write-Warn ("Delete-WithProgress error: {0}" -f $_.Exception.Message) }

if(-not $deleted){ $deleted = Fallback-BulkDelete -Target $ext }

if($deleted){ Write-Ok "Done. The object was permanently deleted." }
else        { Write-ErrorX "Failed to delete the object. Close locking processes (Explorer/editors/AV) and retry." }
