# legacy/scripts — 旧版守护脚本归档

本目录存放 WPF 桌面版（OpenCpolarSync.Client）上线前使用的 PowerShell / Batch 守护脚本，仅供参考和回退使用，不再主动维护。

## 目录结构

```
legacy/scripts/
├── cpolar/
│   ├── CpolarGuard.ps1      Cpolar 隧道监控主脚本（轮询 API + 钉钉推送）
│   └── AutoStart.bat        Cpolar 守护开机自启安装脚本
├── openlist/
│   ├── OpenlistGuard.ps1    Openlist 进程守护脚本（60s 轮询 + 崩溃重启）
│   └── AutoStart.bat        Openlist 守护开机自启安装脚本
└── watchdog/
    ├── GuardCheck.ps1        守护进程存活检测脚本
    └── WatchdogManager.bat   Watchdog 管理脚本（安装/卸载/状态查询）
```

## 与 WPF 版的对应关系

| 旧脚本 | WPF 版对应模块 | 说明 |
|--------|---------------|------|
| CpolarGuard.ps1 | Services/CpolarMonitor.cs + DingTalkService.cs | 隧道监控、变更检测、钉钉推送已用 C# 重写 |
| OpenlistGuard.ps1 | Services/OpenlistMonitor.cs | 进程守护、崩溃重启已用 C# 重写 |
| GuardCheck.ps1 | Services/GuardService.cs | 统一调度管理 |
| WatchdogManager.bat | Components/TrayIcon.cs + 安装包 | 托盘菜单 + Inno Setup 开机自启选项 |
| AutoStart.bat (cpolar) | installer/setup.iss | 安装时可选开机自启 |
| AutoStart.bat (openlist) | installer/setup.iss | 安装时可选开机自启 |

## 注意事项

- 脚本中的相对路径基于原始目录结构（项目根目录下的 Cpolar/、Openlist/、Watchdog/），移动到本目录后直接运行可能路径失效。
- 如需回退使用，请将对应脚本和资源目录复制回项目根目录后再执行。
- 配置文件（config.json）在 legacy/Cpolar/config/ 目录下。
- cpolar 安装包和 openlist 压缩包分别在 legacy/Cpolar/installer/ 和 legacy/Openlist/archive/ 下。
