@echo off
:: Check if we are in the correct directory
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

:: Create a backup of old files in the db root
if exist "..\db\*.lua" (
    if not exist "..\db\backup\" mkdir "..\db\backup"
    copy "..\db\*.lua" "..\db\backup\" >nul 2>&1
)

:: Copy main files
copy /Y "output\*.lua" "..\db\" >nul
if %errorlevel% neq 0 (
    echo ERROR: Failed to copy main files
    pause
    exit /b 1
)

:: Dynamically process all locale folders (enUS, ruRU, etc.)
for /d %%L in ("output\*") do (
    echo Copying locale: %%~nxL
    
    :: Create locale directory in db if it doesn't exist
    if not exist "..\db\%%~nxL\" mkdir "..\db\%%~nxL"
    
    :: Create backup
    if exist "..\db\%%~nxL\*.lua" (
        if not exist "..\db\%%~nxL\backup\" mkdir "..\db\%%~nxL\backup"
        copy "..\db\%%~nxL\*.lua" "..\db\%%~nxL\backup\" >nul 2>&1
    )
    
    :: Copy locale files
    copy /Y "%%L\*.lua" "..\db\%%~nxL\" >nul
    if %errorlevel% neq 0 (
        echo ERROR: Failed to copy locale files for %%~nxL
        pause
        exit /b 1
    )
)

:: Do not pause if running automatically
if "%1"=="auto" goto :eof
echo.
echo ===============================================
echo File transfer completed successfully!
echo ===============================================
pause