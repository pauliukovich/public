<#
.SYNOPSIS
  Permanently delete a file or folder after removing protections, with an interactive progress bar.

.DESCRIPTION
  Prompts for a target path, elevates if required, removes ReadOnly/Hidden/System attributes,
  takes ownership, resets ACLs, disables inheritance, enumerates items and deletes them one-by-one
  while showing a progress bar and percentage. Includes safety checks for system-critical paths.

.NOTES
  Compatible with PowerShell 5.1 and PowerShell 7+.
  Run with Administrator privileges for full effect.
#>

# ---------- Colored Output Helpers ----------
function Write-Info   ($m){ Write-Host "[i] $m" -ForegroundColor Cyan }
function Write-Warn   ($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-ErrorX ($m){ Write-Host "[x] $m" -ForegroundColor Red }
function Write-Ok     ($m){ Write-Host "[✓] $m" -ForegroundColor Green }
function Write-Step   ($m){ Write-Host "── $m" -ForegroundColor Magenta }

# ---------- Elevation ----------
function Ensure-Elevated {
    # Check if running as Administrator; if not, relaunch self with UAC prompt.
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not $isAdmin){
        Write-Warn "Administrator privileges required. Restarting with elevation..."
        $exe  = (Get-Process -Id $PID).Path
        # If PSCommandPath is empty (interactive session), use current script path if possible
        if([string]::IsNullOrEmpty($PSCommandPath)){
            Write-Warn "Script path unknown. Start this script from a file to enable auto-elevation."
            exit 1
        }
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

    # Patterns considered dangerous (drive roots, system folders, user profiles, etc.)
    $dangerRoots = @(
        '^([A-Za-z]:\\)?$',                          
        '^[A-Za-z]:\\$',                             
        '^[A-Za-z]:\\Windows(\\.*)?$',               
        '^[A-Za-z]:\\Program Files( \(x86\))?(\\.*)?$',
        '^[A-Za-z]:\\ProgramData(\\.*)?$',
        '^[A-Za-z]:\\Users\\?$',
        '^[A-Za-z]:\\Users\\[^\\]+\\AppData(\\.*)?$'
    )

    foreach($rx in $dangerRoots){
        if($full -match $rx){ return $true }
    }

    # Prevent deleting current user profile
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
    try {
        & attrib -r -h -s "$Target" /s /d 2>$null
    } catch { }

    Write-Step "Taking ownership and resetting ACLs..."
    try {
        & takeown /f "$Target" /r /d y        | Out-Null
        & icacls "$Target" /grant *S-1-5-32-544:(F) /T /C | Out-Null  # Administrators full control
        & icacls "$Target" /inheritance:d /T /C            | Out-Null
        & icacls "$Target" /reset /T /C                    | Out-Null
    } catch {
        Write-Warn "takeown/icacls returned errors, continuing..."
    }
}

# ---------- Delete With Progress ----------
function Delete-WithProgress {
    param([string]$Target)

    # If target is a file -> simple deletion with progress
    if((Test-Path -LiteralPath $Target) -and (Get-Item -LiteralPath $Target).PSIsContainer -eq $false){
        $name = Split-Path -Leaf $Target
        Write-Step "Deleting file: $name"
        Write-Progress -Activity "Deleting" -Status "Removing file" -PercentComplete 0 -Id 1
        try {
            Remove-Item -LiteralPath $Target -Force -ErrorAction Stop
            Write-Progress -Activity "Deleting" -Completed -Id 1
            return $true
        } catch {
            Write-Progress -Activity "Deleting" -Status "Failed" -PercentComplete 100 -Id 1
            Write-Warn "Remove-Item failed for file: $($_.Exception.Message)"
            return $false
        }
    }

    # If target is a folder (or not resolved), enumerate children
    Write-Step "Collecting items to delete (this may take a while for large trees)..."
    try {
        $items = Get-ChildItem -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue -Force | ForEach-Object { $_.FullName }
    } catch {
        Write-Warn "Error enumerating items: $($_.Exception.Message)"
        $items = @()
    }

    # Include the root target itself (delete it last)
    $itemsList = @()
    if($items){ $itemsList += $items }
    $itemsList += $Target

    $total = $itemsList.Count
    if($total -eq 0){
        Write-Warn "No items found under target. Attempting direct removal..."
        try {
            Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction Stop
            return $true
        } catch {
            Write-Warn "Direct removal failed: $($_.Exception.Message)"
            return $false
        }
    }

    $index = 0
    foreach($it in $itemsList){
        $index++
        $percent = [int](($index / $total) * 100)
        $short = if($it.Length -gt 60){ '...' + $it.Substring($it.Length - 57) } else { $it }
        Write-Progress -Activity "Deleting items" -Status "$index of $total: $short" -PercentComplete $percent -Id 1

        try {
            if(Test-Path -LiteralPath $it){
                # If folder, remove contents first then folder - using Remove-Item with -Force
                Remove-Item -LiteralPath $it -Recurse -Force -ErrorAction Stop -Confirm:$false
            }
        } catch {
            # If Remove-Item failed for this individual item, try cmd fallback for file/folder
            try {
                if((Test-Path -LiteralPath $it) -and (Get-Item -LiteralPath $it).PSIsContainer){
                    & cmd /c "rmdir /s /q `"$it`"" 2>$null
                } else {
                    & cmd /c "del /f /q `"$it`"" 2>$null
                }
            } catch {
                # ignore individual failures, continue to next; final check will detect leftover items
            }
        }
    }

    Write-Progress -Activity "Deleting items" -Completed -Id 1

    # Final existence check
    if(Test-Path -LiteralPath $Target){
        Write-Warn "Target still exists after per-item deletion attempts."
        return $false
    } else {
        return $true
    }
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
        if(Test-Path -LiteralPath $Target){
            Write-Warn "Fallback bulk removal failed or target still present."
            return $false
        } else {
            return $true
        }
    } catch {
        Write-Warn "Fallback bulk removal exception: $($_.Exception.Message)"
        return $false
    }
}

# ---------- Main ----------
Ensure-Elevated

$rawPath = Read-Host "Enter the full path of the file or folder to permanently delete"
if([string]::IsNullOrWhiteSpace($rawPath)){
    Write-ErrorX "No path specified."
    exit 1
}

# Resolve if possible, otherwise use literal
try{
    $resolved = Resolve-Path -LiteralPath $rawPath -ErrorAction Stop
    $target   = $resolved.ProviderPath
} catch {
    $target = $rawPath
}

if(-not (Test-Path -LiteralPath $target)){
    Write-Warn "Object not found: $target (continuing anyway; if path is incorrect, deletion will fail)."
}

if(Test-DangerousPath -Path $target){
    Write-ErrorX "Critical system path detected. Aborting to prevent damage."
    exit 2
}

$ext = Get-ExtendedPath -Path $target
Write-Info "Target: $target"
Write-Info "Extended path: $ext"

# Prepare: remove attributes and ACLs
Reset-OwnershipAndAcl -Target $ext

# Delete with interactive progress
$deleted = $false
try {
    $deleted = Delete-WithProgress -Target $ext
} catch {
    Write-Warn "Delete-WithProgress threw an exception: $($_.Exception.Message)"
    $deleted = $false
}

if(-not $deleted){
    # Try a final fallback
    $deleted = Fallback-BulkDelete -Target $ext
}

if($deleted){
    Write-Ok "Done. The object was permanently deleted."
} else {
    Write-ErrorX "Failed to delete the object."
    Write-Warn "Tip: close Explorer, editors, or antivirus processes that may lock files, then retry."
}
