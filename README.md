# OpenCpolarSync

> Windows 平台实用工具集：Cpolar 隧道状态监控 + openlist 文件管理服务 + 运行时保活看门狗

![GitHub](https://img.shields.io/badge/platform-Windows-lightgrey)
![License](https://img.shields.io/badge/License-MIT-blue)
![Version](https://img.shields.io/badge/version-1.2.0-orange)

## 项目简介

OpenCpolarSync 是一个面向 Windows 用户的实用工具集合，包含三个独立子模块：

| 子模块 | 用途 | 技术栈 |
|--------|------|--------|
| **[Cpolar](./Cpolar/)** | 自动监控 Cpolar 在线隧道状态，变更时通过钉钉 Webhook 推送通知 | Windows Batch / PowerShell |
| **[Openlist](./Openlist/)** | openlist（基于 Alist）文件管理服务的常驻守护、开机自启管理 | Windows Batch / PowerShell |
| **[Watchdog](./Watchdog/)** | 运行时保活看门狗，Guard 进程异常退出时自动拉起 | Windows Batch / PowerShell |

> **新用户请直接看 [一键部署](#-一键部署推荐)** —— 原本需要手工完成的 6 个步骤，现在一条命令即可。

---

## 🚀 一键部署（推荐）

### 方式 A：免 clone，一条命令

在 **Windows PowerShell** 中粘贴执行（无需安装 git，无需手动 clone）。

**国内网络（GitHub 不通）优先用 Gitee 镜像获取启动器：**

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
irm https://gitee.com/pingwang1994/OpenCpolarSync/raw/main/bootstrap.ps1 | iex
```

GitHub 源（默认会自动回退 Gitee 下载，因此即使从 GitHub 获取本脚本也能跑通）：

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
irm https://raw.githubusercontent.com/PingWangWang/OpenCpolarSync/main/bootstrap.ps1 | iex
```

> **提示 1：为什么要先执行那一行 `Tls12`？**  
> Windows PowerShell 5.1（系统预装版）默认只启用 `Ssl3|Tls`，而 Gitee raw 会 302 跳转到 `raw.giteeusercontent.com` CDN，该 CDN 要求 TLS 1.2+。若不先开 TLS 1.2，`irm` 会在建立连接阶段报 `基础连接已经关闭: 发送时发生错误`。这一行只需执行一次（在当前 PowerShell 窗口生效），之后再跑 `irm ... | iex` 就无需重复。
>
> **提示 2：**`bootstrap.ps1` 保存为**无 BOM 的 UTF-8**，正是为了让 `irm | iex` 在系统预装的 Windows PowerShell 5.1 下也能正确解析（带 BOM 会导致注释块失效、中文被当作语句而报错）。已 clone 仓库时请直接运行 `setup.ps1`（见方式 B）。

### 方式 B：已 clone 仓库

```powershell
.\setup.ps1
```

### 先演练、不落盘

`-DryRun` 只打印执行计划，不做任何安装 / 注册 / 写入操作：

```powershell
.\setup.ps1 -DryRun
```

### 无人值守部署

全部配置通过参数传入，不弹任何交互提示：

```powershell
.\setup.ps1 -Silent `
    -WebhookUrl 'https://oapi.dingtalk.com/robot/send?access_token=xxx' `
    -CpolarUser 'you@example.com' `
    -CpolarPassword 'your-password' `
    -TunnelNames 'OpenListHC'
```

### 一键部署到底做了什么

| 阶段 | 自动完成的动作 | 替代的原手工步骤 |
|------|----------------|------------------|
| 1 | 检测 Cpolar 客户端，未安装则静默安装仓库自带的 `cpolar_amd64.msi` | 手动安装 msi |
| 2 | 从 `archive/openlist.zip` 自动解压 `openlist.exe` 到 `Openlist/` | 手动解压（隐含步骤） |
| 3 | 交互式收集配置，隧道名等带默认值，直接回车即可 | 手动编辑 config.json |
| 4 | 生成 `config.json` 并持久化到用户目录（升级不丢失） | 手动编辑 config.json |
| 5 | 写入 `cpolar.yml` 并注册 authtoken，自动创建内网穿透隧道 | Web 端手动建隧道 |
| 6 | 注册 Watchdog S4U 计划任务，并立即拉起两个 Guard | 手动执行 WatchdogManager |

### 仍需人工的一步

**Openlist 存储挂载**需要你在 Web 界面完成。脚本会自动打开 `http://localhost:5244` 并打印步骤清单。

原因是 openlist 的挂载配置保存在它自己的数据库里，跨版本格式不稳定，脚本强写反而容易损坏配置，因此这里只做引导 + 端口/进程校验。

### 配置文件存在哪里

- **主副本**：`%LOCALAPPDATA%\OpenCpolarSync\config\config.json` —— 位于程序目录之外，重新运行 `bootstrap.ps1` 升级程序时不会被覆盖
- **运行副本**：`Cpolar\config\config.json` —— 每次运行 `setup.ps1` 自动从主副本同步，`CpolarGuard` 与 Watchdog 无需改造即可读到最新配置

---

## 📦 模块详情（手动部署）

一键部署已覆盖以下全部内容。若你想了解内部实现或需要单独部署某个模块，可继续阅读。

### [Cpolar 隧道状态同步 →](./Cpolar/)

适合使用 [Cpolar](https://www.cpolar.com) 内网穿透工具、需要实时获知隧道状态变更的开发者。

- `CpolarGuard.ps1` — 常驻守护脚本，轮询 Cpolar 后端 API，自动推送钉钉通知
- `AutoStart.bat` — 交互式菜单，添加/删除开机自启（UAC 提权 + shell:startup 快捷方式，支持命令行静默模式）
- **无需浏览器**，不依赖 Tampermonkey
- 用户名密码自动登录，Token 过期自动重新登录
- 智能去重，无变化不重复推送；配置变更热重载
- 日志按 ISO 周轮转归档

**手动安装方式**：参考 `Cpolar/config/config.example.json` 创建 `config.json`，填入 Webhook URL 和 Cpolar 登录邮箱/密码（脚本自动登录），运行 `AutoStart.bat` 设置开机自启即可。

### [Openlist 服务管理 →](./Openlist/)

适合在 Windows 上使用 [Alist](https://github.com/AlistGo/alist) 文件管理服务、需要便捷启动和开机自启的用户。

- `OpenlistGuard.ps1` — 常驻守护脚本，60秒轮询监控进程，崩溃自动重启
- `AutoStart.bat` — 交互式菜单，添加/删除开机自启（UAC 提权 + shell:startup 快捷方式，支持命令行静默模式）
- 服务默认访问地址：`http://localhost:5244`

**手动安装方式**：手动解压 `archive/openlist.zip`，将 `openlist.exe` 放到 `Openlist/` 目录（与脚本同目录），详情见 [Openlist README](./Openlist/)。

### [Watchdog 看门狗 →](./Watchdog/)

适合所有需要 **运行时保活** 的用户。当 CpolarGuard / OpenlistGuard 的 PowerShell 进程异常退出时自动拉起，确保持续在线。

- `GuardCheck.ps1` — 通用巡检脚本，通过 Mutex 判活，参数化设计一份脚本服务两个模块
- `WatchdogManager.bat` — 统一管理入口，一键配置（清理旧开机自启 + S4U 计划任务运行时保活）
- **零第三方依赖** — 完全利用 Windows 内置 Task Scheduler
- **S4U 非交互运行** — 任务在 Session 0 执行，无控制台弹窗，注销/未登录时保活依然生效
- **容错路径** — 支持仓库安装在带空格的目录下

**手动安装方式**：以管理员身份运行 `Watchdog\WatchdogManager.bat`，选 `1` 一键配置全部（清理旧开机自启 + 注册 S4U 计划任务）即可。

---

## 📁 仓库结构

```
OpenCpolarSync/
├── setup.ps1                   # 一键部署向导（6 阶段，支持 -DryRun / -Silent）
├── bootstrap.ps1               # 免 clone 启动器（GitHub / Gitee / 本地三源）
├── docs/                       # 设计文档
│   └── OneClick-Deploy-Design.md
├── Watchdog/                   # 运行时保活看门狗
│   ├── GuardCheck.ps1          # 通用巡检脚本（Task Scheduler 触发）
│   ├── WatchdogManager.bat     # 统一管理入口（安装/卸载/状态）
│   ├── README.md               # 看门狗说明文档
│   └── watchdog.log            # 恢复日志（自动生成，已忽略）
├── Cpolar/                     # Cpolar 隧道状态监控（守护脚本）
│   ├── CpolarGuard.ps1         # 常驻守护脚本（新增 -ConfigPath 参数）
│   ├── AutoStart.bat           # 开机自启管理
│   ├── config/                 # 配置与快照
│   │   ├── config.example.json # 配置模板（不含敏感信息，纳入版本控制）
│   │   └── config.json         # 运行时生成，含明文密码，已忽略
│   ├── logs/                   # 运行日志（自动轮转，已忽略）
│   ├── archive/                # 旧版油猴脚本等参考文件
│   ├── installer/              # Cpolar 安装包
│   └── README.md
├── Openlist/                   # openlist 服务管理脚本
│   ├── OpenlistGuard.ps1       # 常驻守护脚本（60秒轮询+自动重启）
│   ├── AutoStart.bat           # 开机自启管理（添加/删除）
│   ├── openlist.exe            # 文件管理服务程序（自动解压，已忽略）
│   ├── archive/                # 发布包
│   ├── data/                   # 配置、数据库、日志（已忽略）
│   ├── logs/                   # 守护脚本日志（已忽略）
│   └── README.md
├── LICENSE                     # MIT License
└── README.md                   # 本文件
```

---

## ❓ 适用场景

- **内网穿透运维** — 通过 Cpolar 暴露本地服务后，需要实时监控隧道状态并推送到钉钉群
- **团队协作** — 多人共用一个 Cpolar 账号，通过钉钉机器人同步隧道变更
- **Windows 文件管理** — 在 Windows 上部署 Alist 文件管理服务，需要便捷的启动和开机自启方案

## 前置条件

- **一键部署**：Windows 7 SP1+ / PowerShell 5.0+；**已在 Windows PowerShell 5.1.26100（系统预装版）与 PowerShell 7.6.4 双版本实测通过**，注册计划任务需管理员权限
- **Cpolar 监控**：拥有 Cpolar 账号与钉钉机器人 Webhook
- **Openlist 服务**：守护脚本无需管理员权限；`AutoStart.bat` 自启管理需要
- **Watchdog 看门狗**：管理员权限（用于注册计划任务）

## ⚠️ 注意事项

1. **`config.json` 含明文密码，已从版本控制中忽略**。若你的本地仓库此前提交过该文件，需要执行以下命令才能真正生效（文件本身保留在本地）：

   ```bash
   git rm --cached Cpolar/config/config.json Cpolar/config/last-sent.json
   ```

2. **cpolar.yml 的字段写法** 是依据 `cpolar --help` 推导的，首次实机运行后请确认隧道确实建立成功。

3. **升级程序不会丢失配置**：重新运行 `bootstrap.ps1` 时，配置主副本位于 `%LOCALAPPDATA%\OpenCpolarSync\config`，不在程序解压目录内。

4. **脚本必须保持 UTF-8 with BOM**：Windows PowerShell 5.1 会按系统 ANSI 代码页（简体中文为 GBK）解析**无 BOM** 的 UTF-8 脚本，中文会损坏并直接导致语法错误。修改脚本时请勿丢掉 BOM。

## 🤝 贡献

欢迎提交 Issue 或 Pull Request。每个子项目有独立的 README，建议先阅读对应文档。

## 📝 License

[MIT](./LICENSE) © 2026 PingWang
