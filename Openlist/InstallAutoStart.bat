@echo off
cd /d "%~dp0"

if not exist "OpenlistGuard.ps1" (
    echo Error: OpenlistGuard.ps1 not found. Please run this script from the Openlist directory.
    pause
    exit /b 1
)

:: Get shell:startup folder path
for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v Startup 2^>nul') do set "STARTUP=%%b"
if "%STARTUP%"=="" (
    echo Error: Unable to get the startup folder path.
    pause
    exit /b 1
)

set "LNK=%STARTUP%\OpenlistGuard.lnk"
set "TARGET=%~dp0OpenlistGuard.ps1"
set "WORKDIR=%~dp0"

:: Create shortcut via PowerShell
:: Note: keep arguments minimal to avoid AV behavior detection.
:: Window hiding is handled internally by OpenlistGuard.ps1 via Add-Type + ShowWindow.
powershell -ExecutionPolicy Bypass -Command "& {$ws=New-Object -ComObject WScript.Shell; $lnk=$ws.CreateShortcut('%LNK%'); $lnk.TargetPath='powershell.exe'; $lnk.Arguments='-ExecutionPolicy Bypass -File ""%TARGET%""'; $lnk.WorkingDirectory='%WORKDIR%'; $lnk.Description='OpenList File Management Service (Guard)'; $lnk.Save()}"

if exist "%LNK%" (
    echo Startup shortcut created successfully!
    echo Shortcut added to: %STARTUP%
    echo OpenList will start automatically on next login.
) else (
    echo Failed to create shortcut.
)
pause
