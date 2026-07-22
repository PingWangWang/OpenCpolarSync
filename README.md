# OpenCpolarSync

> Windows 平台实用工具集：Cpolar 隧道状态监控 + openlist 文件管理服务管理

![GitHub](https://img.shields.io/badge/platform-Windows-lightgrey)
![License](https://img.shields.io/badge/License-MIT-blue)
![Version](https://img.shields.io/badge/version-1.1.0-orange)

## 项目简介

OpenCpolarSync 是一个面向 Windows 用户的实用工具集合，包含两个独立子项目：

| 子项目 | 用途 | 技术栈 |
|--------|------|--------|
| **[Cpolar](./Cpolar/)** | 自动监控 Cpolar 在线隧道状态，变更时通过钉钉 Webhook 推送通知 | Windows Batch / PowerShell |
| **[Openlist](./Openlist/)** | openlist（基于 Alist）文件管理服务的常驻守护、开机自启管理 | Windows Batch / PowerShell |

---

## 📦 快速导航

### [Cpolar 隧道状态同步 →](./Cpolar/)

适合使用 [Cpolar](https://www.cpolar.com) 内网穿透工具、需要实时获知隧道状态变更的开发者。

- `CpolarGuard.ps1` — 常驻守护脚本，轮询 Cpolar 后端 API，自动推送钉钉通知
- `AutoStart.bat` — 交互式菜单，添加/删除开机自启（UAC 提权 + shell:startup 快捷方式）
- **无需浏览器**，不依赖 Tampermonkey
- 智能去重，无变化不重复推送
- 日志按 ISO 周轮转归档

**安装方式**：编辑 `config.json` 填入 Webhook URL 和 Token，运行 `AutoStart.bat` 设置开机自启即可。

### [Openlist 服务管理 →](./Openlist/)

适合在 Windows 上使用 [Alist](https://github.com/AlistGo/alist) 文件管理服务、需要便捷启动和开机自启的用户。

- `OpenlistGuard.ps1` — 常驻守护脚本，60秒轮询监控进程，崩溃自动重启
- `AutoStart.bat` — 交互式菜单，添加/删除开机自启（UAC 提权 + shell:startup 快捷方式）
- 服务默认访问地址：`http://localhost:5244`

**安装方式**：下载后先解压 `archive/openlist.zip`，将 `openlist.exe` 放到 `Openlist/` 目录（与脚本同目录），详情见 [Openlist README](./Openlist/)。

---

## 📁 仓库结构

```
OpenCpolarSync/
├── Cpolar/                     # Cpolar 隧道状态监控（守护脚本）
│   ├── CpolarGuard.ps1         # 常驻守护脚本
│   ├── AutoStart.bat           # 开机自启管理
│   ├── config/                 # 配置与快照
│   ├── logs/                   # 运行日志（自动轮转）
│   ├── archive/                # 旧版油猴脚本等参考文件
│   ├── installer/              # Cpolar 安装包
│   └── README.md
├── Openlist/                   # openlist 服务管理脚本
│   ├── OpenlistGuard.ps1       # 常驻守护脚本（60秒轮询+自动重启）
│   ├── AutoStart.bat           # 开机自启管理（添加/删除）
│   ├── bin/                    # 可执行文件
│   ├── archive/                # 发布包
│   ├── data/                   # 配置、数据库、日志
│   ├── logs/                   # 守护脚本日志
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

- **Cpolar 监控**：Windows PowerShell 5.0+，拥有 Cpolar Web 管理界面权限（`localhost:9200`），已创建钉钉机器人 Webhook
- **Openlist 服务**：Windows 系统，管理员权限（用于守护脚本和开机自启管理）

## 🤝 贡献

欢迎提交 Issue 或 Pull Request。每个子项目有独立的 README，建议先阅读对应文档。

## 📝 License

[MIT](./LICENSE) © 2026 PingWang
