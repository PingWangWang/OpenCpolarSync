# Cpolar 隧道状态同步

> 自动监控 Cpolar 在线隧道状态，变更时通过钉钉 Webhook 推送通知

[![Tampermonkey](https://img.shields.io/badge/Tampermonkey-✓-brightgreen)](https://www.tampermonkey.net/)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.1.0-orange)](cpolar-sync.user.js)

## ✨ 功能特性

- **定时监控** — 按可配置的间隔（最小 5 分钟）自动轮询 Cpolar 在线隧道列表
- **变更推送** — 检测到隧道新增、信息变更、离线时，通过钉钉 Webhook 发送 Markdown 通知
- **手动发送** — 支持一键预览推送内容、立即强制发送当前勾选的隧道
- **智能去重** — 对比上次推送快照，数据无变化时不重复发送
- **状态记忆** — 刷新页面或关闭浏览器后，恢复上次监控状态和检测记录
- **调试日志** — 内置控制台调试输出，支持运行时开关，方便排查问题
- **路由自适应** — 仅在 `#/status/online` 页面显示配置栏，登录页自动隐藏

## 📦 安装

### 前置条件

- 浏览器已安装 [Tampermonkey](https://www.tampermonkey.net/) 或 [Violentmonkey](https://violentmonkey.github.io/)
- 拥有 Cpolar Web 管理界面访问权限（`http://localhost:9200`）
- 已创建钉钉机器人并获取 Webhook URL

### 安装脚本

1. 打开 `cpolar-sync.user.js` 文件，复制全部代码
2. 在 Tampermonkey 中创建新脚本，粘贴代码并保存
3. 访问 `http://localhost:9200/#/status/online`，登录后即可看到配置栏

或直接通过 URL 安装（如已部署到服务器）：

```
https://your-server.com/cpolar-sync.user.js
```

## 🚀 快速开始

### 1. 配置 Webhook

在 Cpolar 在线隧道列表页面，脚本配置栏中填写钉钉机器人 Webhook URL：

```
https://oapi.dingtalk.com/robot/send?access_token=xxxxxxxx
```

### 2. 勾选要监控的隧道

点击 **🔄 扫描隧道** 刷新列表，勾选需要监控的隧道。

### 3. 启动监控

点击 **▶ 启动监控**，脚本将按设定间隔自动检测隧道状态变更。

### 4. 测试推送

点击 **👁 预览信息** 查看推送内容，点击 **📤 立即发送** 手动推送测试。

## 🧭 界面说明

```
┌──────────────────────────────────────────────────────────┐
│ 📡 Cpolar 隧道状态同步                                    │
├──────────────────────────────────────────────────────────┤
│ Webhook URL  [______________________________]            │
│ 刷新间隔      [5] 分钟                                    │
│ [💾 保存配置] [🔄 扫描隧道] [👁 预览信息] [📤 立即发送]    │
│ [▶ 启动监控] [🔍 调试日志]                                 │
├──────────────────────────────────────────────────────────┤
│ 监控隧道（勾选需要推送的隧道）                              │
│ ☑ 隧道A  http  http://xxx.cpolar.top  http://127.0.0.1   │
│ ☑ 隧道A  https https://xxx.cpolar.top  http://127.0.0.1  │
├──────────────────────────────────────────────────────────┤
│ ┌──────────┬──────────┬──────────┬──────────┬──────────┐ │
│ │当前状态  │上次检测  │上次推送  │检测结果  │下次检测  │ │
│ ├──────────┼──────────┼──────────┼──────────┼──────────┤ │
│ │● 运行中  │ 14:30:15 │ 14:30:15 │ 已推送   │ 14:35:15 │ │
│ └──────────┴──────────┴──────────┴──────────┴──────────┘ │
│ 调试日志：已开启                                           │
└──────────────────────────────────────────────────────────┘
```

## 🔧 配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| Webhook URL | 钉钉机器人 Webhook 地址 | 空 |
| 刷新间隔 | 自动检测间隔（分钟） | 5 分钟 |
| 勾选的隧道 | 需要监控推送的隧道列表 | 空 |
| 调试日志 | 控制台调试输出开关 | 关闭 |

## 🛠️ 开发

### 技术栈

- 原生 JavaScript（ES5 兼容）
- Tampermonkey `GM_*` API
- 钉钉机器人 Webhook（Markdown 消息）

### 本地调试

1. 在 Tampermonkey 中启用脚本
2. 开启 **🔍 调试日志**（或调用 `cpolarSyncDebug(true)`）
3. 打开浏览器开发者工具 Console，过滤 `[CpolarSync]` 查看日志

### 控制台调试接口

```js
cpolarSyncDebug(true)          // 开启调试日志
cpolarSyncDebug(false)         // 关闭调试日志
cpolarSyncDebug()              // 查看当前状态
cpolarSyncDebug.layout()       // 输出页面布局诊断
```

## ❓ 适用场景

- **Cpolar 用户** — 需要实时获知隧道状态变更（新增/离线/信息更新）
- **团队协作** — 通过钉钉群机器人推送隧道状态，多人同步
- **自动化运维** — 定时监控隧道可用性，异常时自动告警

## 🤝 贡献

欢迎提交 Issue 或 Pull Request。

## 📝 License

[MIT](LICENSE)
