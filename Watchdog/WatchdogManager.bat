@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
:: WatchdogManager.bat — OpenCpolarSync 看门狗统一管理入口
::
:: 用法:
::   交互菜单 : WatchdogManager.bat
::   命令行   : WatchdogManager.bat [setup|teardown|status] [Cpolar|Openlist|all]
::
:: setup    — 一键配置（开机自启 + Watchdog 运行时保活）
:: teardown — 一键移除（开机自启 + Watchdog 运行时保活）
:: status   — 查询计划任务和 Guard 进程状态
:: ============================================================

:: ----------------------------------------------------------
:: Paths — watchdog/ 位于仓库根目录下
:: ----------------------------------------------------------
for %%i in ("%~dp0.") do set "ROOT=%%~dpi"
set "CHECKER=%~dp0GuardCheck.ps1"
set "WD_LOG=%~dp0watchdog.log"
set "CPOLAR_GUARD=%ROOT%Cpolar\CpolarGuard.ps1"
set "OPENLIST_GUARD=%ROOT%Openlist\OpenlistGuard.ps1"
set "CPOLAR_AUTOSTART=%ROOT%Cpolar\AutoStart.bat"
set "OPENLIST_AUTOSTART=%ROOT%Openlist\AutoStart.bat"

:: ----------------------------------------------------------
:: Mutex names — must match those defined in the guard scripts
:: ----------------------------------------------------------
set "CPOLAR_MUTEX=Global\CpolarGuard-{B4C8D2E3-5F6A-7B8C-9D0E-1F2A3B4C5D6E}"
set "OPENLIST_MUTEX=Global\OpenlistGuard-{A3B7E1F2-4C5D-6E7F-8A9B-0C1D2E3F4A5B}"

:: ----------------------------------------------------------
:: Task Scheduler names
:: ----------------------------------------------------------
set "TASK_CPOLAR=OpenCpolarSync_CpolarGuard_Watchdog"
set "TASK_OPENLIST=OpenCpolarSync_OpenlistGuard_Watchdog"

:: ============================================================
:: Admin-rights check — elevate via UAC if not already admin
:: ============================================================
fltmc >nul 2>&1
if %errorlevel% neq 0 (
    echo [WatchdogManager] 请求管理员权限，请在弹出的 UAC 窗口中点击「是」...
    powershell -Command "Start-Process '%~f0' -Verb RunAs -ArgumentList '%~1 %~2'"
    exit /b
)

:: ============================================================
:: Command-line dispatch
:: ============================================================
if "%~1"=="" goto menu

if /i "%~1"=="status"    ( call :status & goto end )
if /i "%~1"=="setup"     ( call :setup %2 & goto end )
if /i "%~1"=="teardown"  ( call :teardown %2 & goto end )

echo 未知命令: %~1
echo 用法: %~nx0 [setup^|teardown^|status] [Cpolar^|Openlist^|all]
exit /b 1

:: ============================================================
:: Interactive menu (no arguments)
:: ============================================================
:menu
cls
echo ====================================
echo   OpenCpolarSync 看门狗管理
echo ====================================
echo   1. 一键配置全部（Cpolar + Openlist）
echo   2. 一键移除全部
echo   3. 仅配置 Cpolar（开机自启 + 保活）
echo   4. 仅移除 Cpolar
echo   5. 仅配置 Openlist（开机自启 + 保活）
echo   6. 仅移除 Openlist
echo   7. 查看状态
echo ====================================
choice /c 1234567 /n /m "请选择 (1-7): "

if errorlevel 7 ( call :status            & goto menu_end )
if errorlevel 6 ( call :teardown Openlist  & goto menu_end )
if errorlevel 5 ( call :setup Openlist     & goto menu_end )
if errorlevel 4 ( call :teardown Cpolar    & goto menu_end )
if errorlevel 3 ( call :setup Cpolar       & goto menu_end )
if errorlevel 2 ( call :teardown all       & goto menu_end )
if errorlevel 1 ( call :setup all          & goto menu_end )

:menu_end
echo.
pause
exit /b

:: ============================================================
:: :register_task — create a Task Scheduler recurring task
:: Parameters: %1=TaskName %2=GuardName %3=GuardScriptPath %4=MutexName
:: ============================================================
:register_task
echo   [*] 注册计划任务: %~1

powershell -ExecutionPolicy Bypass -Command "$a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument \"-ExecutionPolicy Bypass -WindowStyle Hidden -File `\"%~dp0GuardCheck.ps1`\" -GuardName %~2 -MutexName `\"%~4`\" -GuardScriptPath `\"%~3`\" -LogPath `\"%~dp0watchdog.log`\"\"; $p=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive; $t=New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes 5); $s=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10); Register-ScheduledTask -TaskName '%~1' -Action $a -Principal $p -Trigger $t -Settings $s -Force; Write-Host '    [OK] 已注册'"

if %errorlevel% neq 0 (
    echo   [FAIL] 注册失败，请以管理员身份运行
    exit /b 1
)
exit /b

:: ============================================================
:: :remove_task — delete a Task Scheduler task by name
:: ============================================================
:remove_task
echo   [*] 移除计划任务: %~1
schtasks /Delete /TN "%~1" /F >nul 2>&1
if %errorlevel% equ 0 (
    echo   [OK] 已移除
) else (
    echo   [OK] 任务不存在或已移除
)
exit /b

:: ============================================================
:: :status — show watchdog task and guard process status
:: ============================================================
:status
echo ====================================
echo   Watchdog 状态
echo ====================================
echo.

:: --- 计划任务状态 ---
echo [计划任务]
for %%T in ("%TASK_CPOLAR%" "%TASK_OPENLIST%") do (
    schtasks /Query /TN "%%~T" >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [*] %%~T  — 已注册
    ) else (
        echo   [ ] %%~T  — 未注册
    )
)

echo.

:: --- Guard 进程状态 ---
echo [Guard 进程]
powershell -ExecutionPolicy Bypass -Command ^
  "$cpolarAlive = $false; try { $m = New-Object System.Threading.Mutex($false, '%CPOLAR_MUTEX%', [ref]$cpolarAlive); if (-not $cpolarAlive) { Write-Host '  [*] CpolarGuard   — 运行中' } else { Write-Host '  [ ] CpolarGuard   — 未运行'; $m.Dispose() } } catch { Write-Host '  [?] CpolarGuard   — 无法检测' }"
powershell -ExecutionPolicy Bypass -Command ^
  "$openAlive = $false; try { $m = New-Object System.Threading.Mutex($false, '%OPENLIST_MUTEX%', [ref]$openAlive); if (-not $openAlive) { Write-Host '  [*] OpenlistGuard — 运行中' } else { Write-Host '  [ ] OpenlistGuard — 未运行'; $m.Dispose() } } catch { Write-Host '  [?] OpenlistGuard — 无法检测' }"

echo.

:: --- 最近恢复记录 ---
echo [恢复日志] (%WD_LOG%)
if exist "%WD_LOG%" (
    powershell -Command "Get-Content '%WD_LOG%' -Tail 5"
) else (
    echo   （暂无恢复记录）
)
echo.
exit /b

:: ============================================================
:: :setup — one-click: auto-start + watchdog
:: ============================================================
:setup
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=all"

if /i "%TARGET%"=="Cpolar" (
    echo === 一键配置 Cpolar（开机自启 + Watchdog） ===
    if exist "%CPOLAR_AUTOSTART%" (
        echo [1/2] 添加 Cpolar 开机自启...
        call "%CPOLAR_AUTOSTART%" add
    ) else (
        echo [WARN] Cpolar\AutoStart.bat 未找到，跳过开机自启
    )
    echo [2/2] 注册 Cpolar Watchdog...
    call :register_task "%TASK_CPOLAR%" Cpolar "%CPOLAR_GUARD%" "%CPOLAR_MUTEX%"
    if errorlevel 1 (
        echo   [FAIL] Watchdog 注册失败，请以管理员身份运行
        pause
        exit /b 1
    )
    echo 完成：Cpolar 已配置开机自启 + 运行时保活
    exit /b
)
if /i "%TARGET%"=="Openlist" (
    echo === 一键配置 Openlist（开机自启 + Watchdog） ===
    if exist "%OPENLIST_AUTOSTART%" (
        echo [1/2] 添加 Openlist 开机自启...
        call "%OPENLIST_AUTOSTART%" add
    ) else (
        echo [WARN] Openlist\AutoStart.bat 未找到，跳过开机自启
    )
    echo [2/2] 注册 Openlist Watchdog...
    call :register_task "%TASK_OPENLIST%" Openlist "%OPENLIST_GUARD%" "%OPENLIST_MUTEX%"
    if errorlevel 1 (
        echo   [FAIL] Watchdog 注册失败，请以管理员身份运行
        pause
        exit /b 1
    )
    echo 完成：Openlist 已配置开机自启 + 运行时保活
    exit /b
)
if /i "%TARGET%"=="all" (
    echo === 一键配置全部（开机自启 + Watchdog） ===
    if exist "%CPOLAR_AUTOSTART%" (
        echo [1/4] 添加 Cpolar 开机自启...
        call "%CPOLAR_AUTOSTART%" add
    )
    if exist "%OPENLIST_AUTOSTART%" (
        echo [2/4] 添加 Openlist 开机自启...
        call "%OPENLIST_AUTOSTART%" add
    )
    echo [3/4] 注册 Cpolar Watchdog...
    call :register_task "%TASK_CPOLAR%" Cpolar "%CPOLAR_GUARD%" "%CPOLAR_MUTEX%"
    if errorlevel 1 (
        echo   [FAIL] Cpolar Watchdog 注册失败，已终止
        pause
        exit /b 1
    )
    echo [4/4] 注册 Openlist Watchdog...
    call :register_task "%TASK_OPENLIST%" Openlist "%OPENLIST_GUARD%" "%OPENLIST_MUTEX%"
    if errorlevel 1 (
        echo   [FAIL] Openlist Watchdog 注册失败，已终止
        pause
        exit /b 1
    )
    echo.
    echo 完成：Cpolar + Openlist 已配置【开机自启 + 运行时保活】双重保障
    exit /b
)

echo 无效目标: %TARGET%  ^(应为 Cpolar / Openlist / all^)
exit /b 1

:: ============================================================
:: :teardown — one-click: remove auto-start + watchdog
:: ============================================================
:teardown
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=all"

if /i "%TARGET%"=="Cpolar" (
    echo === 一键移除 Cpolar（开机自启 + Watchdog） ===
    if exist "%CPOLAR_AUTOSTART%" (
        echo [1/2] 移除 Cpolar 开机自启...
        call "%CPOLAR_AUTOSTART%" remove
    ) else (
        echo [WARN] Cpolar\AutoStart.bat 未找到，跳过开机自启
    )
    echo [2/2] 移除 Cpolar Watchdog...
    call :remove_task "%TASK_CPOLAR%"
    echo 完成：Cpolar 开机自启和运行时保活已移除
    exit /b
)
if /i "%TARGET%"=="Openlist" (
    echo === 一键移除 Openlist（开机自启 + Watchdog） ===
    if exist "%OPENLIST_AUTOSTART%" (
        echo [1/2] 移除 Openlist 开机自启...
        call "%OPENLIST_AUTOSTART%" remove
    ) else (
        echo [WARN] Openlist\AutoStart.bat 未找到，跳过开机自启
    )
    echo [2/2] 移除 Openlist Watchdog...
    call :remove_task "%TASK_OPENLIST%"
    echo 完成：Openlist 开机自启和运行时保活已移除
    exit /b
)
if /i "%TARGET%"=="all" (
    echo === 一键移除全部（开机自启 + Watchdog） ===
    if exist "%CPOLAR_AUTOSTART%" (
        echo [1/4] 移除 Cpolar 开机自启...
        call "%CPOLAR_AUTOSTART%" remove
    )
    if exist "%OPENLIST_AUTOSTART%" (
        echo [2/4] 移除 Openlist 开机自启...
        call "%OPENLIST_AUTOSTART%" remove
    )
    echo [3/4] 移除 Cpolar Watchdog...
    call :remove_task "%TASK_CPOLAR%"
    echo [4/4] 移除 Openlist Watchdog...
    call :remove_task "%TASK_OPENLIST%"
    echo.
    echo 完成：所有开机自启和运行时保活已移除
    exit /b
)

echo 无效目标: %TARGET%  ^(应为 Cpolar / Openlist / all^)
exit /b 1

:: ============================================================
:end
exit /b 0
