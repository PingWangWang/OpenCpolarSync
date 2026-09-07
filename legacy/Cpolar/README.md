# Cpolar 隧道状态同步

> 常驻守护脚本，自动监控 Cpolar 在线隧道状态，变更时通过钉钉 Webhook 推送通知 — **无需浏览器，支持配置热重载**

[![License](https://img.shields.io/badge/License-MIT-blue)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-2.1-orange)](CpolarGuard.ps1)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)]()

## ✨ 项目亮点

- **独立于浏览器运行** — 不依赖 Tampermonkey / 浏览器，PowerShell 常驻守护脚本，后台静默运行
- **全状态变更检测** — 新增上线 🟢、信息变更 🔄、重新上线 🟢、已离线 🔴，支持同名多协议隧道独立追踪
- **配置变更热重载** — 修改 `config.json` 后自动检测字段级变化（Webhook 地址、轮询间隔、监控列表等），增量推送通知
- **系统状态监控** — 追踪 API 请求与推送的连续失败 / 恢复状态，推送连续失败达到阈值时在消息中附加系统状态告警区块
- **智能去重** — 对比上次推送快照，数据无变化时不重复发送；API 数据不完整时跳过本轮等待数据稳定
- **空结果离线检测** — API 返回空列表但有历史缓存时触发全部隧道离线推送，不漏报
- **日志轮转** — 日志文件按 ISO 周编号归档，保留最近 4 周
- **开机自启** — 通过 `AutoStart.bat` 一键注册/删除 `shell:startup` 快捷方式，带 UAC 提权菜单与命令行静默模式（`add` / `remove`）

## 📦 安装

### 前置条件

- Windows 系统，PowerShell 5.0+
- 拥有 Cpolar Web 管理界面访问权限（`http://localhost:9200`）
- 已创建钉钉机器人并获取 Webhook URL

### 目录结构

```
Cpolar/
├── CpolarGuard.ps1          # 常驻守护脚本（主入口）
├── AutoStart.bat            # 开机自启管理（UAC 提权菜单）
├── config/
│   ├── config.json          # 用户配置（支持热重载）
│   └── last-sent.json       # 上次推送隧道快照（自动维护，勿手动修改）
├── logs/
│   └── guard.log            # 运行日志（按 ISO 周自动轮转）
├── archive/                 # 旧版文件（保留参考）
│   ├── cpolar-sync.user.js
│   ├── cpolar-sync.meta.js
│   └── api_list.txt
├── installer/               # Cpolar 安装包
│   └── cpolar_amd64.msi
└── README.md
```

## 🚀 快速开始

### 1. 配置登录凭证

CpolarGuard 通过调用 Cpolar 后端 API 获取隧道列表，需要配置 Cpolar Web 的登录邮箱和密码（脚本自动登录，无需手动复制 Token）：

编辑 `config/config.json`，填入 Cpolar Web 的登录邮箱和密码：

```json
{
  "username": "your@email.com",
  "password": "your_password"
}
```

首次请求隧道数据时，脚本自动调用登录接口（`POST /api/v1/user/login`）获取 JWT Token 并缓存复用；Token 过期导致 API 鉴权失败时，自动重新登录后重试一次。

### 2. 配置 Webhook

编辑 `config/config.json`，填写钉钉机器人 Webhook URL：

```json
{
  "webhookUrl": "https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxx",
  "keyword": "Cpolar",
  "interval": 1,
  "selectedTunnelNames": [],
  "username": "",
  "password": ""
}
```

> 钉钉群 → 智能群助手 → 添加机器人 → 复制 Webhook URL；`keyword` 需与机器人安全关键词一致。

### 3. 启动监控

```powershell
# 在 Cpolar 目录下执行
powershell -ExecutionPolicy Bypass -File CpolarGuard.ps1
```

脚本启动后自动隐藏控制台窗口，后台常驻运行。

### 4. （可选）配置勾选隧道

`config.json` 中的 `selectedTunnelNames` 用于过滤需要监控的隧道：

```json
"selectedTunnelNames": ["OpenListHC", "我的网站"]
```

留空 `[]` 则不监控任何隧道。运行中修改此文件，下一轮检测自动生效。

### 5. 设置开机自启

以**管理员身份**运行 `AutoStart.bat`，选 `1` 添加开机自启：

```
====================================
   Cpolar 隧道监控 - 开机自启管理
====================================
    1. 添加开机自启
    2. 删除开机自启
====================================
请选择 (1/2):
```

重启后 CpolarGuard 将随系统自动启动。

`AutoStart.bat` 也支持命令行静默模式（供 Watchdog 等外部调用）：

```batch
AutoStart.bat add       # 静默添加开机自启
AutoStart.bat remove    # 静默删除开机自启
```

## 🔧 配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `webhookUrl` | 钉钉机器人 Webhook 地址 | `""` |
| `keyword` | 钉钉机器人安全关键词 | `"Cpolar"` |
| `interval` | 自动检测间隔（分钟，最小 1） | `1` |
| `selectedTunnelNames` | 监控隧道名称列表（空=不监控） | `[]` |
| `cpolarApiBase` | Cpolar Web 地址 | `http://localhost:9200` |
| `username` | Cpolar Web 登录邮箱（必填，自动登录） | `""` |
| `password` | Cpolar Web 登录密码（必填） | `""` |
| `debug` | 调试日志开关 | `false` |

> 所有配置项修改后**无需重启脚本**，下一轮检测自动应用变更。

## 🧠 架构说明

```
┌─────────────────────────────────────────────────┐
│ CpolarGuard.ps1（常驻守护）                      │
│                                                   │
│  ┌──────────────────────────────────────────┐    │
│  │  读取 config/config.json（热重载）        │    │
│  └──────────────────────────────────────────┘    │
│                         │                        │
│                         ▼                        │
│  ┌──────────────────────────────────────────┐    │
│  │  用户名密码 → 自动登录获取 JWT Token      │    │
│  │  （首次请求时登录，Token 缓存复用）      │    │
│  └──────────────────────────────────────────┘    │
│                         │                        │
│                         ▼                        │
│  ┌────── 无限循环 ──────────────────────────┐    │
│  │                                           │    │
│  │  ① 检测 Config 字段级变更                │    │
│  │     → Compare-ConfigState                 │    │
│  │     → 有变更则计入消息                    │    │
│  │                                           │    │
│  │  ② GET /api/v1/tunnels                   │    │
│  │     → 调用 Cpolar 后端 API                │    │
│  │     → 鉴权：Authorization: Bearer Token   │    │
│  │     → Bearer 失败 → 自动重新登录重试      │    │
│  │     → 失败时记录 apiHistory 并跳过本轮    │    │
│  │                                           │    │
│  │  ③ 筛选已勾选隧道                        │    │
│  │     → Filter-SelectedTunnels              │    │
│  │     → 空列表且有历史 → 全部离线通知       │    │
│  │                                           │    │
│  │  ④ 检测变更（复合 key: name|protocol）   │    │
│  │     → Detect-TunnelChanges                │    │
│  │     → 新增 / 信息变更 / 重新上线 / 离线   │    │
│  │     → 字段级 diff（Get-TunnelDiffFields）│    │
│  │     → 数据不完整时跳过等待稳定            │    │
│  │                                           │    │
│  │  ⑤ 组装三区块消息                        │    │
│  │     → Build-DingTalkMessage               │    │
│  │     → [Config] [隧道状态] [系统状态]       │    │
│  │                                           │    │
│  │  ⑥ POST 钉钉 Webhook（Markdown）          │    │
│  │     → 成功：更新 last-sent.json           │    │
│  │     → 失败：记录 pushHistory              │    │
│  │                                           │    │
│  │  ⑦ Start-Sleep 等待下一周期              │    │
│  └───────────────────────────────────────────┘    │
│                                                   │
│  日志轮转（保留最近 4 周）                        │
│  互斥体防止多实例重复启动                         │
└─────────────────────────────────────────────────┘
```

**对比旧版 Tampermonkey 油猴脚本：**

| 维度 | 旧版（油猴脚本） | 新版（PowerShell 守护） |
|------|:---:|:---:|
| 依赖浏览器 | ✅ 必须 | ❌ 不需要 |
| 依赖 Tampermonkey | ✅ 必须 | ❌ 不需要 |
| 数据源 | DOM 解析（Vue SPA） | REST API（JSON） |
| 常驻运行 | 浏览器页面打开时 | 后台进程常驻 |
| 配置热重载 | ❌ 不支持 | ✅ 自动检测 |
| 崩溃恢复 | 页面刷新后重连 | Watchdog 计划任务保活 |
| 日志记录 | 浏览器控制台 | 文件日志 + 周轮转 |
| 系统状态监控 | ❌ 无 | ✅ API/推送失败追踪 |

## 🛠️ 手动运行与调试

### 前台运行（调试模式）

```powershell
powershell -ExecutionPolicy Bypass -File CpolarGuard.ps1
```

窗口保持可见，日志同时输出到控制台和 `logs/guard.log`。如需强制在前台运行，注释脚本开头的窗口隐藏代码（`ShowWindow` 调用部分）。

### 查看日志

```powershell
# 实时查看最新 20 行
Get-Content .\logs\guard.log -Tail 20 -Wait

# 查看历史归档
Get-ChildItem .\logs\guard.log.*
```

## ❓ 适用场景

- **Cpolar 用户** — 需要实时获知隧道状态变更（新增 / 离线 / 信息更新），无需一直开着浏览器
- **团队协作** — 通过钉钉群机器人推送隧道状态，多人同步，异常第一时间知晓
- **自动化运维** — 服务器后台长期运行，配置热重载无需重启，崩溃后开机自启自动恢复
- **多协议隧道** — 同一域名下 TCP / HTTP 等多协议隧道独立追踪，推送消息精确到每个隧道

## 💬 推送消息示例

钉钉消息按三区块组织：

```
Cpolar

## Cpolar 监控报告

━━━ Config 配置变更 ━━━

**⚙️ 监控隧道列表 — 已变更**
- 原值：OpenListHC
- 新值：OpenListHC, 我的网站
- 生效：下一轮检测生效

━━━ 隧道状态变更 ━━━

**🟢 OpenListHC — 新增上线**
- 协议：http
- 公网地址：https://xxx.cpolar.top
- 本地地址：http://localhost:8080

**🔴 我的网站 — 已离线**
- 协议：https
- 公网地址：https://yyy.cpolar.top
- 本地地址：http://localhost:3000

━━━ 系统状态 ━━━

**📤🔴 推送持续失败 — 已连续 3 次**
- 连续失败次数：3 次
- 最后失败时间：2026-07-20 14:25:00
- 建议：检查 config.json 中的 webhookUrl 是否正确

━━━
⏱ 检测时间：2026-07-20 14:30:00
```

## 📝 License

[MIT](LICENSE)
