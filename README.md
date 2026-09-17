# OpenCpolarSync

> Windows 平台：Cpolar 隧道状态监控 + Openlist 文件服务守护 + 运行时保活看门狗，支持一键部署与一键卸载

![Gitee](https://img.shields.io/badge/platform-Gitee-lightgrey)
![License](https://img.shields.io/badge/License-MIT-blue)
![Version](https://img.shields.io/badge/version-1.1.15-orange)

## 项目简介

OpenCpolarSync 是一个面向 Windows 用户的工具集，核心功能：

| 模块 | 用途 |
|------|------|
| **Cpolar 监控** | 轮询 Cpolar 隧道状态，变更时通过钉钉 Webhook 推送通知 |
| **Openlist 守护** | 监控 openlist.exe 进程，崩溃自动重启 |
| **Watchdog 保活** | 守护进程异常退出时自动拉起，基于 Windows 计划任务（S4U） |

提供两种使用方式：
- **PowerShell 脚本版**（当前推荐）：一条命令完成部署，轻量无安装包
- **WPF 桌面版**（开发中）：图形界面，支持托盘、主题切换、可视化配置，见 `src/OpenCpolarSync.Client`

---

## 🚀 快速开始

### 一键安装

在 **Windows PowerShell** 中粘贴执行（无需安装 git，无需手动下载）：

```powershell
irm https://gitee.com/pingwang1994/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 | iex
```

启动后会先询问操作类型：

```
  请选择操作：
    1. 安装 / 更新 OpenCpolarSync
    2. 卸载 OpenCpolarSync
```

选 `1` 即可进入安装向导，按提示输入配置即可。

> 💡 部署完成后会自动在**桌面**创建「**OpenCpolarSync 配置向导**」快捷方式（已带「以管理员身份运行」标志）。
> 以后要改配置，**双击它即可**重新打开向导，不必再执行上面的命令。
> 向导启动后会先询问操作类型（1 安装/更新、2 卸载），所以**卸载也能从这里走**，无需再敲命令。
> 不需要可用 `-SkipShortcut` 跳过创建。

**备用方式（Gitee raw 直链）：**

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
irm https://gitee.com/pingwang1994/OpenCpolarSync/raw/main/bootstrap.ps1 | iex
```

### 一键卸载

同样的命令，选 `2` 即可：

```powershell
irm https://gitee.com/pingwang1994/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 | iex
# 选择 2. 卸载
```

卸载流程会自动完成：
1. 停止 openlist / cpolar 进程及守护进程
2. 移除 Watchdog 计划任务
3. 删除程序目录（自动重试，应对文件被占用）
4. 删除桌面「OpenCpolarSync 配置向导」快捷方式
5. 可选删除配置文件（含密码、Webhook 等）
6. 可选卸载 Cpolar 客户端

### 强制更新（重新下载程序文件）

默认情况下，检测到已安装会跳过下载。如需强制重新下载最新程序文件，需先下载脚本再带参数运行：

```powershell
# 下载到本地
irm https://gitee.com/pingwang1994/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1

# 带 -Force 参数运行（强制重新下载程序文件）
& $env:TEMP\bootstrap.ps1 -Force
```

> **注意**：`irm ... | iex` 这种管道方式无法传递参数，必须先下载到本地再运行。

### 直接卸载（跳过选择菜单）

```powershell
irm https://gitee.com/pingwang1994/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1
& $env:TEMP\bootstrap.ps1 -Uninstall
```

---

## 📋 命令参数大全

### bootstrap.ps1 参数

| 参数 | 说明 |
|------|------|
| `-Force` | 强制重新下载程序文件（跳过已安装检测） |
| `-Uninstall` | 直接进入卸载模式，跳过选择菜单 |
| `-Source Gitee/Local` | 下载来源，默认 Gitee |
| `-InstallDir <路径>` | 自定义安装目录，默认 `%LOCALAPPDATA%\OpenCpolarSync` |
| `-DryRun` | 演练模式，只打印计划不执行 |
| `-NoElevate` | 不自动请求管理员权限 |

### setup.ps1 参数（已 clone 仓库或本地运行时使用）

| 参数 | 说明 |
|------|------|
| `-Silent` | 非交互模式，全部配置由参数传入 |
| `-WebhookUrl <url>` | 钉钉机器人 Webhook 地址 |
| `-CpolarUser <邮箱>` | Cpolar 登录邮箱 |
| `-CpolarPassword <密码>` | Cpolar 登录密码 |
| `-OpenlistPassword <密码>` | Openlist Web 登录密码 |
| `-TunnelNames <名称>` | 要监控的隧道名，多个用逗号分隔 |
| `-Interval <分钟>` | 轮询间隔，默认 1 分钟 |
| `-AuthToken <token>` | Cpolar authtoken（免登录创建隧道） |
| `-SkipCpolarInstall` | 跳过 Cpolar 安装检测 |
| `-SkipOpenlist` | 跳过 openlist 部署 |
| `-SkipTunnel` | 跳过 Cpolar 隧道配置 |
| `-SkipWatchdog` | 跳过 Watchdog 计划任务注册 |
| `-OpenlistReadyTimeout <秒>` | 注册 Watchdog 后等待 Openlist 就绪的最长秒数，默认 30 |
| `-SkipShortcut` | 跳过在桌面创建「配置向导」快捷方式 |
| `-NoMenu` | 不问「安装 / 卸载」，直接进入安装流程（由 `bootstrap-core.ps1` 自动传入，避免重复询问） |
| `-NoBrowser` | 不自动打开 Openlist / Cpolar 网页 |
| `-DryRun` | 演练模式 |

### 无人值守部署示例

```powershell
.\setup.ps1 -Silent `
    -WebhookUrl 'https://oapi.dingtalk.com/robot/send?access_token=xxx' `
    -CpolarUser 'you@example.com' `
    -CpolarPassword 'your-password' `
    -OpenlistPassword 'openlist-web-password' `
    -TunnelNames 'OpenListHC'
```

---

## 🔧 部署流程说明

一键部署在正式阶段开始前，会先做一次**运行状态检查**（清点 Cpolar / Openlist / Guard 实例数），
然后自动完成以下步骤：

| 阶段 | 动作 |
|------|------|
| 1 | 检测 Cpolar 客户端，未安装则自动从官网下载并静默安装 |
| 2 | 解压 openlist.exe 到程序目录 |
| 3 | 交互式收集配置（Webhook、邮箱、密码、隧道名等，**当前值会回显**） |
| 4 | 生成 config.json 并持久化到用户目录（升级不丢失） |
| 5 | 写入 cpolar.yml 隧道配置 |
| 6 | 注册 Watchdog S4U 计划任务 → **立即触发一次**，由 Guard 拉起两个守护进程 → 等待 Openlist 就绪（≤ `-OpenlistReadyTimeout` 秒） |
| 7 | 在桌面创建「OpenCpolarSync 配置向导」快捷方式（以管理员身份运行） |
| 收尾 | 打开 Openlist / Cpolar 网页（**只打开端口确实已在监听的页面**），并输出部署结果摘要 |

> 阶段 6 为什么要「立即触发 + 等待就绪」：注册计划任务只是**排期**，`WatchdogManager.bat` 用的触发器是
> 注册后 **1 分钟**才首次运行。若不等这一下，收尾摘要会显示 `Openlist 未运行`，自动打开的 5244 也会是空白页。
> 等待超时**不算部署失败**——Guard 会在后续轮询周期继续重试，只是收尾不再打开页面并提示看
> `Openlist\logs\guard.log`。

> 阶段 7 的快捷方式是后续**改配置 / 卸载的入口**：双击即可重新运行本向导（会载入现有配置作为默认值），
> 向导启动后可选择「安装 / 更新」或「卸载」。
> 卸载时由 `uninstall.ps1` 一并删除该快捷方式。

> 🖥️ 部署收尾会自动打开 **Openlist**（`http://localhost:5244`）与 **Cpolar Web**（`http://localhost:9200`）
> 两个页面：前者用于完成存储挂载，后者用于确认隧道是否在线。
> 只会打开**端口确实已在监听**的页面——进程刚起时端口还没开始听，硬开只会得到一个空白页；
> 没就绪的那个会给出提示而不是打开。不想自动打开可加 `-NoBrowser`。

> ℹ️ 首次配置时「要监控的隧道名」默认为**空**，不会预填任何隧道名——此时会跳过 cpolar.yml 写入。
> 需要监控时，重新双击向导补填，或直接修改配置文件里的 `selectedTunnelNames`（运行中改动会自动生效）。

> 🔁 **可以重复运行**：向导每次启动都会先做一次「运行状态检查」，清点 Cpolar / Openlist / Guard 的实例数量。
> 已在运行的组件不会被重复拉起——例如 Cpolar 已在运行时不再执行 `cpolar.exe authtoken`
> （该命令会额外拉起一个 cpolar 实例）。因此反复执行向导是安全的，不会攒出多份进程。

### 仍需手动完成的一步

**Openlist 存储挂载**需要在 Web 界面完成（该页面部署结束时会自动打开）：
1. 浏览器打开 `http://localhost:5244`（若未自动打开则手动访问）
2. 登录账号 `admin`，密码为部署时设置的 Openlist 密码
3. 进入「存储」→「添加」，挂载本地目录或网盘

---

## 📁 目录与配置

### 安装目录

- **程序目录**：`%LOCALAPPDATA%\OpenCpolarSync\app`
- **配置目录**：`%LOCALAPPDATA%\OpenCpolarSync\config`（位于程序目录之外，升级不丢失）

### 配置文件

- **主副本**：`%LOCALAPPDATA%\OpenCpolarSync\config\config.json`
- **运行副本**：`app\Cpolar\config\config.json`（每次运行 setup.ps1 自动从主副本同步）

### 关键端口

| 服务 | 地址 |
|------|------|
| Openlist Web | http://localhost:5244 |
| Cpolar Web | http://localhost:9200 |

---

## 🖥️ WPF 桌面版（开发中）

项目同时在开发 WPF 桌面版，提供图形界面：

- 位置：`src/OpenCpolarSync.Client`
- 技术栈：.NET Framework 4.8 + WPF
- 功能：服务总览、Cpolar 配置、Openlist 配置、日志查看、设置（主题/背景效果/关闭行为/开机自启）
- 安装包：Inno Setup 打包，输出 `OpenCpolarSync-Setup_<version>.exe`

### 编译与打包

```powershell
# Debug 编译
.\scripts\build-debug.ps1

# Release 编译
.\scripts\build-release.ps1

# 打包安装包（需安装 Inno Setup）
.\scripts\package.ps1

# 一键编译 Release + 打包 + 版本号自增
.\scripts\build-and-package.ps1
```

---

## 📂 仓库结构

```
OpenCpolarSync/
├── bootstrap.ps1               # 纯 ASCII 引导器（irm|iex 入口）
├── bootstrap-core.ps1          # 引导器主逻辑（下载+解压+安装/卸载选择）
├── setup.ps1                   # 一键部署向导
├── uninstall.ps1               # 一键卸载脚本
├── build_release_zip.ps1       # 生成发布包 zip（作为 Gitee Release 资产分发）
├── publish_gitee_release.ps1   # 一键发布到 Gitee（建/复用 Release + 上传资产）
├── Cpolar/                     # Cpolar 隧道监控
│   ├── CpolarGuard.ps1         # 常驻守护脚本
│   ├── AutoStart.bat           # 开机自启管理
│   ├── config/                 # 配置文件
│   ├── installer/              # Cpolar 安装包（运行时自动下载）
│   └── README.md
├── Openlist/                   # Openlist 服务守护
│   ├── OpenlistGuard.ps1       # 常驻守护脚本
│   ├── AutoStart.bat           # 开机自启管理
│   ├── archive/                # openlist 发布包
│   └── README.md
├── Watchdog/                   # 运行时保活看门狗
│   ├── GuardCheck.ps1          # 通用巡检脚本
│   ├── WatchdogManager.bat     # 统一管理入口
│   └── README.md
├── src/OpenCpolarSync.Client/  # WPF 桌面版（开发中）
├── scripts/                    # 编译/打包脚本
├── installer/                  # Inno Setup 安装脚本
├── docs/                       # 设计文档
├── LICENSE
└── README.md
```

---

## ❓ 常见问题

### Q: 执行 `irm | iex` 时提示"禁止运行脚本"？

先放开当前用户的执行策略（一次即可）：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### Q: 如何强制重新下载程序文件？

`irm | iex` 无法传参数，需先下载再运行：

```powershell
irm https://gitee.com/pingwang1994/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1
& $env:TEMP\bootstrap.ps1 -Force
```

### Q: 卸载时提示文件被占用？

卸载脚本会自动重试 3 次。如仍失败，重启电脑后手动删除 `%LOCALAPPDATA%\OpenCpolarSync\app` 目录即可。

### Q: Cpolar 安装包找不到？

最新版 setup.ps1 会在本地 msi 不存在时自动从 cpolar 官网下载。如下载失败，请手动安装 Cpolar 后重试：https://www.cpolar.com/download

### Q: 配置会在升级时丢失吗？

不会。配置文件保存在 `%LOCALAPPDATA%\OpenCpolarSync\config`，位于程序目录之外。

### Q: 反复运行向导会产生多个 cpolar / openlist 进程吗？

不会（v1.1.15 起）。向导启动时会先做「运行状态检查」：已在运行的组件不会被重复拉起；
本工具自己的 Guard 进程若出现重复，还会自动去重（保留启动最早的那个）。

如果检查结果里 Cpolar / Openlist 显示 **≥2 个实例**，说明或是旧版本遗留的进程，或是该程序
自身启动了多份。向导此时只告警并给建议，**不会替你结束第三方进程**——确认后可在「任务管理器」
里保留一个、结束其余，再重新运行向导即可。

### Q: 首次部署完成后 `Openlist` 显示「未运行」，5244 也打不开？

先确认是不是**时间没到**。`openlist.exe` 不是向导直接启动的，而是由 `OpenlistGuard` 启动，
而 Guard 由 Watchdog 计划任务拉起。

- **v1.1.15 起（当前版本）**：向导在阶段 6 注册完计划任务后会**立刻触发一次**并等待 Openlist
  就绪（默认最多 30 秒）；一般收尾时摘要里就是「运行中（PID=…）」，页面也会正常打开。
- 若摘要显示「尚未就绪」，说明等待超时了。它**不是部署失败**——Guard 会在后续轮询周期继续重试，
  通常 1 分钟内起来。等一会儿再刷新 http://localhost:5244 即可。
- 若**一直**起不来，看这两个日志：
  - `%LOCALAPPDATA%\OpenCpolarSync\app\Openlist\logs\guard.log` —— 里面 `openlist.exe started. PID=…`
    说明启动成功；`openlist.exe not found at:` 说明解压没做成功；`started` 之后紧跟 `not found`
    说明进程起来后立刻退出了。
  - `%LOCALAPPDATA%\OpenCpolarSync\app\Watchdog\watchdog.log` —— 每次计划任务 tick 与 Guard 重启记录。

> 顺带一提：`Cpolar` 显示「运行中」不代表是向导启动的——cpolar 是自带常驻的客户端，通常在跑向导之前
> 就已经在运行了，因此它和 Openlist 的启动时机不可比。

---

## 前置条件

- **系统**：Windows 7 SP1+
- **PowerShell**：5.0+（已在 5.1 和 7.x 实测通过）
- **权限**：注册计划任务和安装 Cpolar 需要管理员权限（脚本自动请求提权）
- **Cpolar 账号**：用于隧道监控
- **钉钉机器人**：用于状态推送（可选）

---

## ⚠️ 注意事项

1. `config.json` 含明文密码，已从版本控制中忽略
2. 升级程序不会丢失配置
3. 卸载时可选是否删除配置和 Cpolar 客户端
4. 脚本编码：`bootstrap.ps1` 为纯 ASCII，`setup.ps1` / `bootstrap-core.ps1` / `uninstall.ps1` 为 UTF-8 with BOM

---

## 🛠️ 维护者指南：修改与发布流程

> 本节面向**项目维护者**，说明「改代码 → 推送 → 发布 → 验证」的完整手工流程。
> 普通使用者无需阅读。

### 一条铁律

**`main` 分支 = `vX.Y.Z` tag = Gitee Release 资产，三者必须指向同一个提交。**

原因是 Gitee 对匿名请求的分发限制（实测，无 Cookie、无登录）：

| 端点 | 结果 |
|------|------|
| `/repository/archive/main.zip` | HTTP 200，但返回**登录页 HTML**，不是 zip |
| `/archive/refs/tags/<tag>.zip` | 同上（返回 HTML） |
| `/raw/main/<小文件>` | ✅ 可用 |
| `/raw/main/<大文件，如 71MB 的 openlist.zip>` | ❌ 403 |
| `/releases/download/<tag>/<资产>` | ✅ **唯一可靠的匿名分发通道** |

两个关键推论：

1. **发布包必须作为 Release 资产上传**，不能用源码归档 URL 当下载源，也没有可用的回退源。
2. **tag 决定资产 URL**——tag 没前移，用户下载到的就还是旧代码。

### 版本号需要同步的位置

改版本号时这几处要一起改，漏一处就会出现「代码是新的、用户下载到的是旧的」：

| 位置 | 内容 |
|------|------|
| `bootstrap.ps1` | `$coreUrl` 里硬编码的 tag：`.../releases/download/v1.1.15/bootstrap-core.ps1` |
| `build_release_zip.ps1` | `$Tag` 默认值 |
| `publish_gitee_release.ps1` | `$Tag` 默认值 |
| `README.md` | 徽标版本号 + 各条安装命令 URL 里的 tag |

### 完整流程（7 步）

#### ① 改代码

按项目编码约定修改（见本节末尾「编码约定」）。

#### ② 本地自测

```powershell
# 演练模式：只打印计划、不下载不解压不执行
.\setup.ps1 -DryRun -Silent -NoElevate -NoBrowser

# 引导器演练（含下载/解压逻辑，但不调用 setup.ps1）
.\bootstrap-core.ps1 -DryRun
```

#### ③ 提交（代码 + 文档一起提交）

> ⚠️ **顺序很关键。** 发布包由 `git archive HEAD` 生成，**HEAD 里有什么就打什么**。
> 如果先构建发布包、之后再补文档提交，包里就是旧文档——这种漂移几乎不会被发现，代价却是多跑一次 75MB 上传。
> 所以：**一次把代码和文档都改完、都提交完，最后只跑一次发布。**

```powershell
git add -A
git commit -m "feat(SCOPE): 变更说明"     # 提交规范见项目约定
```

#### ④ 推送到 Gitee

```powershell
git push origin main
```

#### ⑤ 前移 tag 到本次发布提交

```powershell
$commit = (git rev-parse HEAD).Trim()          # 或用 git log --oneline -1 看提交号

git tag -f v1.1.15 $commit
git push -f origin refs/tags/v1.1.15

# 必须核实远端 tag 真的指向新提交（git tag 只是本地的，不算数）
git ls-remote --tags --refs origin v1.1.15
```

#### ⑥ 发布（构建发布包 + 上传资产）

```powershell
# 令牌只放环境变量，绝不写进脚本、绝不提交
$env:GITEE_TOKEN = '<你的 Gitee 私人令牌>'

.\publish_gitee_release.ps1 -Tag v1.1.15
```

脚本自动完成：`git archive` 构建 `%TEMP%\OpenCpolarSync_v1.1.15.zip`（约 **75MB**）→ 建/复用 Release → 上传三个资产（`bootstrap.ps1`、`bootstrap-core.ps1`、发布包）。

- 上传 75MB 需几分钟，属正常，建议后台跑并看脚本自己输出的 `SCRIPT_RC=0`。
- 构建失败时脚本**直接中止**，不会发出残缺 Release（这点是刻意的，见「常见坑」）。
- 只想重传已有 zip、不重新构建，可加 `-SkipZip`。

#### ⑦ 匿名验证（**别跳**）

```powershell
# a) latest 指向哪个版本、有哪些资产
Invoke-RestMethod 'https://gitee.com/api/v5/repos/pingwang1994/OpenCpolarSync/releases/latest' | Select-Object tag_name

# b) 匿名下载发布包，确认是真 zip + 大小约 75MB
irm https://gitee.com/pingwang1994/OpenCpolarSync/releases/download/v1.1.15/OpenCpolarSync_v1.1.15.zip `
    -OutFile $env:TEMP\check.zip

# c) 校验魔数：合法 ZIP 以 PK 开头（十六进制 50 4B 03 04）
$fs = [System.IO.File]::OpenRead("$env:TEMP\check.zip")
$b = New-Object byte[] 4; [void]$fs.Read($b, 0, 4); $fs.Close()
($b | ForEach-Object { $_.ToString('X2') }) -join ' '     # 期望：50 4B 03 04
```

> ⚠️ **HTTP 200 不等于拿到了真 zip**——Gitee 返回的登录页 HTML 也是 200。必须确认魔数。
> 更进一步，可以解压发布包后确认**关键脚本确实是新版**（例如 grep 新增的函数名），而不只是「下到的是个 zip」。
>
> ⚠️ **不要用 `Range: bytes=0-1` 去「只取两字节验魔数」**：Gitee CDN 会**忽略 Range**，以 HTTP 200 返回**整个 75MB 包**（不是 206，也没有 `Content-Range`）。要么先完整下载再取前 4 字节，要么限长读取（`$fs.Read($b,0,4)` 这种本地读法不受影响；受影响的是 HTTP 请求时手加 `Range` 头）。
>
> ⚠️ **写包内容断言前，先在源码里 grep 一遍**：① 别断言运行时拼出来的字符串（源码只有 `阶段 $Number/$Total`，`阶段 6/6` 在文件里不存在）；② 别用 `endswith('/README.md')` 这类后缀匹配，包里还有 `Openlist/README.md` / `Cpolar/README.md`，要用「顶层目录前缀 + 精确相对路径」定位。

### 常见坑

| 现象 | 原因 / 处理 |
|------|------|
| 上传报 404，日志里 URL 带两个 id（如 `.../attach_files/3215277 3215431`） | PowerShell 7 的 `Invoke-RestMethod` 把 JSON 数组当单个对象，不展开。项目脚本内已统一改为 `foreach` 逐项处理；自己另写脚本时要注意 |
| 一键安装报「下载内容不是有效的 ZIP 压缩包」 | 多数是 Release 里**没有**发布包资产，安装脚本回退去取源码归档（拿到登录页 HTML）。检查第 ⑥ 步是否成功 |
| 查询 Release 返回 HTTP 200 但内容为空 | Gitee 在 tag 不存在时返回 `null` 而非 404 → 必须判 `id` 是否存在，`try/catch` 抓不到 |
| 新建 Release 报 400 Bad Request | tag 尚不存在时必须带 `target_commitish` |
| PowerShell 脚本在 5.1 下中文乱码 | 见下「编码约定」 |
| `Setup.ps1` 语法/中文异常 | 用 UTF-8 with BOM 保存；`param()` 必须放文件最前，帮助注释块移到其后 |

### 编码约定（务必保持）

| 文件 | 编码 / 换行 |
|------|------|
| `bootstrap.ps1` | **纯 ASCII、无 BOM**（`irm \| iex` 场景下 PS 5.1 按 ANSI 解码 HTTP 文本，中文会乱码） |
| `bootstrap-core.ps1` / `setup.ps1` / `uninstall.ps1` | **UTF-8 with BOM + CRLF** |
| `README.md` 及其他 `.md` / `.json` | **无 BOM + CRLF** |

### 令牌安全

- 令牌只通过 `$env:GITEE_TOKEN` / `-Token` / `-TokenFile` 传入，**绝不写进脚本、绝不提交到仓库**。
- 一旦在聊天、日志或截图里出现过，**立即到 Gitee → 设置 → 私人令牌 作废并重新生成**。

### 发布检查清单

- [ ] 代码 + 文档一起改完 → 提交 → 推送
- [ ] 版本号 4 处同步（`bootstrap.ps1` / `build_release_zip.ps1` / `publish_gitee_release.ps1` / `README.md`）
- [ ] tag 前移，且 `git ls-remote --tags --refs` 核实远端已更新
- [ ] `publish_gitee_release.ps1` 跑完且 `SCRIPT_RC=0`
- [ ] 匿名 `releases/latest` 能取到发布包资产
- [ ] 匿名下载为真 zip（魔数 `50 4B 03 04`，约 75MB）
- [ ] 收敛确认：`main` = tag = Release 资产，同一提交

---

## 🤝 贡献

欢迎提交 Issue 或 Pull Request。

## 📝 License

[MIT](./LICENSE) © 2026 PingWang
