@echo off
chcp 65001 >nul

:: Check for administrator privileges
net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: Please right-click and run as administrator!
    pause
    exit /b 1
)

:: Use full path
set "SCHTASKS=%windir%\System32\schtasks.exe"

echo Removing scheduled task "OpenList Background Service" ...
%SCHTASKS% /delete /tn "OpenList Background Service" /f

if %errorlevel% neq 0 (
    echo.
    echo Task deletion failed (task may not exist or insufficient permissions)
    echo Error code: %errorlevel%
) else (
    echo.
    echo OpenList auto-start task has been removed successfully.
)

pause
