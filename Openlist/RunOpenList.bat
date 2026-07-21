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

set "POWERSHELL=%windir%\System32\WindowsPowerShell\v1.0\powershell.exe"

echo Starting openlist (waiting 15s)...
"%POWERSHELL%" -ExecutionPolicy Bypass -File "%PS_FILE%"

if %errorlevel% neq 0 (
    echo.
    echo Script execution failed with error code: %errorlevel%
    echo Check start_log.txt for details.
) else (
    echo.
    echo Script completed successfully.
)
pause