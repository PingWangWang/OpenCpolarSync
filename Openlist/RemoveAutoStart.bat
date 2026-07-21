@echo off
chcp 65001 >nul
cd /d "%~dp0"

for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v Startup 2^>nul') do set "STARTUP=%%b"
if "%STARTUP%"=="" (
    echo Error: Unable to get the startup folder path.
    pause
    exit /b 1
)

set "LNK=%STARTUP%\OpenList 文件管理.lnk"

if not exist "%LNK%" (
    echo Startup shortcut not found, nothing to remove.
    pause
    exit /b 0
)

del /f /q "%LNK%" >nul 2>&1
if exist "%LNK%" (
    echo Failed to delete shortcut. Please check manually: %LNK%
) else (
    echo Startup shortcut removed. OpenList will no longer start on next login.
)
pause
