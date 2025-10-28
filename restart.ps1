# PowerShell 7+
# Принудительная перезагрузка списка ПК через WinRM

$Computers = @(
  'SALA10-LAP','SALA11-LAP','SALA12-LAP','SALA13-LAP','SALA14-LAP','SALA15-LAP',
  'SALA16-LAP','SALA17-LAP','SALA18-LAP','SALA19-LAP','SALA20-LAP','SALA21-LAP',
  'SALA22-LAP','SALA22-LAP2','SALA23-LAP','SALA24-LAP','SALA25-LAP','SALA26-LAP',
  'SALA27-LAP','SALA28-LAP','SALA29-LAP','SALA30-LAP','SALA31-LAP','SALA32-LAP',
  'SALA33-LAP','SALA34-LAP','SALA35-PC','SALA36-PC','SALA37-PC',
  'POKOJNAUCZ1-PC','POKOJNAUCZ2-PC','POKOJNAUCZ3-PC','POKOJNAUCZ4-PC','SALAN1-LAP'
)

# Настройки
$ForceRestart = $true
$DelayBeforeSeconds = 0
$ThrottleLimit = 24

# Опционально спросить креды
$Cred = Get-Credential -Message "Введите учётку с правами на удалённый рестарт"

$restartSb = {
    param([int]$Delay, [bool]$Force)

    if ($Delay -gt 0) {
        $args = '/r','/t',$Delay,'/c','Planowany restart przez administratora'
        if ($Force) { $args += '/f' }
        Start-Process -FilePath "shutdown.exe" -ArgumentList $args -WindowStyle Hidden
        "SCHEDULED:$Delay"
    }
    else {
        Restart-Computer -Force:$Force
        "INSTANT"
    }
}

Write-Host "Запускаю перезагрузку $($Computers.Count) компьютеров..." -ForegroundColor Yellow

$results = $Computers | ForEach-Object -Parallel {
    try {
        Invoke-Command -ComputerName $_ -Credential $using:Cred -ScriptBlock $using:restartSb -ArgumentList $using:DelayBeforeSeconds,$using:ForceRestart -ErrorAction Stop
        [pscustomobject]@{Computer=$_;Status="OK"}
    }
    catch {
        [pscustomobject]@{Computer=$_;Status="FAIL";Error=$_.Exception.Message}
    }
} -ThrottleLimit $ThrottleLimit

$results | Format-Table -AutoSize
