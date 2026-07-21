# OpenCpolarSync

> Windows 平台实用工具集：Cpolar 隧道状态监控 + openlist 文件管理服务管理

![GitHub](https://img.shields.io/badge/platform-Windows-lightgrey)
![License](https://img.shields.io/badge/License-MIT-blue)
![Version](https://img.shields.io/badge/version-1.1.0-orange)

## 项目简介

OpenCpolarSync 是一个面向 Windows 用户的实用工具集合，包含两个独立子项目：

| 子项目 | 用途 | 技术栈 |
|--------|------|--------|
| **[Cpolar](./Cpolar/)** | 自动监控 Cpolar 在线隧道状态，变更时通过钉钉 Webhook 推送通知 | Tampermonkey 油猴脚本 |
| **[Openlist](./Openlist/)** | openlist（基于 Alist）文件管理服务的启动、开机自启、任务管理辅助脚本 | Windows Batch / PowerShell |

---

## 📦 快速导航

### [Cpolar 隧道状态同步 →](./Cpolar/)

适合使用 [Cpolar](https://www.cpolar.com) 内网穿透工具、需要实时获知隧道状态变更的开发者。

- 定时轮询 Cpolar 在线隧道列表，检测新增/离线/信息变更
- 通过钉钉机器人 Webhook 发送 Markdown 通知
- 支持手动预览推送内容、强制发送
- 智能去重，无变化不重复推送
- 页面刷新后自动恢复监控状态

**安装方式**：Tampermonkey / Violentmonkey 脚本，粘贴 `cpolar-sync.user.js` 代码即可。

### [Openlist 服务管理 →](./Openlist/)

适合在 Windows 上使用 [Alist](https://github.com/AlistGo/alist) 文件管理服务、需要便捷启动和开机自启的用户。

- `RunOpenList.bat` — 一键后台静默启动服务
- `CreateTask.bat` — 创建 Windows 计划任务，实现开机自启
- `DeleteTask.bat` — 删除自启任务
- 服务默认访问地址：`http://localhost:5244`

---

## 📁 仓库结构

```
OpenCpolarSync/
├── Cpolar/                     # Cpolar 隧道状态同步（油猴脚本）
│   ├── cpolar-sync.user.js     # 主脚本（89KB）
│   ├── cpolar-sync.meta.js     # 脚本元数据
│   └── README.md
├── Openlist/                   # openlist 服务管理脚本
│   ├── RunOpenList.bat         # 手动启动
│   ├── CreateTask.bat          # 创建开机自启任务
│   ├── DeleteTask.bat          # 删除自启任务
│   ├── StartOpenList.ps1       # PowerShell 启动脚本
│   ├── openlist.exe            # 文件管理服务程序
│   ├── data/                   # 配置、数据库、日志
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

- **Cpolar 监控**：浏览器安装 Tampermonkey / Violentmonkey，拥有 Cpolar Web 管理界面权限（`localhost:9200`），已创建钉钉机器人 Webhook
- **Openlist 服务**：Windows 系统，管理员权限（用于创建计划任务和启动服务）

## 🤝 贡献

欢迎提交 Issue 或 Pull Request。每个子项目有独立的 README，建议先阅读对应文档。

## 📝 License

[MIT](./LICENSE) © 2026 PingWang
