#Requires -Version 5.1
<#
.SYNOPSIS
    OpenCpolarSync Release 编译脚本
.DESCRIPTION
    先检查编译环境（MSBuild、.NET Framework 4.8 Targeting Pack），
    清理后执行 NuGet 还原和 Release 编译。
.NOTES
    用法：.\build-release.ps1
#>

$ErrorActionPreference = "Stop"
# 解析项目根目录：优先用脚本所在目录的父目录，失败则回退到当前工作目录
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectRoot "src\OpenCpolarSync.Client.sln"))) {
    $ProjectRoot = (Get-Location).Path
}
$SolutionPath = Join-Path $ProjectRoot "src\OpenCpolarSync.Client.sln"
$Configuration = "Release"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenCpolarSync - Release 编译" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. 环境检查
# ============================================================
Write-Host "[1/4] 环境检查..." -ForegroundColor Yellow

# 1.1 查找 MSBuild
$MSBuildPaths = @(
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe"
)

$MSBuildPath = $null
foreach ($path in $MSBuildPaths) {
    if (Test-Path $path) {
        $MSBuildPath = $path
        break
    }
}

# 尝试通过 vswhere 查找
if (-not $MSBuildPath) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" 2>$null
        if ($vsPath -and (Test-Path $vsPath)) {
            $MSBuildPath = $vsPath
        }
    }
}

if (-not $MSBuildPath) {
    Write-Host "  [错误] 未找到 MSBuild.exe，请安装 Visual Studio 2019/2022" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] MSBuild: $MSBuildPath" -ForegroundColor Green

# 1.2 检查 .NET Framework 4.8 Targeting Pack
$NetFx48Path = "C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"
if (-not (Test-Path $NetFx48Path)) {
    Write-Host "  [警告] 未找到 .NET Framework 4.8 Targeting Pack，编译可能失败" -ForegroundColor Yellow
    Write-Host "         下载地址：https://dotnet.microsoft.com/download/dotnet-framework/net48" -ForegroundColor DarkGray
} else {
    Write-Host "  [OK] .NET Framework 4.8 Targeting Pack" -ForegroundColor Green
}

# 1.3 检查解决方案文件
if (-not (Test-Path $SolutionPath)) {
    Write-Host "  [错误] 解决方案文件不存在：$SolutionPath" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] 解决方案文件存在" -ForegroundColor Green

Write-Host ""

# ============================================================
# 2. 清理
# ============================================================
Write-Host "[2/4] 清理旧的编译输出..." -ForegroundColor Yellow
$CleanOutput = & $MSBuildPath $SolutionPath /t:Clean /p:Configuration=$Configuration /v:minimal 2>&1
Write-Host "  [OK] 清理完成" -ForegroundColor Green
Write-Host ""

# ============================================================
# 3. NuGet 还原
# ============================================================
Write-Host "[3/4] NuGet 还原..." -ForegroundColor Yellow
$RestoreOutput = & $MSBuildPath $SolutionPath /t:Restore /p:Configuration=$Configuration /v:minimal 2>&1
$RestoreExitCode = $LASTEXITCODE

if ($RestoreExitCode -ne 0) {
    Write-Host "  [错误] NuGet 还原失败" -ForegroundColor Red
    Write-Host $RestoreOutput -ForegroundColor DarkRed
    exit 1
}
Write-Host "  [OK] NuGet 还原完成" -ForegroundColor Green
Write-Host ""

# ============================================================
# 4. 编译
# ============================================================
Write-Host "[4/4] 编译 ($Configuration)..." -ForegroundColor Yellow
$BuildOutput = & $MSBuildPath $SolutionPath /t:Build /p:Configuration=$Configuration /v:minimal 2>&1
$BuildExitCode = $LASTEXITCODE

$Warnings = $BuildOutput | Select-String -Pattern "warning" -CaseSensitive:$false
$Errors = $BuildOutput | Select-String -Pattern "error" -CaseSensitive:$false

if ($BuildExitCode -ne 0) {
    Write-Host "  [错误] 编译失败" -ForegroundColor Red
    Write-Host ""
    Write-Host "--- 错误详情 ---" -ForegroundColor Red
    Write-Host $Errors -ForegroundColor Red
    if ($Warnings) {
        Write-Host ""
        Write-Host "--- 警告 ---" -ForegroundColor Yellow
        Write-Host $Warnings -ForegroundColor Yellow
    }
    exit 1
}

Write-Host "  [OK] 编译成功" -ForegroundColor Green

if ($Warnings) {
    Write-Host ""
    Write-Host "  警告 ($($Warnings.Count))：" -ForegroundColor Yellow
    $Warnings | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
}

# 输出结果
$OutputDir = Join-Path $ProjectRoot "src\OpenCpolarSync.Client\bin\$Configuration"
$ExePath = Join-Path $OutputDir "OpenCpolarSync.exe"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  编译完成" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  配置：$Configuration" -ForegroundColor White
Write-Host "  输出目录：$OutputDir" -ForegroundColor White
if (Test-Path $ExePath) {
    $ExeInfo = Get-Item $ExePath
    Write-Host "  主程序：$($ExeInfo.Name) ($([math]::Round($ExeInfo.Length / 1KB, 1)) KB)" -ForegroundColor White
    Write-Host "  编译时间：$($ExeInfo.LastWriteTime)" -ForegroundColor White
}
Write-Host ""
Write-Host "  下一步：运行 .\package.ps1 打包安装程序" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "按回车键退出..." -ForegroundColor DarkGray
Read-Host | Out-Null
