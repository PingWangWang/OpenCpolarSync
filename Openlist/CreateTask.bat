@echo off
chcp 65001 >nul

:: Check for administrator privileges
net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: Please right-click and run as administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"

set "PS_FILE=%~dp0StartOpenList.ps1"
if not exist "%PS_FILE%" (
    echo ERROR: StartOpenList.ps1 not found
    pause
    exit /b 1
)

:: Set schtasks full path
set "SCHTASKS=%windir%\System32\schtasks.exe"

:: Delay format: mmmm:ss (4-digit minutes)
set "DELAY_TIME=0000:12"

:: Escape inner quotes with \" (Win11 standard)
set "TR_CMD=powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_FILE%\""

echo Creating scheduled task (Win11 compatible)...
%SCHTASKS% /create /tn "OpenList Background Service" /tr "%TR_CMD%" /sc onlogon /delay %DELAY_TIME% /rl highest /f

if %errorlevel% neq 0 (
    echo.
    echo Task creation failed! Error code: %errorlevel%
    echo.
    echo Manually run this command in an administrator CMD to debug:
    echo %SCHTASKS% /create /tn "OpenList Background Service" /tr "%TR_CMD%" /sc onlogon /delay %DELAY_TIME% /rl highest /f
) else (
    echo.
    echo Task created successfully. OpenList will start 12 seconds after login.
)
pause
