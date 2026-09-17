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
| 自动获取最新版 | 调 Gitee API 取 release zipball | 免 clone |
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
  ├─ 阶段 1  下载仓库归档（Gitee / 本地两源）
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
| `setup.ps1` | 新增 | 部署向导核心（UTF-8 BOM + LF，**始终以本地文件方式执行**） |
| `bootstrap.ps1` | 新增 | 免 clone 启动器（**UTF-8 无 BOM + LF**，专供 `irm \| iex` 远程一行命令） |
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
| T9 bootstrap DryRun | PASS（正确解析 Gitee 地址） |
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
| 5.1 默认不启用 TLS 1.2，下载 Gitee 归档会失败 | `bootstrap.ps1` 显式设置 `[Net.ServicePointManager]::SecurityProtocol = Tls12` |
| `Invoke-WebRequest` 在 5.1 依赖 IE 引擎 | 统一加 `-UseBasicParsing` |
| `ConvertTo-Json` 在 5.1 会把中文转义成 `\uXXXX` | 自实现 `ConvertTo-JsonEscapedString` 生成 JSON |
| **5.1 按系统 ANSI 代码页（GBK）解析无 BOM 的 UTF-8 文件，中文会损坏并导致语法错误** | **以本地文件方式执行的脚本**统一保存为 **UTF-8 with BOM**（已在自测中实测复现该问题） |
| **`bootstrap.ps1` 同时支持 `irm \| iex` 与 `.\` 直接运行** | 保存为 **UTF-8 with BOM**，并把 `param()` 放在文件最前、`<# #>` 注释块移到其后（对齐 Win11Debloat 的 `Get_CN.ps1`）。`irm` 拉取时 .NET 在解码阶段自动剥离 BOM（字符串首字符即为 `param`，不含 BOM），故 BOM 不影响 `irm \| iex`；本地 `.\` 跑时 5.1 靠 BOM 识别 UTF-8，中文不乱码 |
| 5.1 控制台默认 GBK，强制设 `OutputEncoding = UTF8` 会让中文乱码 | 仅在 PS 6+ 或控制台已是 65001 时设置 |
| `bootstrap.ps1` 硬编码 `powershell.exe` 会把 setup 降级到 5.1 | 改用当前宿主进程路径（5.1 → powershell.exe，7.x → pwsh.exe） |

> **BOM 结论修正**（5.1.26100 + 7.6.4 实测）：
> - 无 BOM 的本地文件 → 5.1 按 GBK 解析，中文常量变成「缁撴潫」，抛 `ParserError: 字符串缺少终止符`。
> - **带 BOM 的脚本经 `irm \| iex` 是否失败，取决于脚本开头**：若开头是 `<# #>` 注释块，BOM 顶在 `<#` 前会使其失效、中文被当代码而报错（早期实测复现）；若开头是 `param(`（或普通语句），BOM 会被 `irm` 的 .NET 解码器自动剥离，**不影响解析执行**（本次以字节级证据验证：`irm` 拿到的字符串首字符已是 `param`，无 BOM）。
> - 结论：让一个脚本同时兼容两种跑法的正确姿势是 **BOM + `param()` 在前**（对齐 `Get_CN.ps1`），而非「无 BOM 专供 irm」。本次已将 `bootstrap.ps1` 据此改造，`setup.ps1` / `CpolarGuard.ps1` 本就是 BOM + `param`/注释，保持不变。

### 6.2 bootstrap.ps1 一行命令可靠性修复（发布后补充）

发布后真实环境（用户在国内网络）暴露两个问题，已修复：

1. **一行命令下载源不稳定（DNS / 镜像拦截）**：用户国内网络下远程源直连不稳定。修复：README 以 **Gitee 主源** 作为一行命令；`bootstrap.ps1` 下载仓库 zip 以 **Gitee Release 资产优先、Gitee 分支归档回退**（`irm \| iex` 无法传 `-Source` 参数，故必须在脚本内自动降级）。> 分发策略后续已在 **6.5** 修订：Gitee 源码归档对匿名请求不可用，实际只有 Release 资产一条通道。
2. **`iex` 解析失败（BOM 导致，早期结论已修正）**：原 `bootstrap.ps1` 带 BOM 且开头是 `<#` 注释块，经 `irm \| iex` 后注释块失效。修复：移除 BOM（见 6.1 的早期处理）。
3. **`Expand-Archive` 解压阶段崩溃「找不到中央目录结尾记录」**：用户在国内网络下远程源不可用 → 回退时，镜像返回 **HTTP 200 的 HTML 登录/拦截页（约 40KB）**，被当成 zip 下载，解压即崩。修复：`Get-RepoArchive` 下载后做**两道前置校验**——(a) 响应 `Content-Type` 为 `text/html` 直接抛「返回内容类型为 HTML」并提示登录页/错误页；(b) `Test-ZipFile` 校验 **ZIP 魔数（PK）+ 可打开完整性**，魔数不符抛「不是有效的 ZIP 压缩包」；两者均在 `Expand-Archive` 之前拦截，使「所有来源失败」能优雅回退并给出排查建议（离线 Local / git clone Gitee + setup.ps1 / 手动 zip）。`Get-RepoArchive` 还新增 **`-TimeoutSec 45`**，避免镜像卡死导致用户以为 PowerShell 无响应直接退出。`Test-ZipFile` 仅以魔数为硬门槛、完整性打开为尽力而为（不误杀合法 zip），并**移除了原先 `-lt 1024` 的长度门槛**（会误杀合法的小体积 zip，属 false negative）。已用自测脚本在 **PowerShell 5.1 与 7.x** 下覆盖：DryRun 列出两源、真 zip 解压成功、本地假 HTML 被拒、镜像返回 HTML 在下载阶段拦截、镜像返回非 ZIP 被拒——全部 PASS。

> Gitee 主源仓库为 `pingwang1994/OpenCpolarSync`；若临时不可用，可改用 `-Source Local` 离线归档。

### 6.3 bootstrap.ps1 双跑法改造（对齐 Win11Debloat Get_CN.ps1）

用户反馈：参考 Win11Debloat 的 `Get_CN.ps1`（`irm ... | iex` 和 `.\` 直接跑都行），希望 `bootstrap.ps1` 也支持 `.\` 直接运行（此前无 BOM，5.1 下 `.\` 跑会中文乱码、语法崩溃）。

**改造内容**：
1. `bootstrap.ps1` 从「无 BOM + 开头 `<#` 注释块」改为 **「UTF-8 with BOM + `param()` 在前」**，`<# ... #>` 帮助注释块整体移到 `param()` 之后。
2. 版本号 v1.2 → v1.3，注释内补充编码说明与双跑法用法。

**为何可行（实测验证，非仅推理）**：
- `irm` 返回字符串时，.NET 解码器会**自动剥离 UTF-8 BOM**——用字节级证据确认：`irm` 拿到的字符串首字符已是 `p`（`param`），UTF-16 字节为 `70 00 61 00`，不含 `EF BB BF`。因此 BOM 不会进入脚本内容、不影响解析。
- `param()` 在文件最前，即便有 BOM 残留也无害（与 `<#` 注释块被 BOM 顶坏的情况不同）。
- 本地 `.\` 跑时，PS 5.1 靠 BOM 识别 UTF-8，中文正确解码。

**双引擎实测**（5.1.26100 + 7.6.4）：
- `.\bootstrap.ps1 -DryRun` → 中文正常（「一键部署」「演练模式」等无乱码），两源顺序正确，零错误。
- `[scriptblock]::Create(内容)`（`irm|iex` 的解析层）→ `PARSE OK`，无语法错误。

**结论**：一个脚本同时兼容 `irm|iex` 与 `.\` 的正确姿势是 **BOM + `param()` 在前**，而非「无 BOM 专供 irm」。此前「本地脚本要 BOM、远程脚本要无 BOM」的二分法，在此场景下被更优的统一方案取代。

### 6.4 TLS 证书回调 bug 修复（各源统一「基础连接已经关闭」）

**触发**：用户在本机 `.\` 直接运行 bootstrap，各下载源**统一**报 `基础连接已经关闭: 发送时发生错误`，但用户执行 `Get_CN.ps1` 却能正常下载。

**根因**：`Get-RepoArchive` 里有两行 `ServicePointManager` 全局设置，其中第 2 行是元凶：
```powershell
[System.Net.ServicePointManager]::SecurityProtocol = ... -bor [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }  # ← 问题所在
```
`ServerCertificateValidationCallback` 是 **AppDomain 级全局回调**，设为 `{ $true }` 会干扰/破坏 .NET 底层 TLS 握手，在有代理/防火墙做 TLS 拦截的环境下，握手在「发送」阶段即失败 → 各源报同一个错（不可能是多站同时挂）。而 `Get_CN.ps1` 完全不碰这些设置，靠 PowerShell 默认行为即可正常下载。

**修复（v1.4）**：
1. **删除** `ServerCertificateValidationCallback = { $true }`（全局关证书校验既有副作用又有安全风险）。
2. 保留显式 `Tls12`（PS 5.1 默认仅 Ssl3|Tls，连不上要求 TLS1.2+ 的 CDN，这个是有必要的），但改为更明确的 `[System.Net.SecurityProtocolType]::Tls12` 直接赋值。

**实测**：删除回调后，TLS 握手通过，不再报「基础连接已经关闭」；两层防护（`Content-Type=text/html` 拦截 + ZIP 魔数校验）均正常识别并回退。

> **⚠️ 后修订（见 6.5）**：本节当时把 Gitee 返回的 HTML 登录页判为「沙箱特有现象」，并推断「用户本机可正常拿到真 zip」——**该推断已被真实用户环境证伪**。Gitee 对匿名请求**一律**返回登录页而非源码归档，与本机/沙箱无关。两层防护确实正确拦截并回退，但当时并不存在「能成功回退的真实源」，所以一行命令实际不可用。详见 6.5。

**教训**：`ServerCertificateValidationCallback` 这类 AppDomain 级全局设置不要轻易在脚本里设置；「放宽证书校验」的初衷（绕开 CRYPT_E_NO_REVOCATION_CHECK）应交给环境本身处理（如 `git -c http.schannelCheckRevoke=false` 仅针对 git，而非全局回调）。

### 6.5 一行命令在 Gitee 上必失败的真实根因与修复（发布包资产化）

**触发**：用户在真机执行 README 的一行命令，两条来源连续失败：

```text
[WARN] Release 下载失败：Gitee Release 未提供可下载的 zip
[WARN] Gitee 下载失败：下载内容不是有效的 ZIP 压缩包（魔数或完整性校验失败），来源可能返回了登录页或错误页
[ERROR] 所有来源均下载失败或返回了无效的压缩包
```

**根因（两点叠加）**：

1. **Gitee 对匿名请求不返回仓库源码归档。** 逐字节实测（匿名、无 Cookie、本机直连）：

   | 端点 | 结果 |
   |------|------|
   | `/repository/archive/main.zip` | HTTP 200，**46231 字节 HTML**（魔数 `3C 21` = `<!`，含「登录／验证」字样），**不是 zip** |
   | `/archive/refs/heads/main.zip` | 404 |
   | `/archive/refs/tags/v1.1.15.zip` | HTML（同上） |
   | `/repository/archive/main.tar.gz` | HTML |
   | `/releases/download/<tag>/bootstrap.ps1` | ✅ 正常返回脚本本体（2132 B） |
   | `/raw/main/bootstrap-core.ps1` | ✅ 正常返回 |
   | `/raw/main/Openlist/archive/openlist.zip`（71 MB） | ❌ 403 Forbidden |
   | `/raw/main/Cpolar/installer/cpolar_amd64.msi`（8 MB） | ✅ 正常返回 |

   结论：**Gitee 唯一可靠的匿名分发通道是 Release 资产（经 `foruda.gitee.com` CDN）**；源码归档接口与「大文件 raw」都不可匿名获取。这也解释了 6.4 中的 HTML 现象——它并非沙箱特有。

2. **Release 里从来没有发布包。** 原 `build_release_zip.ps1` 依赖 `Cpolar/config/config.json`，而该文件被 `.gitignore` 忽略（仓库里只有 `config.example.json`），构建**必然抛异常**；`publish_gitee_release.ps1` 又把它包在 `try/catch` 里「构建失败就只传两个 ps1」，于是 Release 只有 `bootstrap.ps1` / `bootstrap-core.ps1`，外加 Gitee 自动挂载的源码归档（同样是匿名拿不到的 HTML 链接）。两个下载策略因此全部落空。

**修复**：

1. `build_release_zip.ps1` 改用 **`git archive HEAD`** 打包全部受版本控制文件——补齐原手工清单缺失的 Guard / 卸载脚本，天然排除 `.git` 与被忽略的 `config.json`；产物含 `OpenCpolarSync-<Tag>/` 顶层目录（与解压提层逻辑一致），并新增 ZIP 魔数校验。产物约 **75 MB**（含 `openlist.zip` 71 MB + `cpolar_amd64.msi` 8 MB）。
2. `publish_gitee_release.ps1` 把构建改为**快速失败**（杜绝再发出缺少发布包的残缺 Release）；附件去重改用 **`/attach_files`** 端点取 `id`（Release 对象的 `assets` 数组不含 `id`）。
3. `bootstrap-core.ps1` 的 `Get-RepoArchiveFromRelease` **只认手工上传的 `OpenCpolarSync*.zip`**，显式排除 `/archive/` 源码归档链接；并同步修正失败排查提示。

**实测验证（匿名、无登录）**：`releases/latest` 返回 `OpenCpolarSync_v1.1.15.zip`；直接 GET 该资产 → **HTTP 200 / `Content-Type: application/zip` / `Content-Length: 78898214` / 魔数 `50 4B 03 04`**。一行命令链路恢复。

**踩坑记录（PowerShell 7 特有）**：`Invoke-RestMethod` 在 PS7 下把 JSON 数组**当作单个对象**返回，`@(Invoke-RestMethod ...)` 会把它**再包一层**；此时管道给 `Where-Object`，整个数组作为一项传入，而「对数组取属性」会返回**属性值数组**，`-eq` / `-like` 因此**误判为匹配**——`$dup.id` 插值出 `"3215277 3215431"`，URL 变成 `.../attach_files/3215277 3215431` → **HTTP 404**。修复：一律用 `foreach ($x in $resp)` 逐项展开，不用管道 `Where-Object`（同一隐患已在 `Get-RepoArchiveFromRelease` 的资产检索里一并修掉）。

**发布新版检查清单**：改完代码 → `build_release_zip.ps1 -Tag vX.Y.Z` 本地构建 → `publish_gitee_release.ps1 -Tag vX.Y.Z` 上传（**必须成功**，脚本已改为快速失败）→ 匿名验证 `releases/latest` 能取到并下载 `OpenCpolarSync_vX.Y.Z.zip`。

### 6.6 下载进度改为「底部就地刷新」（替换 Write-Progress）

**现象**：用户真机部署时，下载进度条出现在控制台**顶部**，与下方滚动的日志脱节。

**根因**：`Write-Progress` 在 Windows 控制台里固定绘制在**屏幕顶部**的一块保留区域（与光标位置无关），并没有「显示到底部」的选项——这是它在 PowerShell 里的固有实现，改参数解决不了。

**修复**：`bootstrap-core.ps1` 移除 `Write-Progress`，改为三个小工具函数，在**当前输出位置**就地刷新一行：

- `Write-ProgressLine` — `Write-Host ("`r" + $Text + $pad) -NoNewline`：用 `\r` 回到行首覆盖重写；`$pad` 用空格补齐「上一次更长」的内容，避免残留旧字符。
- `Complete-ProgressLine` — `Write-Host ''` 换行收尾，保证后续日志从新行开始、不被进度覆盖。
- `Test-ProgressEnabled` — 用 `[Console]::IsOutputRedirected` 探测；**输出被重定向（如写日志文件）时不绘制**，避免把回车控制符写进日志；宿主不支持该属性时静默降级为不显示。

由于写入点是「当前光标处」，进度自然落在最新一行（**底部**），与日志顺序一致。

附带改进：约 **100 ms 限流重绘**（避免高速下载刷屏）、显示「已下载 / 总量 MB + 百分比 + MB/s」、**只有真正下完才补画 100%**（中途失败不误报完成）。

**验证**：用真实 `Invoke-WebDownload` 抓取进度帧，确认为同一行内的 `\r` 覆盖刷新且带空格补齐（`<CR>…13%…<CR>…100% 完成␠␠␠␠␠␠`）；真实链路 `bootstrap-core.ps1 -NoSetup` 端到端仍 `SCRIPT_RC=0`（下载 75.25 MB + 解压 26 文件）。

### 6.7 桌面「配置向导」快捷方式

**需求**：部署完成后在桌面放一个快捷方式，用户以后**双击即可重新打开配置向导**，不必再记/敲 `irm ... | iex` 那一行命令。

**实现**：`setup.ps1` 新增 `New-DesktopShortcut`，主流程加「**阶段 7：桌面快捷方式**」。

| 项 | 取值 |
|---|---|
| 目标 | `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`（绝对路径，不继承 PATH 里的 pwsh） |
| 参数 | `-NoProfile -ExecutionPolicy Bypass -NoExit -File "<RootDir>\setup.ps1"` |
| 起始位置 | `$RootDir`（部署后即 `%LOCALAPPDATA%\OpenCpolarSync\app`） |
| 名称 | `OpenCpolarSync 配置向导.lnk` |
| 图标 | `%SystemRoot%\System32\shell32.dll,13` |

**关键点：必须带「以管理员身份运行」。** 向导要安装 msi、注册计划任务，都需要管理员权限；不带该标志时双击会因权限不足失败，或由向导自身再弹一次 UAC 并另开一个窗口。该标志位在 `.lnk` 头 `LinkFlags` 的 **RunAsUser（0x00002000）**，即第 **0x15** 字节的 **bit5（0x20）**——`WScript.Shell` 没有对应属性，所以只能创建后回写这一个字节：

```powershell
$bytes = [System.IO.File]::ReadAllBytes($lnkPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20
[System.IO.File]::WriteAllBytes($lnkPath, $bytes)
```

其他细节：

- `-NoExit`：让向导末尾的人工检查清单留在窗口里可读；关窗即结束。
- 桌面路径统一走 `Get-SpecialFolder -VariableName 'Desktop'`（优先 `Env:Desktop`，回退 `[Environment]::GetFolderPath('Desktop')`），兼容 OneDrive 重定向桌面。
- 创建失败只告警、**不阻断部署**；`-SkipShortcut` 可跳过。
- `Show-FinalChecklist` 只在 `.lnk` 确实存在时才提示「双击桌面快捷方式」，避免 `-SkipShortcut` / 创建失败时误导用户。

**卸载**：`uninstall.ps1` 新增「阶段 4：桌面快捷方式」（原阶段 4/5 顺延为 5/6），删除同名 `.lnk`。

**验证**：`setup.ps1 -DryRun -Silent -NoElevate -NoBrowser` 正确输出阶段 7 计划（含目标 `setup.ps1` 路径），全阶段无异常。

> ⚠️ 未验证项：`.lnk` 的实际创建依赖 `WScript.Shell` COM，本次在受限沙箱内无法执行（COM 实例化被安全策略拦截）。字节偏移 0x15 / 0x20 是通用做法，但**建议真机首次部署后双击确认一次**（应弹出 UAC 并进入配置向导）。


---

### 6.8 交互与观感优化（四项）

真机部署后收到的四条反馈，逐条修复。

#### 6.8.1 输出美化（`setup.ps1` / `bootstrap-core.ps1` / `uninstall.ps1`）

**问题**：原先只有 `[INFO] / [OK]` 这种方括号前缀 + `====` 分隔线，层级感弱、配色也偏素。

**改动**：三个脚本统一视觉语言。

| 元素 | 改前 | 改后 |
|---|---|---|
| 横幅 | `====` 三条 | `════` 双线规则 + 主标题 + 副标题（`Write-Banner`） |
| 阶段 | `--- 阶段 1：xxx ---` | 细线规则 + `阶段 1/7  ·  xxx`（`Write-Stage`，带总数） |
| 日志 | `[OK] 消息` | 级别符号 + 消息（`√ / ! / × / → / · / ~`） |
| 摘要 | `==== 部署结果摘要 ====` + 手动对齐 | `════` 标题栏 + 两列对齐 + 收尾规则 |

**关键约束：所有符号必须落在 GB2312 字符集内。** Windows PowerShell 5.1 的控制台默认是系统 ANSI 代码页（简体中文为 **GBK/936**），GB2312 之外的字符（如 `✔` U+2714、`✖` U+2716、`⚠` U+26A0、`╭` U+256D）会显示成方块或问号。因此刻意选用：

| 用途 | 字符 | 码位 | GB2312 |
|---|---|---|---|
| 成功 | `√` | U+221A | ✓ |
| 失败 | `×` | U+00D7 | ✓ |
| 警告 / 步骤 / 信息 | `!` `→` `·` | ASCII / U+2192 / U+00B7 | ✓ |
| 制表（单/双线） | `─` `═` | U+2500 / U+2550 | ✓ |

**故意不做右边框**：CJK 是双宽字符，要画右侧竖线就得按显示宽度补齐（汉字算 2 列），维护成本和出错概率都高。改用「左对齐 + 整行规则」即可获得同样的分组观感。

#### 6.8.2 配置向导增加卸载入口

**需求**：从桌面快捷方式打开的向导，也应该能选择卸载。

**实现**：`setup.ps1`

1. 新增开关 `-NoMenu`，并在主流程序列**解析路径之后、提权之前**插入操作菜单（1 安装/更新、2 卸载，默认 1）。
2. 显示条件：**非** `-Silent`、**非** `-DryRun`、**非** `-NoMenu`。即只在「独立交互运行」（双击快捷方式）时出现。
3. 选 2 时：由 `$installRoot = Split-Path -Parent $ConfigDir` 反推安装根目录（即 `%LOCALAPPDATA%\OpenCpolarSync`，与 `uninstall.ps1` 默认值一致），优先调用 `$RootDir\uninstall.ps1`，找不到再回退到 `$installRoot\app\uninstall.ps1`；已是管理员直接调用，否则经 `RunAs` 提权（停进程、删计划任务同样需要管理员）。
4. `bootstrap-core.ps1` 调用 setup 时**固定传 `$setupParams['NoMenu'] = $true`**——引导器自己已经问过「安装 / 卸载」，不传就会弹出两层重复菜单。
5. 自动提权重启自身时，参数列表同时追加 `-NoElevate -NoMenu`：用户已经选过操作类型，重启后不能再问一次。

#### 6.8.3 监控隧道名首次配置默认为空

**问题**：`$defaultTunnel = 'OpenListHC'` 会在用户什么都没建的时候预填一个具体隧道名——用户直接回车就接受了，而该隧道并不存在，Guard 随后一直报「隧道未找到」。真机截图里 `部署完成` 段落也确实打印出了 `- OpenListHC`。

**修复**：

- `$defaultTunnel` 改为 `''`。
- 随之而来的**参数绑定陷阱**：`Invoke-ConfigWizard` 的 `[Parameter(Mandatory=$true)][string]$DefaultTunnel` **拒绝空字符串**，传 `''` 直接抛「无法将参数绑定到参数 DefaultTunnel，因为它是空字符串」并中断整个向导（DryRun 实测在「阶段 3」戛然而止）。必须加 `[AllowEmptyString()]`（同时补 `[AllowNull()]`）。
- **空数组陷阱**：`@($default)` 在 `$default` 为空串时会得到 `@('')`，最终写出 `selectedTunnelNames: ["",]` 这种无意义配置。修法是三处同时兜底：
  - Silent 分支：`if ($default) { @($default) } else { @() }`；
  - 交互分支：用户直接回车且无默认值时给 `@()`；
  - 向导末尾统一过滤：`@($Values.TunnelNames | Where-Object { $_ -and "$_".Trim() })`；
  - `New-GuardConfigFile` 序列化前再过滤一次。
- 阶段 5 增加短路：隧道列表为空时**不写** `cpolar.yml`（写了也只有一个空的 `tunnels:` 段），改为提示「可稍后在配置文件中补充后重跑本向导」。
- 交互提示补上「（直接回车 = 暂不监控，可稍后在配置文件里补）」。

**验证**：隔离到临时 `-ConfigDir` 实跑一次配置生成，得到 `"selectedTunnelNames": []`（`json.loads` 解析为 `list`，长度为 0），不再是 `[""]`。

#### 6.8.4 收尾同时拉起 Openlist 与 Cpolar 两个网页

**问题**：`Show-FinalChecklist` 只 `Start-Process "http://localhost:$Port"`，只打开了 Openlist；Cpolar Web 只以文字形式提示，用户还得自己复制地址。

**修复**：两个地址都拉起，并给 400ms 间隔——两个地址在同一瞬间交给 shell 时，部分系统上会因争抢默认浏览器实例而只打开一个。`-NoBrowser` / `-DryRun` 分支的提示也同步改为打印两个地址。

**验证**：DryRun 输出 `~ 计划打开浏览器：Openlist http://localhost:5244 ；Cpolar http://localhost:9200`。

#### 6.8.5 四项改动的汇总

| # | 需求 | 涉及文件 | 关键改动 |
|---|---|---|---|
| 1 | 输出美化 | `setup.ps1` `bootstrap-core.ps1` `uninstall.ps1` | `Write-Banner` / `Write-Rule` / `Write-Stage` + GB2312 安全的级别符号 |
| 2 | 向导可选卸载 | `setup.ps1` `bootstrap-core.ps1` | `-NoMenu` 开关、操作菜单、`RunAs` 提权调用 `uninstall.ps1` |
| 3 | 隧道名默认留空 | `setup.ps1` | `$defaultTunnel=''`、`AllowEmptyString`、三处空数组兜底、阶段 5 短路 |
| 4 | 双网页拉起 | `setup.ps1` | `Show-FinalChecklist` 打开 Openlist + Cpolar，间隔 400ms |

**验证方式**：四个脚本全部通过 PowerShell AST 语法解析；`setup.ps1 -DryRun -Silent -NoElevate -NoBrowser` 端到端无异常（`SCRIPT_OK`）；配置生成实测写入 `[]`；编码校验三脚本均为 **UTF-8 with BOM + 纯 CRLF**。

> ⚠️ 未验证项（需真机确认）：6.8.2 的**卸载分支**会真实停进程、删计划任务，因此在沙箱内未实际执行，仅做代码复核。真机双击快捷方式后选「2」验证一次：应弹 UAC，随后进入卸载流程并删除桌面快捷方式。


---

### 6.9 进程幂等性：「重复运行向导不再重复拉起进程」

**现象**（真机卸载日志）：

```
--- 阶段 1：停止运行中的进程 ---
[STEP] 停止进程：openlist (PID=5616)
[STEP] 停止进程：cpolar (PID=3516)
[STEP] 停止进程：cpolar (PID=8496)      ← 同一个 cpolar 出现了两个实例
[STEP] 停止守护进程：powershell (PID=2528)
[STEP] 停止守护进程：powershell (PID=4036)
[OK] 已停止 5 个进程，等待文件句柄释放...
```

用户判断：多次执行配置向导时没有检测进程是否已启动，导致重复拉起。

#### 根因定位（逐个排查可能的拉起源）

| 候选来源 | 结论 |
|---|---|
| `setup.ps1` 直接 start cpolar | ❌ 代码里没有 |
| `CpolarGuard.ps1` | ❌ 只轮询 API，不启动 cpolar |
| `OpenlistGuard.ps1` → `openlist.exe` | ✅ 会启动，但**已有** `Get-Process` 前置检测 |
| `Cpolar/AutoStart.bat` | ❌ 只管理 CpolarGuard 的启动文件夹快捷方式 |
| `WatchdogManager.bat setup` | ❌ 只注册计划任务 |
| **`Set-CpolarTunnel` → `cpolar.exe authtoken <token>`** | ✅ **正解** |

`Set-CpolarTunnel` 原本无条件执行 `& cpolar.exe authtoken $Token`。而 **cpolar.exe 是常驻客户端**：在 cpolar 已经运行的情况下再执行一次 `authtoken`，会额外拉起一个新实例。于是每跑一次向导就多一个 cpolar 进程——与日志里两个 cpolar PID 完全吻合。

另外 `GuardCheck.ps1` 存在一个**竞态窗口**：它靠「命名 Mutex 是否 createdNew」判断 Guard 是否存活，但「创建 Mutex → `Start-Process` 拉起 Guard」之间有时差；若 Guard 进程已起、还没执行到 `WaitOne`，下一次 tick 仍会看到 `createdNew=$true`，于是再拉起一个。

#### 修复（4 处）

**① `Set-CpolarTunnel`：先检测再调用**（核心）

```powershell
$runningCpolar = @(Get-ProcessList -Name 'cpolar')
if ($runningCpolar.Count -gt 0) {
    Write-Log 'INFO' "Cpolar 已在运行（PID=$($runningCpolar[0].Id)），跳过 authtoken 命令注册（yml 已写好，重启 Cpolar 后生效）"
    return $true
}
```

`cpolar.yml` 本来就由同一个函数手工写入（含 `authtoken:` 段），所以跳过 CLI 不会丢配置，只是生效时机推迟到 cpolar 下次重启。

**② 新增「运行状态检查」预检段**（阶段 1 之前）

每次运行向导都先清点 `cpolar` / `openlist` / 本工具 Guard 的实例数量，0 个记 `未运行`、1 个记 `运行中（PID=…）`、≥2 个记 `WARN … 可能存在重复拉起`。

**③ Guard 进程自动去重**

Guard 是本工具自己的进程，同名出现 2 个一定是错误 → 自动结束多余的，保留启动最早的一个。

**④ `GuardCheck.ps1` 加进程级兜底**

在 Mutex 判定之外再查一次进程：命令行以 `-File` 方式运行且路径等于该 Guard 脚本，则认为已存在，跳过拉起。

#### 关键安全设计：宁可漏检，也不误杀

去重会执行 `Stop-Process -Force`，误判的代价是**结束用户的进程**，因此匹配条件刻意收紧为两条同时满足：

1. 命令行必须含 `-File`（排除 `-Command` 里只是「提到」某文件名的进程）；
2. 必须匹配 Guard 脚本的**完整路径**（`<RootDir>\Cpolar\CpolarGuard.ps1` 等），不做文件名通配。

只给 `BaseDir` 无法命中时直接返回空数组——**漏检只是少清理一次，误杀却是事故**。

> 这个收紧不是设计时想到的，而是**单测抓出来的**：最初只按文件名子串匹配，测试脚本自身的命令行恰好含 `CpolarGuard.ps1` 字样，于是把自己识别成了 Guard（`count=1` 而非 0）。修正后干净环境下为 0，且真实 Guard 命令行仍能命中。

#### 对第三方进程只报告不处理

`cpolar` / `openlist` 的进程模型不完全可控（例如 cpolar 可能由自身服务拉起、进程数语义未知），所以仅输出告警与处置建议，**不自动结束**。

#### 验证

| 项 | 结果 |
|---|---|
| AST 语法解析 | setup.ps1 / GuardCheck.ps1 / OpenlistGuard.ps1 / CpolarGuard.ps1 全部 OK |
| `Get-ProcessList` 对不存在进程 | 返回空数组（`-is [array]` 为 True），不报错 |
| `Select-DuplicateProcess` | 2×CpolarGuard + 1×OpenlistGuard → 只挑出晚启动的 1 个；无重复时返回 0；`StartTime` 缺失时按 Id 兜底 |
| `Write-ProcessStatus` 三档 | 0 → `[INFO] 未运行`；1 → `[OK] 运行中（PID=7）`；2 → `[WARN] 检测到 2 个实例（PID=7, 8）` |
| 匹配收紧后 | 干净环境下 `Get-ToolProcesses` 返回 0；构造真实 Guard 命令行（含 `-File` + 完整路径）能命中；不同目录的 `CpolarGuard.ps1` 不命中 |
| DryRun 全流程 | 预检段正常渲染（Cpolar/Openlist/Guard 三行），七阶段无异常 |
| 真实执行（Silent + 全跳过） | `REAL_OK`，预检与收尾均正常 |

> ⚠️ 未验证项：**「检测到重复后实际结束进程」这一条在沙箱内无法端到端执行**——沙箱拦截了 `Start-Process`（PowerShell 与 Bash 两条路径都拦），无法造出两个真实的 Guard 进程。该分支的逻辑（分组、挑多余、`Stop-Process`）已通过函数级单测覆盖，`Stop-Process` 本身是标准 cmdlet。真机首次运行时可留意预检段是否出现 `已结束多余的 Guard 进程 …`。


---

## 7. 已知限制与待决策项

| # | 事项 | 说明 |
|---|------|------|
| 1 | **Openlist 存储挂载仍为人工** | 挂载配置存于 openlist 自身数据库，跨版本格式不稳，强写易碎。当前只做「打开 Web + 步骤清单 + 隧道校验」引导 |
| 2 | **Gitee 主源访问** | 已全面迁移至 Gitee。分发通道为 **Gitee Release 资产**（唯一可匿名访问）：`bootstrap.ps1` 从 Release 资产取 `bootstrap-core.ps1`，再由其从 `releases/latest` 取 `OpenCpolarSync*.zip` 发布包。⚠️ Gitee **源码归档接口对匿名请求返回登录页 HTML**，不能作为下载源（见 6.5）；发布新版必须执行 `publish_gitee_release.ps1` 上传发布包，否则一行命令必然失败 |
| 3 | **cpolar.yml 字段需实机验证** | 隧道 yml 的写法依据 `cpolar --help` 推导，建议在真机首次运行后确认隧道能正常建立 |
| 4 | **CpolarGuard.ps1 编码** | 保持原有 BOM + CRLF（避免 1109 行全量 diff）；新增脚本统一 BOM + LF。如需全仓库统一换行，建议单独一次提交处理 |

---

## 8. 使用方式

```powershell
# 方式一：免 clone 一键部署
irm https://gitee.com/pingwang1994/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 | iex

# 方式二：已 clone 仓库，直接跑向导
powershell -ExecutionPolicy Bypass -File .\setup.ps1

# 演练（不产生任何副作用）
.\setup.ps1 -DryRun

# 无人值守
.\setup.ps1 -Silent -WebhookUrl 'https://oapi.dingtalk.com/...' `
            -CpolarUser 'a@b.com' -CpolarPassword 'pwd' -TunnelNames 'OpenListHC'
```
