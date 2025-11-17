# Hide-Shutdown-Local.ps1
# Hides only "Shut down" button in Start menu power options on this machine.
# Keeps "Restart" and "Sign out". Hides "Sleep" and "Hibernate".
# Run this script as Administrator.

Write-Host "=== Local Power Options Policy Deployment ===" -ForegroundColor Cyan

# Base path for PolicyManager Start settings
$basePath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Start'

# Ensure base key exists
if (-not (Test-Path $basePath)) {
    New-Item -Path $basePath -Force | Out-Null
    Write-Host "[INFO] Created base key: $basePath"
}

# 1 = hidden, 0 = visible
$settings = @{
    'HideShutDown'  = 1  # hide "Shut down"
    'HideRestart'   = 0  # keep "Restart"
    'HideSignOut'   = 0  # keep "Sign out"
    'HideSleep'     = 1  # hide "Sleep"
    'HideHibernate' = 1  # hide "Hibernate"
}

foreach ($name in $settings.Keys) {
    $keyPath = Join-Path $basePath $name

    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
        Write-Host "[INFO] Created key: $keyPath"
    }

    New-ItemProperty -Path $keyPath -Name 'value' -PropertyType DWord -Value $settings[$name] -Force | Out-Null
    Write-Host "[OK] Set $name -> value = $($settings[$name])"
}

# Read back values
$result = [PSCustomObject]@{
    HideShutDown  = (Get-ItemProperty -Path (Join-Path $basePath 'HideShutDown')  -Name 'value' -ErrorAction SilentlyContinue).value
    HideRestart   = (Get-ItemProperty -Path (Join-Path $basePath 'HideRestart')   -Name 'value' -ErrorAction SilentlyContinue).value
    HideSignOut   = (Get-ItemProperty -Path (Join-Path $basePath 'HideSignOut')   -Name 'value' -ErrorAction SilentlyContinue).value
    HideSleep     = (Get-ItemProperty -Path (Join-Path $basePath 'HideSleep')     -Name 'value' -ErrorAction SilentlyContinue).value
    HideHibernate = (Get-ItemProperty -Path (Join-Path $basePath 'HideHibernate') -Name 'value' -ErrorAction SilentlyContinue).value
}

Write-Host ""
Write-Host "=== Applied Settings (current machine) ===" -ForegroundColor Green
$result | Format-Table | Out-String | Write-Host

Write-Host ""
Write-Host "Note:" -ForegroundColor Yellow
Write-Host "- You may need to sign out or reboot for Start menu changes to fully apply."
Write-Host "- In most cases, logoff is enough." 
Write-Host ""
Write-Host "Done." -ForegroundColor Green
