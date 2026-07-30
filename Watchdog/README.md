# Watchdog — 运行时保活看门狗

> Windows 计划任务驱动的巡检保活模块。当 CpolarGuard / OpenlistGuard 的 PowerShell 进程因系统异常、崩溃等原因退出时，自动检测并拉起，确保持续在线。

[![Version](https://img.shields.io/badge/version-1.0-blue)]()
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)]()
[![License](https://img.shields.io/badge/License-MIT-green)](../LICENSE)

## 设计背景

CpolarGuard 和 OpenlistGuard 都是 PowerShell 常驻进程。在 Windows 上长时间运行时，PowerShell 进程可能因系统资源紧张、会话回收、意外崩溃等原因被异常杀掉。

原有防护仅依赖 `shell:startup` 开机自启——只在用户登录时启动一次，**运行中若进程退出，没有任何恢复机制**。

Watchdog 模块填补了这一空白：用 Windows 内置的 **Task Scheduler（计划任务）** 作为外部看门狗，巡检 Mutex 判定 guard 是否存活，死则拉起。

---

## 快速开始

```batch
cd watchdog
WatchdogManager.bat

# 或命令行一键配置全部
WatchdogManager.bat setup all
```

运行后，依次完成：

1. 注册开机自启（Cpolar + Openlist 的 `shell:startup` 快捷方式）
2. 注册计划任务（每 5 分钟巡检一次）

之后每次登录，guard 自动启动；运行中若进程意外退出，**最多 5 分钟** 内自动恢复。

---

## 文件说明

| 文件 | 用途 |
|------|------|
| `GuardCheck.ps1` | 通用巡检脚本，通过 Mutex 判活，参数化设计一份脚本服务两个模块 |
| `WatchdogManager.bat` | 统一管理入口，交互菜单 + 命令行两种模式 |
| `README.md` | 本文件 |

### GuardCheck.ps1

**调用方式**（由计划任务触发，用户无需手动运行）：

```powershell
powershell -ExecutionPolicy Bypass -File GuardCheck.ps1 `
  -GuardName "Cpolar" `
  -MutexName "Global\CpolarGuard-{B4C8D2E3-5F6A-7B8C-9D0E-1F2A3B4C5D6E}" `
  -GuardScriptPath "C:\...\CpolarGuard.ps1" `
  -LogPath "C:\...\watchdog.log"
```

| 参数 | 说明 |
|------|------|
| `-GuardName` | 模块标识，用于日志（Cpolar / Openlist） |
| `-MutexName` | 对应 guard 脚本中定义的 Global Mutex 名称 |
| `-GuardScriptPath` | guard 脚本的完整路径 |
| `-LogPath` | watchdog 日志文件路径 |

**执行逻辑**：

```
① 尝试创建同名 Global Mutex
  ├─ 创建成功（guard 已退出）→ 写 RESTART 日志 → Start-Process 拉起 guard
  └─ 创建失败（guard 正常运行）→ 静默退出，不写日志避免噪声
② 无论分支，退出前 Dispose() 释放 Mutex 句柄
```

### WatchdogManager.bat

**交互菜单模式**（无参数运行）：

```
====================================
  OpenCpolarSync 看门狗管理
====================================
  1. 一键配置全部（Cpolar + Openlist）
  2. 一键移除全部
  3. 仅配置 Cpolar（开机自启 + 保活）
  4. 仅移除 Cpolar
  5. 仅配置 Openlist（开机自启 + 保活）
  6. 仅移除 Openlist
  7. 查看状态
====================================
请选择 (1-7):
```

**命令行模式**：

```batch
WatchdogManager.bat setup [Cpolar|Openlist|all]
WatchdogManager.bat teardown [Cpolar|Openlist|all]
WatchdogManager.bat status

# 示例
WatchdogManager.bat setup all         # 一键配置全部
WatchdogManager.bat teardown Openlist  # 仅移除 Openlist
WatchdogManager.bat status             # 查看状态
```

---

## 工作原理

```
┌───────────────────────────────────────────────┐
│             Task Scheduler（OS 核心组件）      │
│  OpenCpolarSync_CpolarGuard_Watchdog          │
│  触发器: 首次启动后 1 分钟 → 每 5 分钟重复    │
└───────────────────┬───────────────────────────┘
                    │ 系统触发
                    ▼
┌───────────────────────────────────────────────┐
│           powershell.exe GuardCheck.ps1       │
│           -GuardName Cpolar ...               │
└───────────────────┬───────────────────────────┘
                    │
          ┌─────────┴──────────┐
          │  Mutex 判活        │
          │  ($createdNew?)    │
          ├─────────┬──────────┤
          │ YES     │ NO       │
          │(guard死)│(guard活) │
          ▼         ▼
    Start-Process    静默
    CpolarGuard.ps1  exit 0
          │
          ▼
    watchdog.log
    [RESTART] CpolarGuard 已拉起 (PID=1234)
```

### 双引号/路径容错

注册计划任务时，路径参数使用 **反引号转义双引号**（`` `\" ``）包裹，确保即使仓库安装在带空格的路径下（如 `C:\My Files\OpenCpolarSync\`），Task Scheduler 也能正确解析参数。

---

## 查看状态

```powershell
# 计划任务状态
WatchdogManager.bat status

# 或直接通过 PowerShell 查看
Get-ScheduledTask -TaskName "OpenCpolarSync_*_Watchdog" | Select-Object State,NextRunTime

# 查看恢复日志
Get-Content .\watchdog.log

# 查看最近 5 条恢复记录
Get-Content .\watchdog.log -Tail 5
```

**状态输出示例**：

```
====================================
  Watchdog 状态
====================================

[计划任务]
  [*] OpenCpolarSync_CpolarGuard_Watchdog  — 已注册
  [*] OpenCpolarSync_OpenlistGuard_Watchdog — 已注册

[Guard 进程]
  [*] CpolarGuard   — 运行中
  [*] OpenlistGuard — 运行中

[恢复日志] (C:\...\watchdog.log)
  2026-07-30 10:06:06 [RESTART] CpolarGuard 不在运行，正在尝试拉起...
  2026-07-30 10:06:08 [RESTART] CpolarGuard 已拉起 (PID=1234)
```

---

## 卸载

```batch
WatchdogManager.bat teardown all
```

此操作会：
1. 移除 shell:startup 开机自启快捷方式
2. 删除 Windows 计划任务

---

## 从旧版本升级

如果您之前使用 `AutoStart.bat` 单独配置了开机自启，建议运行 `WatchdogManager.bat teardown all` 清理旧配置，再用 `WatchdogManager.bat setup all` 重新配置。

---

## 目录结构

```
OpenCpolarSync/
├── watchdog/                    # ← 本模块
│   ├── GuardCheck.ps1          # 通用巡检脚本
│   ├── WatchdogManager.bat     # 统一管理入口
│   ├── watchdog.log            # 恢复日志（自动生成）
│   └── README.md               # 本文件
├── Cpolar/                     # Cpolar 隧道监控
├── Openlist/                   # Openlist 服务管理
└── README.md                   # 项目总览
```

## 📝 License

[MIT](../LICENSE)
