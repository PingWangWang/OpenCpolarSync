# OpenCpolarSync

> Windows 桌面工具：Cpolar 隧道状态监控 + Openlist 文件服务进程守护，WPF 一体化安装版

![Platform](https://img.shields.io/badge/platform-Windows%207%20SP1%2B-lightgrey)
![License](https://img.shields.io/badge/License-MIT-blue)
![Version](https://img.shields.io/badge/version-1.1.29-orange)
![.NET](https://img.shields.io/badge/.NET-Framework%204.8-blueviolet)

## 项目简介

OpenCpolarSync 是一个面向 Windows 用户的桌面工具，将 **Cpolar 隧道监控** 和 **Openlist 文件服务守护** 整合为一个 WPF 应用，提供图形化配置、实时状态展示、Web 管理内嵌和系统托盘保活。

| 功能 | 说明 |
|------|------|
| **Cpolar 隧道监控** | 自动登录 Cpolar Web API，轮询隧道状态，检测上线/离线/变更，通过钉钉机器人实时推送 |
| **Openlist 进程守护** | 60 秒轮询 openlist.exe 进程，崩溃后自动以 `server` 参数重启 |
| **图形化配置** | 内置配置表单（Webhook、轮询间隔、隧道名、账号密码等），支持校验和热重载 |
| **Web 管理内嵌** | 通过 WebView2 内嵌 Cpolar（localhost:9200）和 Openlist（localhost:5244）管理界面，Win7 无 Runtime 时自动降级为外部浏览器 |
| **系统托盘** | 关闭主窗口自动最小化到托盘，右键菜单支持启动/停止守护、打开 Web 管理、退出 |
| **一键安装** | Inno Setup 安装包集成 cpolar MSI 静默安装和 openlist 绿色包解压，检测已安装状态避免重复安装 |

---

## 快速开始

### 环境要求

- Windows 7 SP1 / 8.1 / 10 / 11
- .NET Framework 4.8（Win7 需手动安装，Win10 1803+ 自带）
- WebView2 Runtime（Win10 1803+ 自带，Win7 需单独安装；未安装时自动降级为外部浏览器）
- Visual Studio 2022（编译用，MSBuild 17.x）

### 编译

```powershell
# Debug 编译
.\scripts\build-debug.ps1

# Release 编译
.\scripts\build-release.ps1
```

编译输出位于 `src\OpenCpolarSync.Client\bin\{Debug|Release}\`。

### 打包安装程序

```powershell
# 需先完成 Release 编译，并安装 Inno Setup 6.x
.\scripts\package.ps1
```

安装包输出位于 `installer\Output\OpenCpolarSync-Setup_1.1.29.exe`。

### 运行

编译后直接运行 `OpenCpolarSync.exe`，或通过安装包安装后从开始菜单/桌面快捷方式启动。

首次运行需在「Cpolar 配置」Tab 中填写钉钉 Webhook、Cpolar 登录账号等信息，保存后点击「启动全部守护」。

---

## 项目结构

```
OpenCpolarSync/
├── src/                              # WPF 源码
│   ├── OpenCpolarSync.Client.sln     # 解决方案
│   └── OpenCpolarSync.Client/        # WPF 项目（.NET Framework 4.8）
│       ├── App.xaml / .cs             # 应用入口（单实例 Mutex + 全局异常）
│       ├── MainWindow.xaml / .cs      # 主窗口（4 Tab + 托盘 + 关于）
│       ├── Models/                     # 数据模型
│       │   ├── CpolarConfig.cs         # 配置模型（JSON 序列化）
│       │   ├── TunnelInfo.cs           # 隧道信息模型
│       │   └── ServiceStatus.cs        # 服务状态枚举 + 事件参数
│       ├── Services/                   # 核心业务服务
│       │   ├── GuardService.cs         # 统一调度（Cpolar + Openlist + 钉钉推送）
│       │   ├── CpolarMonitor.cs        # Cpolar API 监控（JWT 登录 + 隧道轮询 + 变更检测）
│       │   ├── OpenlistMonitor.cs      # Openlist 进程守护（60s 轮询 + 崩溃重启）
│       │   ├── ConfigService.cs        # 配置读写 + 校验 + 热重载
│       │   ├── DingTalkService.cs      # 钉钉机器人 Markdown 推送
│       │   └── InstallDetectionService.cs  # cpolar/openlist/WebView2 安装检测
│       ├── Components/                 # UI 组件
│       │   ├── TrayIcon.cs             # 系统托盘（Hardcodet.NotifyIcon）
│       │   └── WebView2Manager.cs      # WebView2 初始化 + Win7 降级
│       ├── ViewModels/                 # 视图模型
│       │   ├── MainViewModel.cs
│       │   ├── DashboardViewModel.cs
│       │   └── CpolarConfigViewModel.cs
│       └── Views/                      # 页面视图
│           ├── DashboardTab.xaml / .cs      # 总览（服务状态 + 快捷操作）
│           ├── CpolarConfigTab.xaml / .cs   # Cpolar 配置表单 + Web 管理入口
│           ├── OpenlistTab.xaml / .cs       # Openlist Web 管理（WebView2 内嵌）
│           ├── LogsTab.xaml / .cs           # 运行日志查看
│           └── AboutWindow.xaml / .cs       # 关于对话框（版本 + 功能介绍）
├── scripts/                          # 编译/打包脚本
│   ├── build-debug.ps1                # Debug 编译（环境检查 + 还原 + 编译）
│   ├── build-release.ps1              # Release 编译（环境检查 + 清理 + 还原 + 编译）
│   └── package.ps1                    # 安装包打包（环境检查 + ISCC 编译）
├── installer/                        # 安装包
│   └── setup.iss                      # Inno Setup 脚本（集成 cpolar MSI + openlist.zip）
├── docs/                             # 设计文档
│   └── WPF-Installer-Design.md       # WPF 安装版设计方案（方案对比 + 模块划分）
├── legacy/                           # 旧版项目归档（PowerShell / Batch 脚本）
│   ├── Cpolar/                        # 旧版 Cpolar 模块
│   ├── Openlist/                      # 旧版 Openlist 模块
│   ├── Watchdog/                      # 旧版 Watchdog 保活模块
│   ├── scripts/                       # 旧版守护脚本（6 个 .ps1/.bat）
│   └── README.md                      # 归档说明
├── LICENSE
└── README.md                          # 本文件
```

---

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | .NET Framework 4.8 |
| UI | WPF (XAML + MVVM 轻量模式) |
| 内嵌浏览器 | Microsoft.Web.WebView2 |
| 系统托盘 | Hardcodet.NotifyIcon.Wpf |
| JSON | Newtonsoft.Json |
| HTTP | System.Net.Http (HttpClient) |
| 安装包 | Inno Setup 6.x |
| 构建脚本 | PowerShell 5.1+ |

---

## 核心流程

### Cpolar 隧道监控

```
启动守护 → 自动登录 Cpolar API（邮箱+密码 → JWT Token）
        → 按配置间隔轮询 /api/v1/tunnels
        → 筛选勾选的隧道，复合键(name|protocol)比对上次快照
        → 检测到变更（新增/更新/重连/离线）→ 构建 Markdown 消息 → 钉钉推送
        → Token 过期自动重新登录
```

### Openlist 进程守护

```
启动守护 → 检查 openlist.exe 进程 → 未运行则以 `server` 参数启动
        → 每 60 秒轮询进程状态 → 进程消失则自动重启
        → 重启后等待 15 秒确认存活
```

### 安装流程

```
运行安装包 → 检测 cpolar 是否已安装（注册表+默认路径）
          → 未安装则静默执行 cpolar_amd64.msi
          → 解压 openlist.zip 到安装目录
          → 复制主程序及依赖、默认 config.json
          → 创建开始菜单/桌面快捷方式（可选）
          → 可选注册开机自启
          → 安装完成后可选启动主程序
```

---

## 旧版说明

项目早期由三个独立的 PowerShell / Batch 脚本模块组成（CpolarGuard、OpenlistGuard、Watchdog），现已全部用 C# 重写并整合为 WPF 桌面应用。

旧版脚本及资源文件统一归档在 [`legacy/`](./legacy/) 目录下，仅供参考和回退使用，不再主动维护。详见 [legacy/README.md](./legacy/README.md)。

---

## 适用场景

- **内网穿透运维** — 通过 Cpolar 暴露本地服务，需要实时监控隧道状态并推送到钉钉群
- **家庭/小型团队文件服务** — 在 Windows 上部署 Openlist/Alist 文件管理，需要进程保活和便捷管理
- **一体化运维工具** — 希望用一个图形化工具同时管理隧道监控和文件服务，避免多个脚本窗口

---

## 贡献

欢迎提交 Issue 或 Pull Request。设计方案详见 [`docs/WPF-Installer-Design.md`](./docs/WPF-Installer-Design.md)。

## License

[MIT](./LICENSE) © 2026 PingWang
