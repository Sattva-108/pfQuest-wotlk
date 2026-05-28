@echo off
echo ===============================================
echo pfQuest File Transfer Script
echo ===============================================
echo.

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

:: Создаем резервную копию старых файлов (опционально)
echo Creating backup of existing files...
if exist "..\db\*.lua" (
    if not exist "..\db\backup\" mkdir "..\db\backup"
    copy "..\db\*.lua" "..\db\backup\" >nul 2>&1
    echo   - Main files backed up to db\backup\
)

if exist "..\db\enUS\*.lua" (
    if not exist "..\db\enUS\backup\" mkdir "..\db\enUS\backup"
    copy "..\db\enUS\*.lua" "..\db\enUS\backup\" >nul 2>&1
    echo   - Locale files backed up to db\enUS\backup\
)

echo.
echo Copying new files from output to db...

:: Копируем основные файлы
echo   - Copying main database files...
copy /Y "output\*.lua" "..\db\" >nul
if %errorlevel% equ 0 (
    echo     SUCCESS: Main files copied
) else (
    echo     ERROR: Failed to copy main files
    pause
    exit /b 1
)

:: Создаем enUS директорию если не существует
if not exist "..\db\enUS\" mkdir "..\db\enUS"

:: Копируем файлы локализации
echo   - Copying locale files...
copy /Y "output\enUS\*.lua" "..\db\enUS\" >nul
if %errorlevel% equ 0 (
    echo     SUCCESS: Locale files copied
) else (
    echo     ERROR: Failed to copy locale files
    pause
    exit /b 1
)

echo.
echo ===============================================
echo File transfer completed successfully!
echo ===============================================

:: Показываем статистику скопированных файлов
echo.
echo Files in db folder:
dir /b "..\db\*.lua" 2>nul | find /c /v "" && echo main files copied

echo.
echo Files in db\enUS folder:
dir /b "..\db\enUS\*.lua" 2>nul | find /c /v "" && echo locale files copied

echo.
echo ===============================================
echo Ready for in-game testing!
echo ===============================================
echo.
echo Next steps:
echo 1. Launch WoW 3.3.5a client
echo 2. Load a character
echo 3. Test command: /run local count = 0; for _ in pairs(pfDB["quests"]["data"]) do count = count + 1 end; print("Total quests loaded:", count)
echo 4. Expected result: ~9000 quests
echo.
pause
