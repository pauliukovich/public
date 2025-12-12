# Get-Server-Logins.ps1
# PowerShell 7 — вывод локально залогиненных пользователей + время логина

$OutDir = "C:\Windows\database\login"
$OutFile = Join-Path $OutDir "serwer-login.txt"

# Создаём каталог если нет
if (!(Test-Path $OutDir)) {
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
}

# Получаем список текущих пользовательских сессий через quser
$quser = quser 2>$null

if (-not $quser) {
    "Нет активных пользовательских сессий." | Out-File -FilePath $OutFile -Encoding UTF8
    exit
}

# Пропускаем строку заголовков и парсим
$parsed = $quser | Select-Object -Skip 1 | ForEach-Object {
    $line = $_.Trim() -replace '\s+', ' '
    $parts = $line.Split(' ')

    [PSCustomObject]@{
        Username   = $parts[0]
        Session    = $parts[1]
        ID         = $parts[2]
        State      = $parts[3]
        LogonTime  = ($parts[4..($parts.Length-1)] -join ' ')
    }
}

# Формируем отчёт
$report = @()
$report += "===== LOCAL SERVER LOGIN REPORT ====="
$report += "Server: $env:COMPUTERNAME"
$report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += ""
$report += "Active Logons:"
$report += ""

foreach ($u in $parsed) {
    $report += "User: $($u.Username)"
    $report += "Session: $($u.Session)"
    $report += "ID: $($u.ID)"
    $report += "State: $($u.State)"
    $report += "Logon Time: $($u.LogonTime)"
    $report += ""
}

# Пишем в файл
$report | Out-File -FilePath $OutFile -Encoding UTF8

# Дублируем в консоль
$report
