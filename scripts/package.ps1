#Requires -Version 5.1
<#
.SYNOPSIS
    OpenCpolarSync 安装包打包脚本
.DESCRIPTION
    先检查打包环境（Inno Setup、Release 编译输出、cpolar MSI、openlist.zip），
    再调用 ISCC.exe 编译 setup.iss 生成安装程序。
.NOTES
    用法：.\package.ps1
    前提：需先运行 .\build-release.ps1 完成 Release 编译
#>

$ErrorActionPreference = "Stop"

# 解析项目根目录：优先用脚本所在目录的父目录，失败则回退到当前工作目录
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectRoot "src\OpenCpolarSync.Client.sln"))) {
    $ProjectRoot = (Get-Location).Path
}
$InstallerDir = Join-Path $ProjectRoot "installer"
$SetupScript = Join-Path $InstallerDir "setup.iss"
$OutputDir = Join-Path $InstallerDir "Output"
$Version = "1.1.22"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenCpolarSync - 安装包打包" -ForegroundColor Cyan
Write-Host "  版本：$Version" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. 环境检查
# ============================================================
Write-Host "[1/2] 环境检查..." -ForegroundColor Yellow

# 1.1 查找 Inno Setup (ISCC.exe)
# 优先检测常见安装路径（支持 5/6/7 版本）
$ISCCPaths = @(
    "C:\Program Files\Inno Setup 7\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 5\ISCC.exe",
    "C:\Program Files\Inno Setup 5\ISCC.exe"
)

$ISCCPath = $null
foreach ($path in $ISCCPaths) {
    if (Test-Path $path) {
        $ISCCPath = $path
        break
    }
}

# 从注册表卸载项动态查找（不硬编码版本号）
if (-not $ISCCPath) {
    try {
        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        foreach ($keyRoot in $uninstallKeys) {
            if (-not (Test-Path $keyRoot)) { continue }
            $innoEntries = Get-ChildItem $keyRoot -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -like "Inno Setup*" }
            foreach ($entry in $innoEntries) {
                $installLoc = (Get-ItemProperty $entry.PSPath -ErrorAction SilentlyContinue).InstallLocation
                if ($installLoc) {
                    $candidate = Join-Path $installLoc "ISCC.exe"
                    if (Test-Path $candidate) {
                        $ISCCPath = $candidate
                        break
                    }
                }
            }
            if ($ISCCPath) { break }
        }
    } catch { }
}

# 最后尝试 PATH 环境变量
if (-not $ISCCPath) {
    $cmd = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $ISCCPath = $cmd.Source }
}

if (-not $ISCCPath) {
    Write-Host "  [错误] 未找到 Inno Setup (ISCC.exe)" -ForegroundColor Red
    Write-Host "         请安装 Inno Setup 6.x 或 7.x" -ForegroundColor Red
    Write-Host "         下载地址：https://jrsoftware.org/isdl.php" -ForegroundColor DarkGray
    exit 1
}
Write-Host "  [OK] Inno Setup: $ISCCPath" -ForegroundColor Green

# 1.2 检查 setup.iss
if (-not (Test-Path $SetupScript)) {
    Write-Host "  [错误] 安装脚本不存在：$SetupScript" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] 安装脚本存在" -ForegroundColor Green

# 1.3 检查 Release 编译输出
$ReleaseDir = Join-Path $ProjectRoot "src\OpenCpolarSync.Client\bin\Release"
$ReleaseExe = Join-Path $ReleaseDir "OpenCpolarSync.exe"
if (-not (Test-Path $ReleaseExe)) {
    Write-Host "  [错误] 未找到 Release 编译输出：$ReleaseExe" -ForegroundColor Red
    Write-Host "         请先运行 .\build-release.ps1 完成编译" -ForegroundColor Red
    exit 1
}
$ExeInfo = Get-Item $ReleaseExe
Write-Host "  [OK] Release 编译输出存在 ($([math]::Round($ExeInfo.Length / 1KB, 1)) KB)" -ForegroundColor Green

# 1.4 检查 cpolar 安装包
$CpolarMsi = Join-Path $ProjectRoot "legacy\Cpolar\installer\cpolar_amd64.msi"
if (-not (Test-Path $CpolarMsi)) {
    Write-Host "  [警告] 未找到 cpolar 安装包：$CpolarMsi" -ForegroundColor Yellow
    Write-Host "         安装包将不包含 cpolar 自动安装功能" -ForegroundColor DarkYellow
} else {
    $MsiInfo = Get-Item $CpolarMsi
    Write-Host "  [OK] cpolar 安装包存在 ($([math]::Round($MsiInfo.Length / 1MB, 2)) MB)" -ForegroundColor Green
}

# 1.5 检查 openlist 压缩包
$OpenlistZip = Join-Path $ProjectRoot "legacy\Openlist\archive\openlist.zip"
if (-not (Test-Path $OpenlistZip)) {
    Write-Host "  [警告] 未找到 openlist 压缩包：$OpenlistZip" -ForegroundColor Yellow
    Write-Host "         安装包将不包含 openlist 自动部署功能" -ForegroundColor DarkYellow
} else {
    $ZipInfo = Get-Item $OpenlistZip
    Write-Host "  [OK] openlist 压缩包存在 ($([math]::Round($ZipInfo.Length / 1MB, 2)) MB)" -ForegroundColor Green
}

Write-Host ""

# ============================================================
# 2. 打包
# ============================================================
Write-Host "[2/2] 编译安装程序..." -ForegroundColor Yellow

# 创建输出目录
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# 执行 ISCC 编译
Push-Location $InstallerDir
try {
    # ISCC 会将警告输出到 stderr，临时放宽错误策略避免警告被当成终止错误
    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $ISCCOutput = & $ISCCPath $SetupScript 2>&1
    $ISCCExitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevErrorAction
} finally {
    Pop-Location
}

if ($ISCCExitCode -ne 0) {
    Write-Host "  [错误] 安装程序编译失败" -ForegroundColor Red
    Write-Host ""
    Write-Host "--- ISCC 输出 ---" -ForegroundColor Red
    Write-Host $ISCCOutput -ForegroundColor DarkRed
    exit 1
}

Write-Host "  [OK] 安装程序编译完成" -ForegroundColor Green
Write-Host ""

# ============================================================
# 输出结果
# ============================================================
$ExpectedInstaller = Join-Path $OutputDir "OpenCpolarSync-Setup_$Version.exe"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  打包完成" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (Test-Path $ExpectedInstaller) {
    $InstallerInfo = Get-Item $ExpectedInstaller
    Write-Host "  安装包：$($InstallerInfo.Name)" -ForegroundColor White
    Write-Host "  路径：$($InstallerInfo.FullName)" -ForegroundColor White
    Write-Host "  大小：$([math]::Round($InstallerInfo.Length / 1MB, 2)) MB" -ForegroundColor White
    Write-Host "  生成时间：$($InstallerInfo.LastWriteTime)" -ForegroundColor White
} else {
    # 列出输出目录中的文件
    Write-Host "  输出目录：$OutputDir" -ForegroundColor White
    Get-ChildItem $OutputDir -Filter "*.exe" | ForEach-Object {
        Write-Host "    $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)" -ForegroundColor White
    }
}
Write-Host ""
Write-Host "按回车键退出..." -ForegroundColor DarkGray
Read-Host | Out-Null
