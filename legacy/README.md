# legacy — 旧版项目归档

本目录存放 WPF 桌面版（OpenCpolarSync.Client）上线前的旧版项目文件，包括守护脚本、cpolar/openlist 资源文件和 Watchdog 工具，仅供参考和回退使用，不再主动维护。

## 目录结构

```
legacy/
├── Cpolar/              旧版 Cpolar 模块
│   ├── config/          配置文件（config.json、last-sent.json）
│   ├── installer/       cpolar 安装包（cpolar_amd64.msi）
│   ├── archive/         参考资料（API 文档、油猴脚本等）
│   ├── logs/            旧版运行日志
│   └── README.md        旧版 Cpolar 模块说明
├── Openlist/            旧版 Openlist 模块
│   ├── openlist.exe     openlist 主程序（绿色版，162MB）
│   ├── archive/         openlist 压缩包（openlist.zip）
│   ├── data/            openlist 运行数据（配置、数据库、日志）
│   ├── logs/            旧版守护日志
│   └── README.md        旧版 Openlist 模块说明
├── Watchdog/            旧版 Watchdog 保活模块
│   ├── watchdog.log     旧版运行日志
│   └── README.md        旧版 Watchdog 模块说明
└── scripts/             旧版守护脚本（PowerShell / Batch）
    ├── cpolar/          CpolarGuard.ps1、AutoStart.bat
    ├── openlist/        OpenlistGuard.ps1、AutoStart.bat
    ├── watchdog/        GuardCheck.ps1、WatchdogManager.bat
    └── README.md        旧版脚本归档说明
```

## 与 WPF 版的对应关系

| 旧版目录/文件 | WPF 版对应 | 说明 |
|--------------|------------|------|
| legacy/scripts/cpolar/CpolarGuard.ps1 | src/.../Services/CpolarMonitor.cs + DingTalkService.cs | 隧道监控、变更检测、钉钉推送已用 C# 重写 |
| legacy/scripts/openlist/OpenlistGuard.ps1 | src/.../Services/OpenlistMonitor.cs | 进程守护、崩溃重启已用 C# 重写 |
| legacy/scripts/watchdog/ | src/.../Services/GuardService.cs + Components/TrayIcon.cs | 统一调度 + 托盘保活 |
| legacy/Cpolar/installer/cpolar_amd64.msi | installer/setup.iss | 安装时静默安装 cpolar |
| legacy/Openlist/archive/openlist.zip | installer/setup.iss | 安装时解压部署 openlist |
| legacy/Cpolar/config/config.json | 安装后 {app}/config/config.json | 默认配置模板 |

## 注意事项

- 旧版脚本中的相对路径基于原始根目录结构，移动到本目录后直接运行可能路径失效。
- 如需回退使用旧版脚本，请将对应文件复制回项目根目录后再执行。
- openlist.exe 为 162MB 大文件，已在 .gitignore 中排除，不纳入版本控制。
- cpolar_amd64.msi 和 openlist.zip 同样在 .gitignore 中排除。
