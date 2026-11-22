@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion
REM Диагностика компьютера, часть 2. Никонов. 22.11.2026.

set "PC_AUDIT_SCRIPT=%~f0"
if /i "%~1"=="--test" goto test

set "report=%~dp0pc_report.txt"
set "work=%TEMP%\pc-audit-%RANDOM%-%RANDOM%"
mkdir "%work%" 2>nul
if errorlevel 1 (
    echo Не удалось создать временную папку.
    pause
    exit /b 1
)

type nul >"%report%" 2>nul
if errorlevel 1 (
    echo Не удалось записать отчёт. Перенесите батник в папку, куда можно сохранять файлы.
    rd "%work%" 2>nul
    pause
    exit /b 1
)

set "PC_AUDIT_RAW=%work%\apps_list.txt"
set "PC_AUDIT_SORTED=%work%\apps_sorted.txt"
call :log "Диагностика компьютера"
call :log "Дата: %date% %time%"
call :log "Собираю сведения о Windows, процессоре, памяти и диске..."

REM Каждый параметр заполняется заново. Если одного значения нет, остальные всё равно выводятся.
for %%V in (Caption Version CPU TotalRam FreeRam DiskSize DiskFree) do set "%%V="
call :runPowerShell system >"%work%\system.txt"
for /f "usebackq tokens=1,* delims==" %%A in ("%work%\system.txt") do set "%%A=%%B"

call :blank
call :log "Операционная система"
call :field "Название" Caption
call :field "Версия" Version
call :blank
call :log "Процессор"
call :field "Модель" CPU
call :blank
call :log "Оперативная память"
call :field "Всего памяти" TotalRam " ГБ"
call :field "Свободно памяти" FreeRam " ГБ"
call :blank
call :log "Диск C"
call :field "Всего места" DiskSize " ГБ"
call :field "Свободно места" DiskFree " ГБ"
call :blank

REM В общий список идут только значения DisplayName из разделов Uninstall.
call :log "Читаю список программ из реестра..."
(
    call :registry "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    call :registry "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    call :registry "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall"
) >"%PC_AUDIT_RAW%"

call :log "Сравниваю список с офисным набором..."
call :runPowerShell audit >"%work%\audit.txt"
if errorlevel 1 goto auditFailed

call :blank
call :log "Установленные программы"
call :readLines "%PC_AUDIT_SORTED%"
call :blank
call :readLines "%work%\audit.txt"
goto done

:auditFailed
call :log "Не удалось выполнить проверку списка программ."

:done
call :blank
call :log "Отчёт сохранён"
set "line=Путь к отчёту: %report%"
call :log
del /q "%work%\system.txt" "%PC_AUDIT_RAW%" "%PC_AUDIT_SORTED%" "%work%\audit.txt" 2>nul
rd "%work%" 2>nul
pause
exit /b 0

:test
call :runPowerShell test
exit /b %errorlevel%

:runPowerShell
REM PowerShell-код находится в конце этого же файла.
powershell.exe -NoProfile -Command "$src = [IO.File]::ReadAllText($env:PC_AUDIT_SCRIPT); $mark = '# --- PowerShell ---'; $start = $src.LastIndexOf($mark) + $mark.Length; & ([ScriptBlock]::Create($src.Substring($start))) '%~1'"
exit /b %errorlevel%

:registry
for /f "tokens=1,2,*" %%A in ('reg query "%~1" /s /v DisplayName 2^>nul') do (
    if /i "%%A"=="DisplayName" (
        set "app=%%C"
        setlocal EnableDelayedExpansion
        if defined app echo(!app!
        endlocal
    )
)
exit /b

:readLines
REM Строки из файлов передаются через переменную, чтобы CALL не разобрал спецсимволы повторно.
for /f "usebackq delims=" %%L in ("%~1") do (
    set "line=%%L"
    call :log
)
exit /b

:field
setlocal EnableDelayedExpansion
set "line=%~1: данные получить не удалось"
if defined %~2 set "line=%~1: !%~2!%~3"
call :log
endlocal
exit /b

:blank
set "line="
call :log
exit /b

:log
setlocal EnableDelayedExpansion
if not "%~1"=="" set "line=%~1"
echo(!line!
>>"!report!" echo(!line!
endlocal
exit /b

# --- PowerShell ---
param([string]$Mode)

$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
$ErrorActionPreference = 'Stop'

function Write-SystemInfo {
    # Ошибка получения одного класса не мешает вывести данные из остальных.
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue

    'Caption=' + $os.Caption
    'Version=' + $os.Version
    'CPU=' + ($cpu.Name -join ', ')
    if ($os.TotalVisibleMemorySize -gt 0) {
        'TotalRam=' + [Math]::Floor($os.TotalVisibleMemorySize / 1MB)
    }
    if ($null -ne $os.FreePhysicalMemory) {
        'FreeRam=' + [Math]::Floor($os.FreePhysicalMemory / 1MB)
    }
    if ($disk.Size -gt 0) {
        'DiskSize=' + [Math]::Floor($disk.Size / 1GB)
    }
    if ($null -ne $disk.FreeSpace) {
        'DiskFree=' + [Math]::Floor($disk.FreeSpace / 1GB)
    }
}

function Get-AuditLines([string[]]$Apps) {
    # Ищем названия без учёта регистра. Границы слов уменьшают ложные совпадения.
    $office = @(
        @{ Name = 'Офисный пакет'; Pattern = '^(?:Microsoft (?:Office(?!.*(?:Click-to-Run|Component|Extensibility|Licensing|Proofing))|365|Word)|LibreOffice|(?:Apache )?OpenOffice|МойОфис)\b'; Advice = 'Для документов можно установить LibreOffice или Microsoft Office.' }
        @{ Name = 'Браузер'; Pattern = '^(?:Google Chrome(?! Remote Desktop)|Mozilla Firefox|Microsoft Edge(?!.*(?:WebView|Update))|Яндекс(?:[ .]Браузер)?|Yandex Browser)\b'; Advice = 'Для рабочих сайтов можно настроить Chrome, Firefox или Edge.' }
        @{ Name = 'Чтение PDF'; Pattern = '^(?:Adobe Acrobat|Foxit(?: PDF Reader| Reader)|SumatraPDF)\b'; Advice = 'Для отдельной программы чтения PDF подойдут SumatraPDF или Foxit PDF Reader.' }
        @{ Name = 'Архиватор'; Pattern = '^(?:7-Zip|WinRAR|WinZip)\b'; Advice = 'Для работы с архивами можно установить 7-Zip или WinRAR.' }
        @{ Name = 'Антивирус'; Pattern = '\b(?:Microsoft Defender|Windows Defender|Kaspersky|ESET|Dr[. ]Web)\b'; Advice = 'Проверьте, включён ли Microsoft Defender, или уточните, какой антивирус принят в организации.' }
    )
    $groups = @(
        @{ Name = 'Игры и игровые платформы'; Pattern = '\b(?:Steam|Epic Games|GOG|Origin|EA app|Ubisoft Connect|Battle\.net|Riot|games?|gaming|Counter-Strike|Roblox)\b' }
        @{ Name = 'Торрент-клиенты'; Pattern = '\b(?:torrent|[uµ]Torrent|BitTorrent|qBittorrent|Vuze|Transmission)\b' }
        @{ Name = 'Мессенджеры'; Pattern = '\b(?:Discord|Telegram|WhatsApp|Viber|Skype)\b' }
        @{ Name = 'Развлечения и оформление'; Pattern = '\b(?:Wallpaper Engine|OBS|Soundpad|VLC)\b' }
    )

    if ($Apps.Count -eq 0) {
        'Базовое ПО'
        'Список программ получить не удалось. Наличие базового ПО не проверено.'
        'Программы для проверки'
        'Поиск по группам пропущен.'
        'Проверено категорий базового ПО: 0. Рекомендаций: 0.'
        return
    }

    $count = 0
    'Базовое ПО'
    foreach ($category in $office) {
        $found = @($Apps | Where-Object { $_ -match $category.Pattern })
        if ($found.Count -eq 0) {
            '{0}: не найдено. {1}' -f $category.Name, $category.Advice
            $count++
            continue
        }

        '{0}: найдено — {1}' -f $category.Name, ($found -join ', ')
        if ($category.Name -eq 'Браузер' -and $found -match '^Microsoft Edge\b') {
            '  Edge может быть компонентом Windows. Настройки браузера не проверяются.'
        }
    }

    '--------------------------------------------------'
    'Программы для проверки'
    foreach ($group in $groups) {
        '{0}:' -f $group.Name
        $found = @($Apps | Where-Object { $_ -match $group.Pattern })
        if ($found.Count -eq 0) {
            '  Совпадений нет.'
            continue
        }
        foreach ($app in $found) {
            '  Проверить: {0}' -f $app
            $count++
        }
    }

    'Уточните назначение этих программ перед принятием решения об удалении.'
    'Проверено категорий базового ПО: {0}. Рекомендаций: {1}.' -f $office.Count, $count
}

function Test-Audit {
    $base = @('МойОфис', 'Microsoft Edge', 'SumatraPDF', 'winrar 7.01', 'ESET Endpoint Security')
    $first = @(Get-AuditLines ($base + @('qBittorrent', 'Telegram Desktop')))
    if ($first -notcontains 'Архиватор: найдено — winrar 7.01' -or
        $first -notcontains '  Проверить: qBittorrent' -or
        $first -notcontains '  Проверить: Telegram Desktop' -or
        $first -notcontains 'Проверено категорий базового ПО: 5. Рекомендаций: 2.') {
        throw 'Проверка установленного ПО не прошла.'
    }

    $second = @(Get-AuditLines @($base | Where-Object { $_ -notmatch 'WinRAR' }))
    if ($second -notcontains 'Архиватор: не найдено. Для работы с архивами можно установить 7-Zip или WinRAR.' -or
        $second -notcontains 'Проверено категорий базового ПО: 5. Рекомендаций: 1.') {
        throw 'Проверка списка без архиватора не прошла.'
    }

    $empty = @(Get-AuditLines @())
    if ($empty -notcontains 'Проверено категорий базового ПО: 0. Рекомендаций: 0.') {
        throw 'Проверка пустого списка не прошла.'
    }
    'Самопроверка прошла: найденные программы, отсутствие архиватора, пустой список.'
}

switch ($Mode) {
    'system' { Write-SystemInfo }
    'audit' {
        $apps = @(Get-Content -LiteralPath $env:PC_AUDIT_RAW -Encoding UTF8 |
            ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        [IO.File]::WriteAllLines($env:PC_AUDIT_SORTED, [string[]]$apps, $utf8)
        if ($apps.Count -eq 0) { 'Список программ пуст или недоступен.' }
        Get-AuditLines $apps
    }
    'test' { Test-Audit }
}
