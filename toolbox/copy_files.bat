@echo off
:: Проверяем что мы в правильной директории
if not exist "output\" (
    echo ERROR: output folder not found!
    echo Please run this script from the toolbox folder
    pause
    exit /b 1
)
if not exist "..\db\" (
    echo ERROR: db folder not found!
    echo Please check pfQuest directory structure
    pause
    exit /b 1
)

:: Создаем резервную копию старых файлов в корне db
if exist "..\db\*.lua" (
    if not exist "..\db\backup\" mkdir "..\db\backup"
    copy "..\db\*.lua" "..\db\backup\" >nul 2>&1
)

:: Копируем основные файлы
copy /Y "output\*.lua" "..\db\" >nul
if %errorlevel% neq 0 (
    echo ERROR: Failed to copy main files
    pause
    exit /b 1
)

:: Динамически обрабатываем все папки с локализацией (enUS, ruRU и т.д.)
for /d %%L in ("output\*") do (
    echo Copying locale: %%~nxL
    
    :: Создаем директорию локализации в db если ее нет
    if not exist "..\db\%%~nxL\" mkdir "..\db\%%~nxL"
    
    :: Создаем бекап
    if exist "..\db\%%~nxL\*.lua" (
        if not exist "..\db\%%~nxL\backup\" mkdir "..\db\%%~nxL\backup"
        copy "..\db\%%~nxL\*.lua" "..\db\%%~nxL\backup\" >nul 2>&1
    )
    
    :: Копируем файлы локализации
    copy /Y "%%L\*.lua" "..\db\%%~nxL\" >nul
    if %errorlevel% neq 0 (
        echo ERROR: Failed to copy locale files for %%~nxL
        pause
        exit /b 1
    )
)

:: Не делаем pause если запущено автоматически
if "%1"=="auto" goto :eof
echo.
echo ===============================================
echo File transfer completed successfully!
echo ===============================================
pause