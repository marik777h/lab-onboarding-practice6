@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion
REM Практическая работа 8. Диагностика компьютера
REM Автор: marik777h. Дата: 12.11.2026

set "report=%~dp0pc_report.txt"
type nul >"%report%" 2>nul
if errorlevel 1 (
    echo Не удалось создать отчёт. Перенесите папку в Документы.
    pause
    exit /b 1
)

REM Получение сведений об ОС, процессоре и памяти
where wmic >nul 2>nul
if errorlevel 1 goto cim

for /f "tokens=1,* delims==" %%A in ('wmic os get Caption^,Version^,TotalVisibleMemorySize^,FreePhysicalMemory /value 2^>nul') do (
    for /f "delims=" %%C in ("%%B") do set "%%A=%%C"
)
for /f "tokens=1,* delims==" %%A in ('wmic cpu get Name /value 2^>nul') do (
    for /f "delims=" %%C in ("%%B") do set "cpu=%%C"
)

REM Получение размера диска C в байтах
for /f "tokens=1,* delims==" %%A in ('wmic logicaldisk where "DeviceID='C:'" get Size^,FreeSpace /value 2^>nul') do (
    for /f "delims=" %%C in ("%%B") do set "%%A=%%C"
)
goto output

:cim
REM В новых Windows вместо WMIC используется Get-CimInstance
for /f "tokens=1,* delims==" %%A in ('powershell.exe -NoProfile -Command "$o=Get-CimInstance Win32_OperatingSystem; $p=Get-CimInstance Win32_Processor; $d=Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq 'C:'; 'Caption='+$o.Caption; 'Version='+$o.Version; 'TotalVisibleMemorySize='+$o.TotalVisibleMemorySize; 'FreePhysicalMemory='+$o.FreePhysicalMemory; 'cpu='+($p.Name -join ', '); 'Size='+$d.Size; 'FreeSpace='+$d.FreeSpace"') do set "%%A=%%B"

:output
setlocal EnableDelayedExpansion
set "line=Диагностика компьютера"
call :print
set "line=Дата: %date% %time%"
call :print
set "line=----------------------------------------"
call :print

REM Операционная система
set "line=Операционная система"
call :print
set "line=Название: !Caption!"
call :print
set "line=Версия: !Version!"
call :print
set "line="
call :print

REM Процессор
set "line=Процессор"
call :print
set "line=!cpu!"
call :print
set "line="
call :print

REM Перевод памяти из КБ в ГБ
set "line=Оперативная память"
call :print
if defined TotalVisibleMemorySize (
    set /a totalRam=TotalVisibleMemorySize / 1048576
    set "line=Всего памяти: !totalRam! ГБ"
) else (
    set "line=Всего памяти: нет данных"
)
call :print
if defined FreePhysicalMemory (
    set /a freeRam=FreePhysicalMemory / 1048576
    set "line=Свободно памяти: !freeRam! ГБ"
) else (
    set "line=Свободно памяти: нет данных"
)
call :print
set "line="
call :print

REM Перевод размера диска из байтов в ГБ
set "line=Диск C"
call :print
if defined Size (
    set "number=!Size!"
    call :gigabytes
    set "line=Всего места: !number! ГБ"
) else (
    set "line=Всего места: нет данных"
)
call :print
if defined FreeSpace (
    set "number=!FreeSpace!"
    call :gigabytes
    set "line=Свободно места: !number! ГБ"
) else (
    set "line=Свободно места: нет данных"
)
call :print
set "line="
call :print

REM Названия программ из реестра
set "line=Установленные программы"
call :print
set "line=----------------------------------------"
call :print
setlocal DisableDelayedExpansion
for %%K in (
    "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall"
) do (
    for /f "tokens=1,2,*" %%A in ('reg query "%%~K" /s /v DisplayName 2^>nul ^| findstr /c:"DisplayName"') do (
        set "program=%%C"
        setlocal EnableDelayedExpansion
        if not "!program!"=="" (
            set "line=!program!"
            call :print
        )
        endlocal
    )
)
endlocal
set "line="
call :print
set "line=Отчёт сохранён"
call :print
pause
exit /b

:print
REM Одна и та же строка в окне и в файле
echo(!line!
>>"!report!" echo(!line!
exit /b

:gigabytes
REM Три деления на 1024 равны делению на 1073741824.
REM Поразрядное деление нужно, чтобы set /a не переполнялся.
for /l %%N in (1,1,3) do (
    set "digits=!number!"
    set "result="
    set /a remainder=0
    for /l %%I in (0,1,24) do (
        set "digit=!digits:~%%I,1!"
        if defined digit (
            set /a "value=remainder*10+digit, part=value/1024, remainder=value%%1024"
            if defined result (
                set "result=!result!!part!"
            ) else (
                if not "!part!"=="0" set "result=!part!"
            )
        )
    )
    if not defined result set "result=0"
    set "number=!result!"
)
exit /b
