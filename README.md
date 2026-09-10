# OpenCpolarSync

> Windows 平台：Cpolar 隧道状态监控 + Openlist 文件服务守护 + 运行时保活看门狗，支持一键部署与一键卸载

![GitHub](https://img.shields.io/badge/platform-Windows-lightgrey)
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
irm https://github.com/PingWangWang/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 | iex
```

启动后会先询问操作类型：

```
  请选择操作：
    1. 安装 / 更新 OpenCpolarSync
    2. 卸载 OpenCpolarSync
```

选 `1` 即可进入安装向导，按提示输入配置即可。

**国内网络备选（Gitee 镜像）：**

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
irm https://gitee.com/pingwang1994/OpenCpolarSync/raw/main/bootstrap.ps1 | iex
```

### 一键卸载

同样的命令，选 `2` 即可：

```powershell
irm https://github.com/PingWangWang/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 | iex
# 选择 2. 卸载
```

卸载流程会自动完成：
1. 停止 openlist / cpolar 进程及守护进程
2. 移除 Watchdog 计划任务
3. 删除程序目录（自动重试，应对文件被占用）
4. 可选删除配置文件（含密码、Webhook 等）
5. 可选卸载 Cpolar 客户端

### 强制更新（重新下载程序文件）

默认情况下，检测到已安装会跳过下载。如需强制重新下载最新程序文件，需先下载脚本再带参数运行：

```powershell
# 下载到本地
irm https://github.com/PingWangWang/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1

# 带 -Force 参数运行（强制重新下载程序文件）
& $env:TEMP\bootstrap.ps1 -Force
```

> **注意**：`irm ... | iex` 这种管道方式无法传递参数，必须先下载到本地再运行。

### 直接卸载（跳过选择菜单）

```powershell
irm https://github.com/PingWangWang/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1
& $env:TEMP\bootstrap.ps1 -Uninstall
```

---

## 📋 命令参数大全

### bootstrap.ps1 参数

| 参数 | 说明 |
|------|------|
| `-Force` | 强制重新下载程序文件（跳过已安装检测） |
| `-Uninstall` | 直接进入卸载模式，跳过选择菜单 |
| `-Source GitHub/Gitee/Local` | 下载来源，默认 GitHub |
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

一键部署自动完成以下步骤：

| 阶段 | 动作 |
|------|------|
| 1 | 检测 Cpolar 客户端，未安装则自动从官网下载并静默安装 |
| 2 | 解压 openlist.exe 到程序目录 |
| 3 | 交互式收集配置（Webhook、邮箱、密码、隧道名等，**当前值会回显**） |
| 4 | 生成 config.json 并持久化到用户目录（升级不丢失） |
| 5 | 写入 cpolar.yml 隧道配置 |
| 6 | 注册 Watchdog S4U 计划任务，拉起两个守护进程 |

### 仍需手动完成的一步

**Openlist 存储挂载**需要在 Web 界面完成：
1. 浏览器打开 `http://localhost:5244`
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
irm https://github.com/PingWangWang/OpenCpolarSync/releases/download/v1.1.15/bootstrap.ps1 -OutFile $env:TEMP\bootstrap.ps1
& $env:TEMP\bootstrap.ps1 -Force
```

### Q: 卸载时提示文件被占用？

卸载脚本会自动重试 3 次。如仍失败，重启电脑后手动删除 `%LOCALAPPDATA%\OpenCpolarSync\app` 目录即可。

### Q: Cpolar 安装包找不到？

最新版 setup.ps1 会在本地 msi 不存在时自动从 cpolar 官网下载。如下载失败，请手动安装 Cpolar 后重试：https://www.cpolar.com/download

### Q: 配置会在升级时丢失吗？

不会。配置文件保存在 `%LOCALAPPDATA%\OpenCpolarSync\config`，位于程序目录之外。

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

## 🤝 贡献

欢迎提交 Issue 或 Pull Request。

## 📝 License

[MIT](./LICENSE) © 2026 PingWang
