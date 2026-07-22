@echo off
cd /d "%~dp0"

:: ============================================================
:: 检测管理员权限 — 非管理员则通过 UAC 提权重启
:: ============================================================
fltmc >nul 2>&1
if %errorlevel% neq 0 (
    echo 请求管理员权限，请在弹出的 UAC 窗口中点击「是」...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: ============================================================
:: 菜单选择
:: ============================================================
cls
echo ====================================
echo    Cpolar 隧道监控 - 开机自启管理
echo ====================================
echo    1. 添加开机自启
echo    2. 删除开机自启
echo ====================================
choice /c 12 /n /m "请选择 (1/2): "
if errorlevel 2 goto remove_autostart
if errorlevel 1 goto add_autostart

:: ============================================================
:: 添加开机自启 — 创建快捷方式到 shell:startup
:: ============================================================
:add_autostart

:: 验证 CpolarGuard.ps1 存在
if not exist "CpolarGuard.ps1" (
    echo 错误：CpolarGuard.ps1 未找到。
    echo 请从 Cpolar 目录运行此脚本。
    pause
    exit /b 1
)

:: 获取当前用户启动文件夹路径
for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v Startup 2^>nul') do set "STARTUP=%%b"
if "%STARTUP%"=="" (
    echo 错误：无法获取启动文件夹路径。
    pause
    exit /b 1
)

set "LNK=%STARTUP%\CpolarGuard.lnk"
set "TARGET=%~dp0CpolarGuard.ps1"
set "WORKDIR=%~dp0"

:: 通过 PowerShell ComObject 创建快捷方式
:: 窗口隐藏由 CpolarGuard.ps1 内部自处理，避免 AV 检测
powershell -ExecutionPolicy Bypass -Command "& {$ws=New-Object -ComObject WScript.Shell; $lnk=$ws.CreateShortcut('%LNK%'); $lnk.TargetPath='powershell.exe'; $lnk.Arguments='-ExecutionPolicy Bypass -File ""%TARGET%""'; $lnk.WorkingDirectory='%WORKDIR%'; $lnk.Description='Cpolar Tunnel Status Monitor (Guard)'; $lnk.Save()}"

if exist "%LNK%" (
    echo.
    echo 开机自启已添加！
    echo CpolarGuard 将在下次登录时自动启动。
    echo 快捷方式：%LNK%
) else (
    echo 错误：创建快捷方式失败。
)
pause
exit /b

:: ============================================================
:: 删除开机自启 — 从 shell:startup 移除快捷方式
:: ============================================================
:remove_autostart

:: 获取当前用户启动文件夹路径
for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v Startup 2^>nul') do set "STARTUP=%%b"
if "%STARTUP%"=="" (
    echo 错误：无法获取启动文件夹路径。
    pause
    exit /b 1
)

set "LNK=%STARTUP%\CpolarGuard.lnk"

if not exist "%LNK%" (
    echo 开机自启未设置，无需删除。
    pause
    exit /b 0
)

del /f /q "%LNK%" >nul 2>&1

if exist "%LNK%" (
    echo 错误：删除快捷方式失败，请手动检查：%LNK%
) else (
    echo.
    echo 开机自启已删除！
    echo CpolarGuard 将不再随系统启动。
)
pause
exit /b
