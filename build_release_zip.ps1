param(
    [string]$Tag = "v1.1.16",
    [string]$OutDir = $env:TEMP
)

# 生成可发布的仓库快照包，供 Gitee Release 作为资产上传（项目主源为 Gitee）。
#
# 为什么用 git archive 而不是手工 Copy-Item 清单：
#   1) Gitee 对匿名用户不开放「源码归档」下载——/repository/archive/<branch>.zip 对
#      未登录请求会返回登录页 HTML（不是 zip），因此发布包必须作为 Release 资产上传，
#      再由 CDN 匿名分发。这也意味着发布包必须自包含、下载即用。
#   2) 发布包必须是完整可用的仓库快照：缺任一 Guard / 脚本都会让部署中途失败。
#      用 git archive 打包 HEAD 下的全部受版本控制文件，天然排除 .git 与本地未跟踪
#      文件（如 Cpolar/config/config.json——它由 setup.ps1 现场生成，不应入库）。
#   3) 压缩包内含一层 OpenCpolarSync-<Tag>/ 前缀目录，与 bootstrap-core.ps1 解压后的
#      「提层」逻辑（匹配 *OpenCpolarSync* 的目录）保持一致。
#
# 用法：.\build_release_zip.ps1 -Tag v1.1.16
# 产物：%TEMP%\OpenCpolarSync_<Tag>.zip

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$zip  = Join-Path $OutDir ("OpenCpolarSync_" + $Tag + ".zip")
if (Test-Path $zip) { Remove-Item $zip -Force }

$prefix = "OpenCpolarSync-$Tag/"
Push-Location $root
try {
    # HEAD 即当前分支最新提交；发布前请确认已提交待发布内容。
    git archive --format=zip --prefix=$prefix -o "$zip" HEAD
    if ($LASTEXITCODE -ne 0) { throw "git archive 执行失败（exit code $LASTEXITCODE）" }
} finally {
    Pop-Location
}

if (-not (Test-Path $zip)) { throw "未生成发布包：$zip" }

# 魔数校验：合法 ZIP 以 PK（0x50 0x4B）开头，防止错误页/空文件被当成成功产物。
$fs = [System.IO.File]::OpenRead($zip)
try {
    $buf = New-Object byte[] 2
    if ($fs.Read($buf, 0, 2) -ne 2) { throw "发布包读取失败：$zip" }
} finally {
    $fs.Close()
}
if (-not ($buf[0] -eq 0x50 -and $buf[1] -eq 0x4B)) { throw "发布包不是有效的 ZIP 压缩包：$zip" }

$len = (Get-Item $zip).Length
Write-Output "发布包: $zip  $([math]::Round($len / 1MB, 2))MB"
