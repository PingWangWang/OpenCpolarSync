# Openlist - 服务管理脚本集

> Windows 平台下 openlist 文件管理服务的启动守护、开机自启管理脚本

[![Version](https://img.shields.io/badge/version-2.0-blue)](OpenlistGuard.ps1)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)]()

## 脚本说明

本目录包含守护脚本和自启管理脚本，用于管理 `openlist.exe`（基于 Alist 的文件管理服务）的后台常驻运行。

### 脚本列表

| 脚本 | 用途 | 权限 |
|------|------|:----:|
| `OpenlistGuard.ps1` | 常驻守护脚本，60 秒轮询监控进程崩溃自动重启，日志按 ISO 周轮转归档 | - |
| `AutoStart.bat` | 交互式菜单，添加/删除开机自启（UAC 提权 + shell:startup 快捷方式） | UAC 提权 |

## 守护方案（OpenlistGuard）

`OpenlistGuard.ps1` 替代了旧版一次性启动脚本，提供进程崩溃自动恢复能力：

- **轮询周期**：每 60 秒检测 `openlist.exe` 进程是否存在
- **崩溃恢复**：进程意外退出后自动重启，无需人工干预
- **日志轮转**：日志文件按 ISO 8601 周编号（如 `guard-2025-W14.log`）归档，保留最近 4 周
- **窗口隐藏**：通过 `Add-Type` + `ShowWindow` 内部隐藏窗口，避免触发 AV 行为检测

### 手动启动守护

```powershell
# 在 Openlist 目录下执行
powershell -ExecutionPolicy Bypass -File OpenlistGuard.ps1
```

或直接双击 `OpenlistGuard.ps1`（如果 PowerShell 执行策略允许）。

## 开机自启管理（AutoStart）

`AutoStart.bat` 合并了旧版安装/删除两个独立脚本，通过交互式菜单操作：

```
AutoStart.bat
  ├── [1] 添加开机自启  → 创建快捷方式到 shell:startup
  └── [2] 删除开机自启  → 从 shell:startup 移除快捷方式
```

- 启动时自动检测管理员权限，非管理员通过 UAC RunAs 提权重启
- 添加自启：创建指向 `OpenlistGuard.ps1` 的快捷方式到 `shell:startup`
- 删除自启：从 `shell:startup` 移除对应快捷方式

## 快速开始

### 首次设置

```
1. 双击 AutoStart.bat
2. 输入 1 → 添加开机自启
3. OpenlistGuard 将在下次登录时自动启动
```

### 手动启动

以管理员身份运行 `OpenlistGuard.ps1`，或通过 `AutoStart.bat` 设置自启后重启即可。

## 目录结构

```
Openlist/
+-- OpenlistGuard.ps1         # 常驻守护脚本（60秒轮询 + 自动重启）
+-- AutoStart.bat             # 开机自启管理（添加/删除）
+-- openlist.exe              # 文件管理服务程序
+-- openlist.zip              # 发布压缩包
+-- data/
|   +-- config.json           # 服务配置
|   +-- data.db               # SQLite 数据库
|   +-- log/log.log           # 运行日志
|   +-- temp/                 # 临时文件目录
+-- guard-*.log               # OpenlistGuard 运行日志（自动轮转）
+-- README.md
```

## 关于 openlist

`openlist.exe` 是一个基于 [Alist](https://github.com/AlistGo/alist) 的文件管理 Web 服务，提供：

- Web 界面文件管理（上传/下载/浏览）
- 多协议支持（FTP / SFTP / S3）
- 离线下载（115 网盘 / PikPak / 迅雷 等）
- 多用户权限管理

访问地址：`http://localhost:5244`，默认账号 `admin`。

## 关联项目

- **[Cpolar](../Cpolar/)** - 同一仓库下的 Cpolar 隧道状态监控 Tampermonkey 脚本。
