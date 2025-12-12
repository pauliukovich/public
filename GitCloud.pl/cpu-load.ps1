# CPU-Load-Monitor.ps1
# PowerShell 7
# Average CPU load + CPU temperature
# Output: C:\Windows\database\cpu-load\cpu-load.txt

$OutFile = "C:\Windows\database\cpu-load\cpu-load.txt"

# Ensure directory exists
$dir = Split-Path $OutFile
if (!(Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$serverName = $env:COMPUTERNAME

# -------- CPU INFO --------
$cpuInfo = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
$cpuName    = $cpuInfo.Name
$cpuCores   = $cpuInfo.NumberOfCores
$cpuLogical = $cpuInfo.NumberOfLogicalProcessors

# -------- CPU LOAD (AVERAGE, ??? Get-Counter) --------
# 5 ??????? ?? 2 ??????? ? 10 ?????? ??????????

$samples     = 5
$intervalSec = 2
$values      = @()

for ($i = 0; $i -lt $samples; $i++) {
    $loadObjs = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
    if ($loadObjs) {
        $avgSample = ($loadObjs | Measure-Object -Property LoadPercentage -Average).Average
        if ($avgSample -ne $null) {
            $values += [Math]::Round($avgSample, 1)
        }
    }
    Start-Sleep -Seconds $intervalSec
}

if ($values.Count -eq 0) {
    $nowLoad = 0
    $avgLoad = 0
    $maxLoad = 0
    $minLoad = 0
} else {
    $nowLoad = $values[-1]
    $avgLoad = [Math]::Round(($values | Measure-Object -Average).Average, 1)
    $maxLoad = [Math]::Round(($values | Measure-Object -Maximum).Maximum, 1)
    $minLoad = [Math]::Round(($values | Measure-Object -Minimum).Minimum, 1)
}

# -------- CPU TEMPERATURE --------

$cpuTempC      = $null
$cpuTempSource = "N/A"

try {
    $t = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop |
         Select-Object -First 1

    if ($t -and $t.CurrentTemperature -gt 0) {
        $cpuTempC = [Math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
        $cpuTempSource = "MSAcpi_ThermalZoneTemperature"
    }
}
catch {
    # ??????? ????? ?? ???? - ??? ?????????
}

# -------- WRITE OUTPUT FILE --------

"===== CPU LOAD ====="                                  | Out-File $OutFile -Encoding UTF8
"Server : $serverName"                                  | Out-File $OutFile -Append -Encoding UTF8
"Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"    | Out-File $OutFile -Append -Encoding UTF8
""                                                      | Out-File $OutFile -Append -Encoding UTF8

"CPU Model        : $cpuName"                           | Out-File $OutFile -Append -Encoding UTF8
"Cores / Logical  : $cpuCores / $cpuLogical"            | Out-File $OutFile -Append -Encoding UTF8
""                                                      | Out-File $OutFile -Append -Encoding UTF8

"Current Load     : $nowLoad %"                         | Out-File $OutFile -Append -Encoding UTF8
"Average Load 10s : $avgLoad %"                         | Out-File $OutFile -Append -Encoding UTF8
"Max Load 10s     : $maxLoad %"                         | Out-File $OutFile -Append -Encoding UTF8
"Min Load 10s     : $minLoad %"                         | Out-File $OutFile -Append -Encoding UTF8
""                                                      | Out-File $OutFile -Append -Encoding UTF8

if ($cpuTempC -ne $null) {
    "CPU Temperature : $cpuTempC °C"                    | Out-File $OutFile -Append -Encoding UTF8
    "Temp Source     : $cpuTempSource"                  | Out-File $OutFile -Append -Encoding UTF8
}
else {
    "CPU Temperature : N/A (no sensor available)"       | Out-File $OutFile -Append -Encoding UTF8
    "Temp Source     : $cpuTempSource"                  | Out-File $OutFile -Append -Encoding UTF8
}
