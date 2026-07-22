# Cpolar 隧道状态同步

> 自动监控 Cpolar 在线隧道状态，变更时通过钉钉 Webhook 推送通知 — **无需浏览器，常驻守护**

[![License](https://img.shields.io/badge/License-MIT-blue)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-2.0-orange)](CpolarGuard.ps1)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)]()

## ✨ 功能特性

- **独立运行** — 不依赖 Tampermonkey / 浏览器，PowerShell 常驻守护脚本
- **定时监控** — 按可配置的间隔（最小 1 分钟）轮询 Cpolar 后端 API
- **变更推送** — 检测到隧道新增、信息变更、离线时，通过钉钉 Webhook 发送 Markdown 通知
- **智能去重** — 对比上次推送快照，数据无变化时不重复发送
- **日志轮转** — 日志文件按 ISO 周编号归档，保留最近 4 周
- **开机自启** — 通过 AutoStart.bat 一键注册 shell:startup 快捷方式

## 📦 安装

### 前置条件

- Windows 系统，PowerShell 5.0+
- 拥有 Cpolar Web 管理界面访问权限（`http://localhost:9200`）
- 已创建钉钉机器人并获取 Webhook URL

### 目录结构

```
Cpolar/
├── CpolarGuard.ps1          # 常驻守护脚本
├── AutoStart.bat            # 开机自启管理
├── config/
│   ├── config.json          # 用户配置
│   └── last-sent.json       # 上次推送隧道快照（自动维护）
├── logs/
│   └── guard.log            # 运行日志（自动轮转）
├── archive/                 # 旧版文件（保留参考）
│   ├── cpolar-sync.user.js
│   └── api_list.txt
├── installer/               # Cpolar 安装包
│   └── cpolar_amd64.msi
└── README.md
```

## 🚀 快速开始

### 1. 获取 API Token

CpolarGuard 通过调用 Cpolar 后端 API 获取隧道列表，需要从浏览器中复制登录后的 Cookie 值：

1. 打开浏览器，登录 Cpolar Web 管理界面（`http://localhost:9200`）
2. 按 `F12` 打开开发者工具 → **Application** → **Cookies** → `http://localhost:9200`
3. 找到名为 `vue_admin_template_token` 的 Cookie，复制其 **Value**
4. 粘贴到 `config/config.json` 的 `"token"` 字段

### 2. 配置 Webhook

编辑 `config/config.json`，填写钉钉机器人 Webhook URL：

```json
{
  "webhookUrl": "https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxx",
  "interval": 5,
  "selectedTunnelNames": [],
  "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

### 3. 启动监控

```powershell
# 在 Cpolar 目录下执行
powershell -ExecutionPolicy Bypass -File CpolarGuard.ps1
```

或通过 `AutoStart.bat` 设置开机自启，重启后自动运行。

### 4. 配置勾选隧道（可选）

`config.json` 中的 `selectedTunnelNames` 用于过滤需要监控的隧道，填入隧道名称即可，例如：

```json
"selectedTunnelNames": ["OpenListHC", "我的网站"]
```

留空则监控所有隧道。

## 🔧 配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `webhookUrl` | 钉钉机器人 Webhook 地址 | `""` |
| `interval` | 自动检测间隔（分钟） | `1` |
| `selectedTunnelNames` | 需要监控的隧道名称列表（留空=全部） | `[]` |
| `cpolarApiBase` | Cpolar Web 地址 | `http://localhost:9200` |
| `token` | JWT Token（从浏览器 DevTools → Local Storage 复制） | `""` |
| `debug` | 调试日志输出开关 | `false` |

## 🧠 架构说明

```
CpolarGuard.ps1
  │
  ├─ 读取 config/config.json
  ├─ 无限循环：
  │   ├─ GET /api/v1/tunnels?token=xxx   ← 调用 Cpolar 后端 API
  │   ├─ 筛选已勾选隧道
  │   ├─ 检测变更（新增/更新/离线）
  │   ├─ 有变更 → POST 钉钉 Webhook
  │   └─ Start-Sleep 等待下一周期
  └─ 日志轮转（保留最近 4 周）
```

**对比旧版 Tampermonkey 油猴脚本：**

| 维度 | 旧版（油猴脚本） | 新版（PowerShell 守护） |
|------|:---:|:---:|
| 依赖浏览器 | ✅ 必须 | ❌ 不需要 |
| 依赖 Tampermonkey | ✅ 必须 | ❌ 不需要 |
| 数据源 | DOM 解析（Vue SPA） | REST API（JSON） |
| 常驻运行 | 浏览器页面打开时 | 后台进程常驻 |
| 崩溃恢复 | 页面刷新后重连 | AutoStart.bat 守护 |
| 日志记录 | 浏览器控制台 | 文件日志 + 周轮转 |

## 🛠️ 手动运行与调试

### 前台运行（调试模式）

```powershell
powershell -ExecutionPolicy Bypass -File CpolarGuard.ps1
```

窗口保持可见，日志同时输出到控制台和 `logs/guard.log`。

### 后台运行（隐藏窗口）

脚本启动后自动隐藏控制台窗口（通过 `Add-Type` + `ShowWindow` 实现）。
如需在前台运行，注释掉脚本开头的窗口隐藏代码。

### 查看日志

```powershell
# 实时查看
Get-Content .\logs\guard.log -Tail 20 -Wait

# 查看历史归档
Get-ChildItem .\logs\guard.log.*
```

## ❓ 适用场景

- **Cpolar 用户** — 需要实时获知隧道状态变更（新增/离线/信息更新）
- **团队协作** — 通过钉钉群机器人推送隧道状态，多人同步
- **自动化运维** — 无需打开浏览器，服务器后台长期运行

## 📝 License

[MIT](LICENSE)
