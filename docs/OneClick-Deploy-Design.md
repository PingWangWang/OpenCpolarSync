# OpenCpolarSync 一键部署方案设计

> 记录日期：2026-09-09
> 目标：把原本 5~6 步的手工部署流程收敛为一条命令
> 状态：已实现并自测通过（28 项检查全部 PASS）

---

## 1. 背景与问题

### 1.1 当前用户需要执行的步骤

```
1. clone 仓库
2. 手动安装 Cpolar/installer/cpolar_amd64.msi
3. 手动修改 Cpolar/config/config.json
4. 执行 Watchdog/GuardCheck.ps1 并启用所有监控
5. 在 Openlist 与 Cpolar 的 Web 端分别配置文件挂载和内网穿透
```

### 1.2 痛点归因

| 步骤 | Root cause |
|------|-----------|
| 1 clone | 没有一键分发入口，强依赖 git 环境 |
| 2 装 msi | 没有安装检测与静默安装逻辑 |
| 3 改 config.json | `CpolarGuard.ps1` **无 param 块**，配置路径硬编码为 `$scriptDir/config/config.json`；手工填 4 项易格式错；配置存于仓库目录，升级易冲突 |
| 4 启用监控 | 入口语义混淆（见 1.3），且需为 Cpolar / Openlist 分别 setup |
| 5 web 配置 | 未利用 cpolar 自身的 `-config` / `authtoken` 能力 |
| 6（隐含） | `openlist.exe` 不入库，需手工从 `archive/openlist.zip` 解压（README 明确写「手动放置」） |

### 1.3 两处认知纠正

- **`GuardCheck.ps1` 不是用户入口**。它是被 Windows 计划任务调用的巡检脚本，需要 4 个强制参数，靠 Mutex 判活后拉起 guard。真正的用户入口是 `WatchdogManager.bat setup all`。
- **实际有 6 步而非 5 步**，第 6 步（解压 openlist.exe）在 README 中以「手动放置」形式存在，容易被忽略。

### 1.4 关键可行性发现

`Cpolar/archive/cpolar_help.txt` 证实 cpolar 支持以下参数：

```
-config string      配置文件路径（默认 $HOME/.cpolar/cpolar.yml）
-authtoken string   账号认证 token
-daemon string      后台进程模式
-tunnelName string  隧道名
-proto string       协议 http/https/tcp
-region string      区域
```

**结论：第 5 步的「内网穿透」部分可以自动化**——通过写入 `cpolar.yml` 定义隧道，无需在 Web 端手工创建。

---

## 2. 参考范式分析：Win11Debloat Script CN.ps1

| 做法 | 说明 | 借鉴点 |
|------|------|--------|
| `param` 开关化 | 近百个 `[switch]` / `[string]` 参数 | 支持静默与无人值守 |
| 自动获取最新版 | 调 GitHub API 取 release zipball | 免 clone |
| 解压到临时目录 | `%TEMP%\Win11Debloat` | 与仓库解耦 |
| **配置目录保护** | 清理时排除 `Config/Logs/Backups` | **升级不丢配置** |
| 参数透传 | 重建参数列表传给主脚本 | 入口与逻辑分离 |
| 自动提权 | `-Verb RunAs` + `-executionpolicy bypass` | 免手工右键 |
| 中文进度与错误处理 | 分步提示 + 失败可读 | 体验友好 |

核心范式：**零克隆 + 配置与程序分离**。

---

## 3. 方案设计

### 方案一：一键 Bootstrap 启动器（推荐）

对齐 Win11Debloat 范式。一条命令 `irm <url> | iex` 下载并部署，免 clone；配置固化在 `%LOCALAPPDATA%`，位于程序目录之外，升级不覆盖。

- **优**：体验最好；配置与程序分离，升级安全；解决全部 6 个痛点
- **缺**：引入网络分发依赖；脚本复杂度最高

### 方案二：仓库内交互式 Setup 向导

保留 clone，新增 `setup.ps1` 一键跑完第 2~6 步。

- **优**：无网络依赖，改动集中在仓库内，风险最低
- **缺**：痛点 1（clone）未解决

### 方案三：Inno Setup 打包安装包

把 PS 脚本打成 `Setup.exe`，复用 `feature/wpf-desktop` 分支已有的 `setup.iss` 经验。

- **优**：Windows 用户最熟悉（双击安装）
- **缺**：需维护构建产物分发；每次改脚本都要重新打包；与 main「轻量 PS 脚本」定位有张力
- **结论**：不推荐

### 方案对比

| 维度 | 方案一 | 方案二 | 方案三 |
|------|-------|-------|-------|
| 用户步骤 | 1 条命令 | clone + 1 条命令 | 下载 + 双击 |
| 侵入性 | 中 | 低 | 高 |
| 维护成本 | 中 | 低 | 高 |
| 风险 | 网络依赖 | 最低 | 构建分发负担 |
| 解决 clone 痛点 | 是 | 否 | 是 |

**选型：方案一**。方案二可作为其子集随时降级使用（`setup.ps1` 本身即可独立运行）。

---

## 4. 详细设计

### 4.1 总体流程

```
bootstrap.ps1（可选入口，免 clone）
  ├─ 阶段 1  下载仓库归档（GitHub / Gitee / 本地三源）
  ├─ 阶段 2  解压到 %LOCALAPPDATA%\OpenCpolarSync\app
  └─ 阶段 3  提权调用 setup.ps1
                │
setup.ps1（核心向导）
  ├─ 阶段 1  检测并静默安装 Cpolar（msiexec /qn）
  ├─ 阶段 2  解压 openlist.zip 出 openlist.exe
  ├─ 阶段 3  交互式收集配置（webhook / 账号 / 隧道名 / 间隔）
  ├─ 阶段 4  生成 config.json（主副本 + 运行副本）
  ├─ 阶段 5  写入 cpolar.yml 并注册 authtoken
  ├─ 阶段 6  注册 Watchdog 计划任务并拉起 Guard
  └─ 收尾    打开 Openlist Web 引导挂载（唯一人工步骤）
```

### 4.2 配置分离策略

```
%LOCALAPPDATA%\OpenCpolarSync\
  ├── app\          <- 程序（升级时整体覆盖）
  └── config\       <- 配置主副本（升级不覆盖）
```

`setup.ps1` 每次运行都会把主副本**同步**一份到 `app\Cpolar\config\config.json`。这样：

- Guard 与 Watchdog **零改造**即可读到最新配置（它们仍读默认路径）
- 配置在程序目录之外，重复部署 / 升级不丢失
- 二次运行时主副本作为向导默认值，不必重填

### 4.3 函数划分（setup.ps1）

| 函数 | 职责 |
|------|------|
| `Write-Log` / `Write-Stage` | 分级着色日志与阶段标题 |
| `Invoke-Action` | 副作用统一包装，DryRun 下只打印不执行 |
| `Get-SpecialFolder` | 安全获取系统目录（环境变量缺失时回退 .NET API） |
| `Test-IsAdmin` | 管理员权限判断 |
| `Test-CpolarInstalled` | 注册表 / 路径 / 进程三重检测 |
| `Install-Cpolar` | msiexec 静默安装 |
| `Deploy-Openlist` | 解压并部署 openlist.exe（幂等） |
| `Set-CpolarTunnel` | 生成 cpolar.yml 并注册 authtoken |
| `Read-ExistingConfig` | 读取历史配置作为默认值 |
| `Invoke-ConfigWizard` | 交互式配置收集 |
| `New-GuardConfigFile` | 生成 config.json（手工拼 JSON 保中文可读） |
| `Register-WatchdogTasks` | 注册计划任务 |
| `Show-FinalChecklist` | 收尾引导与人工清单 |

### 4.4 参数设计

无人值守所需参数全部支持：`-WebhookUrl` `-CpolarUser` `-CpolarPassword` `-TunnelNames` `-Interval` `-AuthToken` `-Region` `-OpenlistPort`。

控制类：`-Silent`（非交互）`-DryRun`（演练）`-SkipCpolarInstall` `-SkipOpenlist` `-SkipTunnel` `-SkipWatchdog` `-NoBrowser` `-NoElevate`。

### 4.5 文件清单

| 文件 | 类型 | 说明 |
|------|------|------|
| `setup.ps1` | 新增 | 部署向导核心（UTF-8 BOM + LF） |
| `bootstrap.ps1` | 新增 | 免 clone 启动器（UTF-8 BOM + LF） |
| `Cpolar/CpolarGuard.ps1` | 修改 | 新增 `-ConfigPath` 参数（+20 / -2 行） |

---

## 5. 实现结果

### 5.1 CpolarGuard.ps1 改动（最小侵入）

```powershell
param(
    [string]$ConfigPath
)

if ($ConfigPath) {
    $configDir     = Split-Path -Parent $ConfigPath
    $configPath    = $ConfigPath
} else {
    $configDir     = Join-Path -Path $scriptDir -ChildPath "config"
    $configPath    = Join-Path -Path $configDir -ChildPath "config.json"
}
$sentCachePath    = Join-Path -Path $configDir -ChildPath "last-sent.json"
```

diff 仅 20 增 2 删，未触碰任何业务逻辑；不传参时行为与原来完全一致。

### 5.2 自测中修复的 4 个真实缺陷

| # | 缺陷 | 根因 | 修复 |
|---|------|------|------|
| 1 | 非控制台下脚本崩溃 | `[Console]::OutputEncoding` 在管道调用下抛异常 | try/catch 保护 |
| 2 | 非控制台下脚本崩溃 | `Clear-Host` 同上 | try/catch 保护 |
| 3 | `Join-Path` 收到 null | 宿主下 `$env:ProgramFiles` 为 null | 新增 `Get-SpecialFolder`，回退 .NET API |
| 4 | Mandatory 参数传 null | 首次运行时 `-Existing` 为 `$null` | 改用 `[AllowNull()]` |

> 缺陷 1~3 在计划任务（S4U，Session 0 无控制台）场景下**必然触发**，属于真实生产问题，不是测试环境噪音。

另将 `Deploy-Openlist` 由 .NET `ZipFile` 改为 `Expand-Archive` cmdlet——前者依赖 `System.IO.Compression.FileSystem` 程序集，在 PowerShell 7（.NET Core）上不可用。

---

## 6. 自测结果

**双版本实测：Windows PowerShell 5.1.26100（系统预装版）与 PowerShell 7.6.4，均为 28 项 PASS / 0 FAIL。**

| 环境 | PASS | FAIL |
|------|------|------|
| Windows PowerShell 5.1.26100（Desktop 版） | 28 | 0 |
| PowerShell 7.6.4 | 28 | 0 |

| 用例 | 结果 |
|------|------|
| T1 语法解析（4 个脚本） | 4/4 PASS |
| T2 CpolarGuard 参数化改造 | 2/2 PASS（含 param 位置合法性） |
| T3 setup.ps1 全阶段 DryRun | 6 阶段全部演练通过 |
| T4 DryRun 零副作用 | 5/5 PASS |
| T5 config.json 生成与解析 | 6/6 PASS（含 `p@ss"wo\rld` 特殊字符转义） |
| T6 辅助函数 | 2/2 PASS |
| T7 解压逻辑（模拟压缩包带子目录） | 2/2 PASS（含幂等） |
| T8 隧道 yml 生成 | 4/4 PASS |
| T9 bootstrap DryRun | PASS（正确解析 GitHub 地址） |
| T10 bootstrap 零副作用 | 2/2 PASS |

自测脚本：`.workbuddy/selftest.ps1`，报告：`.workbuddy/selftest.log`（PS 5.1 回归运行器：`.workbuddy/run51.ps1`，报告：`.workbuddy/selftest-ps51.log`）。

**安全约束**：自测全程未启动 `CpolarGuard.ps1`（常驻轮询脚本）；所有真实写入均在临时目录；本机未安装 cpolar，天然验证了安装步骤未被误触发。

---

## 6.1 PowerShell 5.1 兼容性

Windows PowerShell 5.1 是 Windows 系统预装版本，是绝大多数用户的实际运行环境，因此按 5.1 的能力集约束实现。

### 主动规避的 PS7 独占特性

| 特性 | 最低版本 | 本项目的处理 |
|------|---------|-------------|
| `ConvertFrom-Json -AsHashtable` | 6.0 | 不使用，统一用默认 `PSCustomObject` |
| 空合并 `??` / 空条件 `?.` / 三元 `? :` | 7.0 | 不使用，一律显式判断 |
| `$IsWindows` | 6.0 | 不使用 |
| `Out-File -Encoding utf8NoBOM` | 6.0 | 使用默认 UTF8（带 BOM），并手工控制 JSON 生成 |
| `System.IO.Compression.ZipFile` | — | 改用 `Expand-Archive`（PS 5.0+），该 .NET 程序集在 PS7/.NET Core 不可用 |

### 针对 5.1 的适配点

| 问题 | 处理 |
|------|------|
| 5.1 默认不启用 TLS 1.2，下载 GitHub 归档会失败 | `bootstrap.ps1` 显式设置 `[Net.ServicePointManager]::SecurityProtocol = Tls12` |
| `Invoke-WebRequest` 在 5.1 依赖 IE 引擎 | 统一加 `-UseBasicParsing` |
| `ConvertTo-Json` 在 5.1 会把中文转义成 `\uXXXX` | 自实现 `ConvertTo-JsonEscapedString` 生成 JSON |
| **5.1 按系统 ANSI 代码页（GBK）解析无 BOM 的 UTF-8 脚本，中文会损坏并导致语法错误** | 所有脚本统一保存为 **UTF-8 with BOM**（已在自测中实测复现该问题） |
| 5.1 控制台默认 GBK，强制设 `OutputEncoding = UTF8` 会让中文乱码 | 仅在 PS 6+ 或控制台已是 65001 时设置 |
| `bootstrap.ps1` 硬编码 `powershell.exe` 会把 setup 降级到 5.1 | 改用当前宿主进程路径（5.1 → powershell.exe，7.x → pwsh.exe） |

> 实测复现记录：最初用无 BOM 的 UTF-8 测试脚本在 5.1 下运行，中文常量被 GBK 解码为「缁撴潫」并抛出 `ParserError: 字符串缺少终止符`。主脚本因带 BOM 未受影响，该问题已在自测覆盖范围内。

---

## 7. 已知限制与待决策项

| # | 事项 | 说明 |
|---|------|------|
| 1 | **Openlist 存储挂载仍为人工** | 挂载配置存于 openlist 自身数据库，跨版本格式不稳，强写易碎。当前只做「打开 Web + 步骤清单 + 隧道校验」引导 |
| 2 | **GitHub 国内访问** | 已实现 GitHub / Gitee / 本地三源切换（`-Source`），默认 GitHub；访问不畅时建议 `-Source Gitee` |
| 3 | **cpolar.yml 字段需实机验证** | 隧道 yml 的写法依据 `cpolar --help` 推导，建议在真机首次运行后确认隧道能正常建立 |
| 4 | **CpolarGuard.ps1 编码** | 保持原有 BOM + CRLF（避免 1109 行全量 diff）；新增脚本统一 BOM + LF。如需全仓库统一换行，建议单独一次提交处理 |

---

## 8. 使用方式

```powershell
# 方式一：免 clone 一键部署
irm https://raw.githubusercontent.com/PingWangWang/OpenCpolarSync/main/bootstrap.ps1 | iex

# 方式二：已 clone 仓库，直接跑向导
powershell -ExecutionPolicy Bypass -File .\setup.ps1

# 演练（不产生任何副作用）
.\setup.ps1 -DryRun

# 无人值守
.\setup.ps1 -Silent -WebhookUrl 'https://oapi.dingtalk.com/...' `
            -CpolarUser 'a@b.com' -CpolarPassword 'pwd' -TunnelNames 'OpenListHC'
```
