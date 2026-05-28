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
:: Создаем резервную копию старых файлов
if exist "..\db\*.lua" (
    if not exist "..\db\backup\" mkdir "..\db\backup"
    copy "..\db\*.lua" "..\db\backup\" >nul 2>&1
)
if exist "..\db\enUS\*.lua" (
    if not exist "..\db\enUS\backup\" mkdir "..\db\enUS\backup"
    copy "..\db\enUS\*.lua" "..\db\enUS\backup\" >nul 2>&1
)
:: Копируем основные файлы
copy /Y "output\*.lua" "..\db\" >nul
if %errorlevel% neq 0 (
    echo ERROR: Failed to copy main files
    pause
    exit /b 1
)
:: Создаем enUS директорию если не существует
if not exist "..\db\enUS\" mkdir "..\db\enUS"
:: Копируем файлы локализации
copy /Y "output\enUS\*.lua" "..\db\enUS\" >nul
if %errorlevel% neq 0 (
    echo ERROR: Failed to copy locale files
    pause
    exit /b 1
)
:: Не делаем pause если запущено автоматически
if "%1"=="auto" goto :eof
echo.
echo ===============================================
echo File transfer completed successfully!
echo ===============================================
pause
