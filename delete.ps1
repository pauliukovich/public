# Remove-ExpressVPN.ps1
# Удаляет папку ExpressVPN рекурсивно с принудительным снятием прав (PowerShell 5 compatible)
# Запускать ОТ АДМИНИСТРАТОРА!

$Path = 'C:\Program Files (x86)\ExpressVPN'

function Write-Info($msg){ Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg){ Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Err($msg){ Write-Host "[ERR] $msg" -ForegroundColor Red }

# Проверка прав администратора
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Err "Скрипт должен быть запущен от имени администратора. Завершение."
    exit 1
}

# Проверка существования папки
if (-not (Test-Path -LiteralPath $Path)) {
    Write-Err "Путь не найден: $Path"
    exit 1
}

Write-Info "Начинаю удаление: $Path"

try {
    # 1) Останавливаем сервисы с именем, содержащим 'express' (если есть)
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'express' -or $_.DisplayName -match 'express' }
    if ($svc) {
        foreach ($s in $svc) {
            Write-Info "Останавливаю службу: $($s.Name)"
            try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; Write-Ok "Служба $($s.Name) остановлена" } catch { Write-Err "Не удалось остановить службу $($s.Name): $_" }
        }
    } else { Write-Info "Службы express не найдены." }

    # 2) Завершаем процессы с именем содержащим 'expressvpn' или 'express'
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'expressvpn' -or $_.Name -match '^express' }
    if ($procs) {
        foreach ($p in $procs) {
            Write-Info "Убиваю процесс: $($p.ProcessName) (Id $($p.Id))"
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; Write-Ok "Процесс $($p.ProcessName) завершён" } catch { Write-Err "Не удалось завершить процесс $($p.ProcessName): $_" }
        }
    } else { Write-Info "Процессы expressvpn не найдены." }

    # 3) Снимаем атрибуты 'ReadOnly' и 'System' рекурсивно
    Write-Info "Снимаю атрибуты ReadOnly/System рекурсивно"
    try {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Attributes = 'Normal' } catch { }
        }
        Write-Ok "Атрибуты сняты"
    } catch {
        Write-Err "Ошибка при снятии атрибутов: $_"
    }

    # 4) Берём владение и выдаём полный доступ группе Administrators (используем takeown + icacls для PS5 совместимости)
    Write-Info "Беру владение (takeown) и выдаю полный доступ Administrators (icacls)"
    $takeownCmd = "takeown /F `"$Path`" /R /D Y"
    $icaclsCmd  = "icacls `"$Path`" /grant `"Administrators:F`" /T /C"

    cmd.exe /c $takeownCmd 2>&1 | ForEach-Object { Write-Info $_ }
    cmd.exe /c $icaclsCmd 2>&1 | ForEach-Object { Write-Info $_ }

    # 5) Пытаемся удалить через Remove-Item
    Write-Info "Пробую Remove-Item -Recurse -Force"
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    Write-Ok "Папка успешно удалена через Remove-Item."
    exit 0
}
catch {
    Write-Err "Remove-Item не сработал: $_. Попытка принудительного удаления через rd.exe"
    try {
        # Доп. попытка: убедиться, что внутри нет заблокированных файлов: повторно убиваем процессы и снимаем атрибуты
        Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'expressvpn' -or $_.Name -match '^express' } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Attributes = 'Normal' } catch { }
        }

        # Финальная принудительная команда удаления через cmd (rd /s /q)
        $cmd = "rd /s /q `"$Path`""
        $proc = Start-Process -FilePath cmd.exe -ArgumentList "/c $cmd" -Verb runAs -Wait -NoNewWindow -PassThru
        if (Test-Path -LiteralPath $Path) {
            Write-Err "После rd папка всё ещё существует. Возможно, файл занят или права не сняты."
            exit 2
        } else {
            Write-Ok "Папка удалена через rd."
            exit 0
        }
    } catch {
        Write-Err "Не удалось принудительно удалить папку: $_"
        exit 3
    }
}
