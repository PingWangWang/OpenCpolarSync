<#
.SYNOPSIS
    OpenCpolarSync 一键编译 Release + 打包 + 版本号自增
.DESCRIPTION
    1. 环境检查（MSBuild、ISCC、.NET Framework 4.8）
    2. 读取当前版本号并自动 +1（最后一位加，加到99进位）
    3. 更新所有版本号文件（AssemblyInfo、setup.iss、package.ps1、MainWindow.xaml、README.md）
    4. 编译 Release 版本
    5. 打包安装包
.NOTES
    用法：.\build-and-package.ps1
    版本号规则：最后一位 +1，加到 99 后向前进一位，依次类推
#>

$ErrorActionPreference = "Stop"

# ============================================================
# 路径配置
# ============================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$SrcDir = Join-Path $ProjectRoot "src"
$SlnPath = Join-Path $SrcDir "OpenCpolarSync.Client.sln"
$InstallerDir = Join-Path $ProjectRoot "installer"
$SetupIssPath = Join-Path $InstallerDir "setup.iss"
$PackageScriptPath = Join-Path $ScriptDir "package.ps1"
$AssemblyInfoPath = Join-Path $SrcDir "OpenCpolarSync.Client\Properties\AssemblyInfo.cs"
$MainWindowXamlPath = Join-Path $SrcDir "OpenCpolarSync.Client\MainWindow.xaml"
$ReadmePath = Join-Path $ProjectRoot "README.md"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenCpolarSync - 一键编译 + 打包 + 版本自增" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 步骤 1：环境检查
# ============================================================
Write-Host "[1/5] 环境检查..." -ForegroundColor Yellow

# 检查 MSBuild
$MSBuildPath = & "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe" -version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    # 尝试通过 vswhere 查找
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $MSBuildPath = & $vswhere -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
    }
}
if (-not $MSBuildPath) {
    $MSBuildPath = "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe"
}
if (-not (Test-Path $MSBuildPath)) {
    Write-Host "  [错误] 未找到 MSBuild.exe" -ForegroundColor Red
    Write-Host "         请安装 Visual Studio 2022 或 Build Tools" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}
Write-Host "  [OK] MSBuild: $MSBuildPath" -ForegroundColor Green

# 检查 ISCC
$ISCCPath = $null
$isccCandidates = @(
    "C:\Program Files\Inno Setup 7\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 5\ISCC.exe"
)
foreach ($candidate in $isccCandidates) {
    if (Test-Path $candidate) { $ISCCPath = $candidate; break }
}
if (-not $ISCCPath) {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    $isccReg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Inno Setup*" } | Select-Object -First 1
    if ($isccReg -and $isccReg.InstallLocation) {
        $candidate = Join-Path $isccReg.InstallLocation "ISCC.exe"
        if (Test-Path $candidate) { $ISCCPath = $candidate }
    }
}
if (-not $ISCCPath) {
    Write-Host "  [错误] 未找到 Inno Setup (ISCC.exe)" -ForegroundColor Red
    Write-Host "         请安装 Inno Setup 6.x / 7.x" -ForegroundColor Red
    Write-Host "         下载地址：https://jrsoftware.org/isdl.php" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}
Write-Host "  [OK] Inno Setup: $ISCCPath" -ForegroundColor Green

# 检查解决方案文件
if (-not (Test-Path $SlnPath)) {
    Write-Host "  [错误] 解决方案文件不存在: $SlnPath" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}
Write-Host "  [OK] 解决方案文件存在" -ForegroundColor Green

# 检查 setup.iss
if (-not (Test-Path $SetupIssPath)) {
    Write-Host "  [错误] 安装脚本不存在: $SetupIssPath" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}
Write-Host "  [OK] 安装脚本存在" -ForegroundColor Green

Write-Host ""

# ============================================================
# 步骤 2：读取并递增版本号
# ============================================================
Write-Host "[2/5] 版本号自增..." -ForegroundColor Yellow

# 从 setup.iss 读取当前版本号（作为权威来源）
$issContent = Get-Content $SetupIssPath -Raw -Encoding UTF8
if ($issContent -match '#define MyAppVersion "([\d]+\.[\d]+\.[\d]+)"') {
    $currentVersion = $Matches[1]
} else {
    Write-Host "  [错误] 无法从 setup.iss 读取版本号" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

Write-Host "  当前版本: $currentVersion" -ForegroundColor White

# 解析版本号为数组 [major, minor, build]
$versionParts = $currentVersion -split '\.' | ForEach-Object { [int]$_ }
$major = $versionParts[0]
$minor = $versionParts[1]
$build = $versionParts[2]

# 递增：最后一位 +1，加到99进位
$build++
if ($build -gt 99) {
    $build = 0
    $minor++
    if ($minor -gt 99) {
        $minor = 0
        $major++
    }
}

$newVersion = "$major.$minor.$build"
$newVersion4 = "$major.$minor.$build.0"

Write-Host "  新版本:   $newVersion" -ForegroundColor Green
Write-Host ""

# ============================================================
# 步骤 3：更新所有版本号文件
# ============================================================
Write-Host "[3/5] 更新版本号文件..." -ForegroundColor Yellow

# 3a. 更新 setup.iss
$issContent = $issContent -replace '#define MyAppVersion "[\d]+\.[\d]+\.[\d]+"', "#define MyAppVersion `"$newVersion`""
Set-Content -Path $SetupIssPath -Value $issContent -Encoding UTF8 -NoNewline
Write-Host "  [OK] setup.iss" -ForegroundColor Green

# 3b. 更新 AssemblyInfo.cs
$asmContent = Get-Content $AssemblyInfoPath -Raw -Encoding UTF8
$asmContent = $asmContent -replace 'AssemblyVersion\("[\d]+\.[\d]+\.[\d]+\.[\d]+"\)', "AssemblyVersion(`"$newVersion4`")"
$asmContent = $asmContent -replace 'AssemblyFileVersion\("[\d]+\.[\d]+\.[\d]+\.[\d]+"\)', "AssemblyFileVersion(`"$newVersion4`")"
Set-Content -Path $AssemblyInfoPath -Value $asmContent -Encoding UTF8 -NoNewline
Write-Host "  [OK] AssemblyInfo.cs" -ForegroundColor Green

# 3c. 更新 package.ps1
$pkgContent = Get-Content $PackageScriptPath -Raw -Encoding UTF8
$pkgContent = $pkgContent -replace '\$Version = "[\d]+\.[\d]+\.[\d]+"', "`$Version = `"$newVersion`""
Set-Content -Path $PackageScriptPath -Value $pkgContent -Encoding UTF8 -NoNewline
Write-Host "  [OK] package.ps1" -ForegroundColor Green

# 3d. 更新 MainWindow.xaml
$mwContent = Get-Content $MainWindowXamlPath -Raw -Encoding UTF8
$mwContent = $mwContent -replace 'Text="v[\d]+\.[\d]+\.[\d]+"', "Text=`"v$newVersion`""
Set-Content -Path $MainWindowXamlPath -Value $mwContent -Encoding UTF8 -NoNewline
Write-Host "  [OK] MainWindow.xaml" -ForegroundColor Green

# 3e. 更新 README.md
$readmeContent = Get-Content $ReadmePath -Raw -Encoding UTF8
$readmeContent = $readmeContent -replace 'version-[\d]+\.[\d]+\.[\d]+', "version-$newVersion"
$readmeContent = $readmeContent -replace 'OpenCpolarSync-Setup_[\d]+\.[\d]+\.[\d]+\.exe', "OpenCpolarSync-Setup_$newVersion.exe"
Set-Content -Path $ReadmePath -Value $readmeContent -Encoding UTF8 -NoNewline
Write-Host "  [OK] README.md" -ForegroundColor Green

Write-Host ""

# ============================================================
# 步骤 4：编译 Release 版本
# ============================================================
Write-Host "[4/5] 编译 Release 版本..." -ForegroundColor Yellow

Set-Location $SrcDir

# NuGet 还原
Write-Host "  还原 NuGet 包..." -ForegroundColor Gray
& $MSBuildPath $SlnPath /t:Restore /v:minimal 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [警告] NuGet 还原失败，尝试继续编译..." -ForegroundColor Yellow
}

# 清理
Write-Host "  清理旧编译输出..." -ForegroundColor Gray
& $MSBuildPath $SlnPath /t:Clean /p:Configuration=Release /v:minimal 2>&1 | Out-Null

# 编译
Write-Host "  编译中..." -ForegroundColor Gray
$buildOutput = & $MSBuildPath $SlnPath /t:Build /p:Configuration=Release /v:minimal 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [错误] 编译失败！" -ForegroundColor Red
    Write-Host $buildOutput -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

# 获取 exe 大小
$exePath = Join-Path $SrcDir "OpenCpolarSync.Client\bin\Release\OpenCpolarSync.exe"
$exeSize = (Get-Item $exePath).Length / 1KB
Write-Host "  [OK] 编译成功" -ForegroundColor Green
Write-Host "       主程序: OpenCpolarSync.exe ($([math]::Round($exeSize, 1)) KB)" -ForegroundColor Gray

Write-Host ""

# ============================================================
# 步骤 5：打包安装包
# ============================================================
Write-Host "[5/5] 打包安装包..." -ForegroundColor Yellow

Set-Location $InstallerDir

# 临时设置 ErrorActionPreference 为 Continue，避免 ISCC 的 stderr 警告被当成终止错误
$ErrorActionPreference = "Continue"
$isccOutput = & $ISCCPath $SetupIssPath 2>&1
$ErrorActionPreference = "Stop"

if ($LASTEXITCODE -ne 0) {
    Write-Host "  [错误] 打包失败！" -ForegroundColor Red
    Write-Host $isccOutput -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

# 获取安装包路径和大小
$setupExe = Join-Path $InstallerDir "Output\OpenCpolarSync-Setup_$newVersion.exe"
if (Test-Path $setupExe) {
    $setupSize = (Get-Item $setupExe).Length / 1MB
    Write-Host "  [OK] 打包成功" -ForegroundColor Green
    Write-Host "       安装包: OpenCpolarSync-Setup_$newVersion.exe ($([math]::Round($setupSize, 2)) MB)" -ForegroundColor Gray
    Write-Host "       路径: $setupExe" -ForegroundColor Gray
} else {
    Write-Host "  [警告] 未找到生成的安装包，请检查 Output 目录" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  全部完成" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  版本：$currentVersion → $newVersion" -ForegroundColor White
Write-Host "  编译：Release" -ForegroundColor White
Write-Host "  安装包：OpenCpolarSync-Setup_$newVersion.exe" -ForegroundColor White
Write-Host "  编译时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""

Read-Host "按回车键退出"
