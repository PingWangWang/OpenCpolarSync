# Openlist - 服务管理脚本集

> Windows 平台下 openlist 文件管理服务的启动、开机自启、任务管理辅助脚本

[![Version](https://img.shields.io/badge/version-1.0-blue)](RunOpenList.bat)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)]()

## 脚本说明

本目录包含四个 Windows 批处理/PowerShell 脚本，用于管理 `openlist.exe`（基于 Alist 的文件管理服务）的启动和自启配置。

### 脚本列表

| 脚本 | 用途 | 需要管理员权限 |
|------|------|:--------------:|
| `RunOpenList.bat` | 手动启动服务（后台静默运行） | 是 |
| `CreateTask.bat` | 创建 Windows 计划任务，实现开机自动启动 | 是 |
| `DeleteTask.bat` | 删除已创建的开机自启计划任务 | 是 |
| `StartOpenList.ps1` | PowerShell 启动脚本（被上述 .bat 调用） | - |

## 快速开始

### 手动启动

以管理员身份运行 `RunOpenList.bat`：

```
右键 -> 以管理员身份运行
```

启动后等待约 15 秒（网络和服务就绪），`openlist.exe` 将以隐藏窗口在后台运行。

### 设置开机自启

以管理员身份运行 `CreateTask.bat`，创建一个名为 **"OpenList Background Service"** 的计划任务，用户登录后延迟 12 秒自动启动服务。

```
右键 -> 以管理员身份运行 -> 任务创建成功！
```

### 移除自启

以管理员身份运行 `DeleteTask.bat`，删除已创建的 "OpenList Background Service" 计划任务。

## 脚本工作流程

```
RunOpenList.bat / CreateTask.bat
  +-> StartOpenList.ps1
       +-> 等待 15 秒（网络就绪）
       +-> 启动 openlist.exe server（隐藏窗口）
       +-> 检查进程是否存活
```

## 目录结构

```
Openlist/
+-- RunOpenList.bat           # 手动启动（需管理员）
+-- CreateTask.bat            # 创建开机自启任务（需管理员）
+-- DeleteTask.bat            # 删除开机自启任务（需管理员）
+-- StartOpenList.ps1         # PowerShell 启动脚本
+-- openlist.exe              # 文件管理服务程序
+-- data/
|   +-- config.json           # 服务配置
|   +-- data.db               # SQLite 数据库
|   +-- log/log.log           # 运行日志
|   +-- temp/                 # 临时文件目录
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
