# OpenCpolarSync WPF 安装版 — 设计方案

> 版本：v1.0 草案  
> 日期：2026-09-04  
> 状态：待评审

---

## 一、需求理解

### 1.1 业务目标

将现有的三个 PowerShell/Batch 脚本模块（Cpolar 隧道监控、Openlist 服务守护、Watchdog 保活）整合为一个 **Windows 桌面安装程序**，提供图形化界面统一管理，降低用户使用门槛。

### 1.2 约束条件

| 约束项 | 具体要求 |
|--------|----------|
| 界面技术 | WPF（Windows Presentation Foundation） |
| 系统兼容 | Windows 7 SP1 ~ 最新 Windows 11 |
| 托盘行为 | 关闭主窗口时最小化到系统托盘，不退出程序 |
| 集成方式 | 将 cpolar 和 openlist 两个 exe 打包进安装包 |
| 安装检测 | 安装时检测目标程序是否已安装，未安装则提醒并一并安装 |
| 交付形态 | .exe 安装包（非绿色版） |

### 1.3 功能边界

**必须实现**：
1. 启动/停止守护（同时守护 cpolar 和 openlist 两个进程）
2. Cpolar 配置（原生表单编辑 config.json + 网页管理入口打开 `localhost:9200`）
3. Openlist 网页配置入口（点击按钮打开，或内嵌 Web 界面 `localhost:5244`）
4. 系统托盘（最小化、状态显示、右键菜单，含 cpolar/openlist 管理快捷入口）
5. 安装程序（集成 cpolar MSI + openlist 绿色包，检测已安装状态）

**不做（本期范围外）**：
- 跨平台（macOS/Linux）
- 多用户/多租户
- 远程管理（仅本地 localhost）
- 钉钉推送的图形化配置（沿用 config.json 编辑）

### 1.4 假设点

- cpolar 安装包使用项目中已有的 `cpolar_amd64.msi`（8.38 MB）
- openlist 使用项目中已有的 `openlist.zip`（71 MB，解压后 openlist.exe 162 MB）
- 用户以管理员身份运行安装程序（cpolar MSI 需要管理员权限）
- 钉钉 Webhook 推送功能保留，但通过配置文件编辑而非独立 UI

---

## 二、项目现状

### 2.1 现有架构

```
OpenCpolarSync/
├── Cpolar/           # PowerShell 守护脚本 + Batch 自启管理
│   ├── CpolarGuard.ps1    # 轮询 Cpolar API → 钉钉推送
│   ├── AutoStart.bat      # shell:startup 快捷方式管理
│   ├── config/config.json # 用户配置（热重载）
│   └── installer/cpolar_amd64.msi  # cpolar 安装包（8.38MB）
├── Openlist/         # PowerShell 守护脚本 + Batch 自启管理
│   ├── OpenlistGuard.ps1  # 60s 轮询 openlist.exe → 崩溃重启
│   ├── AutoStart.bat      # shell:startup 快捷方式管理
│   ├── openlist.exe       # 绿色版程序（162MB，手动放置）
│   └── archive/openlist.zip  # 发布压缩包（71MB）
└── Watchdog/         # 计划任务保活
    ├── GuardCheck.ps1     # Mutex 判活 + 自动拉起
    └── WatchdogManager.bat # 计划任务注册/卸载
```

### 2.2 现有守护机制

| 机制 | 实现方式 | 问题 |
|------|----------|------|
| 进程守护 | PowerShell 无限循环 + Start-Sleep | 无 GUI，日志只能看文件 |
| 防多实例 | Global\ 命名 Mutex | 正常 |
| 开机自启 | shell:startup 快捷方式 | 登录后才有弹窗，注销即停 |
| 运行时保活 | Task Scheduler + S4U（每5分钟） | 配置复杂，普通用户难理解 |
| 配置管理 | 手动编辑 config.json | 无校验，易错 |

### 2.3 关键技术事实（已核实）

| 项目 | 事实 |
|------|------|
| cpolar 安装包 | MSI 格式（`cpolar_amd64.msi`，8.38 MB），需管理员权限安装 |
| cpolar 管理界面 | Web UI at `http://localhost:9200`，JWT Token 鉴权 |
| cpolar 配置文件 | 默认 `$HOME/.cpolar/cpolar.yml`，CLI 支持 `-config` 指定路径 |
| openlist 程序 | 绿色版单 exe（162 MB），启动参数 `openlist.exe server` |
| openlist 管理界面 | Web UI at `http://localhost:5244`，默认账号 admin |
| openlist 配置文件 | `data/config.json`（SQLite 数据库 `data/data.db`） |
| .NET Framework | 当前开发机 4.8；Win7 SP1 最高支持 4.8 |
| PowerShell | Win7 自带 5.0/5.1，Win10/11 自带 5.1 |

---

## 三、关键技术约束分析

### 3.1 WPF + Win7 兼容性（硬约束）

| 技术栈 | Win7 支持 | 结论 |
|--------|-----------|------|
| .NET Framework 4.0 ~ 4.8 | ✅ 支持 | **必须选此** |
| .NET Core 3.0 / .NET 5+ | ❌ 不支持 Win7 | 排除 |
| .NET 6/7/8 | ❌ 不支持 Win7 | 排除 |

**结论**：必须使用 **.NET Framework 4.8**（或 4.7.2）开发 WPF 应用。这意味着：
- 不能使用 C# 8.0+ 的部分新语法（如 default interface methods、async streams）
- 不能使用 .NET Core 专属 API
- 项目格式用传统 `.csproj`（非 SDK 风格）

### 3.2 系统托盘实现

WPF 无原生 NotifyIcon，可选方案：

| 方案 | 体积 | Win7 兼容 | 说明 |
|------|------|-----------|------|
| `Hardcodet.NotifyIcon.Wpf`（NuGet） | ~50KB | ✅ | 纯 WPF 实现，支持气泡提示、右键菜单、双击事件，**推荐** |
| `System.Windows.Forms.NotifyIcon` 互操作 | 0（系统自带） | ✅ | 需要引用 WinForms 程序集，代码略繁琐 |
| 自绘 Win32 API | 0 | ✅ | 开发量大，不推荐 |

### 3.3 内嵌 Web 界面（cpolar + openlist 管理入口）

cpolar 管理界面（`http://localhost:9200`）和 openlist 管理界面（`http://localhost:5244`）都是现代 Vue SPA，两者共用同一套 WebView2 组件，通过加载不同 URL 切换。

| 方案 | Win7 兼容 | 体积增量 | 体验 | 说明 |
|------|-----------|----------|------|------|
| **WebView2**（Edge Chromium） | ⚠️ Win7 需安装 WebView2 Runtime | ~150MB（Runtime） | 最佳 | Win10 1803+ 系统自带；Win7 需检测并引导安装 Evergreen Runtime；cpolar 和 openlist 共用组件实例 |
| **CefSharp**（Chromium 嵌入） | ⚠️ 需 v90 旧版 | ~100MB（x86+x64） | 好 | 最新版已放弃 Win7；需锁定旧版本，安全更新滞后 |
| **WebBrowser 控件**（IE 内核） | ✅ 自带 | 0 | 差 | 基于 IE11，现代网页兼容性差，cpolar/openlist 前端均可能渲染异常 |
| **外部浏览器打开** | ✅ | 0 | 一般 | 调用 `Process.Start("http://localhost:9200/5244")`，跳出主程序 |

**关键判断**：cpolar 和 openlist 的 Web 前端都是现代 SPA（Vue），IE 内核必然渲染异常。因此 WebBrowser 控件不可用。**WebView2 组件复用设计**：一个 `WebView2Manager` 管理 WebView2 生命周期，cpolar 和 openlist 各持一个 `WebView2` 控件实例（或共用一个通过 `Navigate()` 切换 URL），Win7 无 Runtime 时统一降级为外部浏览器。

### 3.4 安装包制作

| 工具 | 格式 | Win7 兼容 | 学习曲线 | 说明 |
|------|------|-----------|----------|------|
| **Inno Setup** | .exe | ✅ | 低 | 免费、脚本化、体积小、支持安装前检测/条件安装，**推荐** |
| WiX Toolset | .msi | ✅ | 高 | 微软官方，XML 配置，复杂 |
| NSIS | .exe | ✅ | 中 | 免费、脚本化，但语法较老 |

### 3.5 守护进程实现

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| **C# 内嵌守护** | WPF 主程序后台 `Task`/`Timer` 轮询 | 统一、无外部依赖、托盘直接控制状态 | 需重写现有 PowerShell 逻辑 |
| **复用 PowerShell 脚本** | WPF 调用现有 `.ps1`，管理其进程 | 复用已验证代码、开发量小 | 进程间通信复杂、日志分散、体验割裂 |
| **Windows Service** | 安装为系统服务 | 最稳定、注销也运行 | 开发量大、Win7 服务管理复杂、需单独安装 |

---

## 四、方案设计

### 方案一：全内嵌一体化方案（推荐）

**一句话概括**：用 C# 重写守护逻辑内嵌到 WPF 主程序，WebView2 嵌入 openlist 管理界面，Inno Setup 一键安装全部组件。

**核心思路**：
- WPF 主程序 = 守护引擎 + 配置 UI + 托盘 + 安装器前端
- 守护逻辑用 C# `System.Threading.Timer` + `Process` 类重写，替代 PowerShell 脚本
- cpolar 配置用原生 WPF 表单（数据绑定 config.json）+ Web 管理入口（WebView2 内嵌 `localhost:9200`，Win7 降级外部浏览器）
- openlist 配置用 WebView2 内嵌（`localhost:5244`，Win7 自动降级为外部浏览器）
- **WebView2 组件复用**：cpolar 和 openlist 共用同一个 `WebView2Manager`，各自的 Tab 内持有 WebView2 控件，通过 `Navigate()` 加载不同 URL；Win7 无 Runtime 时统一降级
- Watchdog 保活由 WPF 主程序自身承担（主程序在则守护在），不再需要独立计划任务

#### 4.1.1 模块/组件划分

```
OpenCpolarSync.Client (WPF .NET Framework 4.8)
├── App.xaml / App.xaml.cs          # 应用入口、单实例互斥
├── MainWindow.xaml                  # 主界面（Tab 布局）
│   ├── DashboardTab                 # 总览：两个服务状态、启动/停止按钮、Web管理快捷入口
│   ├── CpolarConfigTab              # cpolar 配置表单 + Web 管理入口（WebView2 内嵌 localhost:9200）
│   ├── OpenlistTab                  # openlist 管理（WebView2 嵌入 localhost:5244）
│   └── LogsTab                      # 运行日志查看
├── Components/
│   ├── TrayIcon.cs                  # 系统托盘（Hardcodet.NotifyIcon.Wpf）
│   └── WebView2Manager.cs           # WebView2 初始化 + Win7 降级检测（同时服务 cpolar:9200 和 openlist:5244）
├── Services/
│   ├── GuardService.cs              # 守护引擎（轮询 + 进程管理）
│   ├── CpolarMonitor.cs             # cpolar 隧道状态监控 + 钉钉推送
│   ├── OpenlistMonitor.cs           # openlist 进程守护
│   ├── ConfigService.cs             # config.json 读写 + 校验
│   └── InstallDetectionService.cs   # 安装状态检测（cpolar/openlist）
├── Models/
│   ├── CpolarConfig.cs              # cpolar 配置模型
│   ├── TunnelInfo.cs                # 隧道信息模型
│   └── ServiceStatus.cs             # 服务状态枚举
└── Installer/
    └── setup.iss                    # Inno Setup 脚本
```

#### 4.1.2 数据流设计

```
用户操作 → WPF UI → ConfigService（读写 config.json）
                      ↓
               GuardService（Timer 轮询）
                ├── CpolarMonitor → HTTP GET localhost:9200/api/v1/tunnels
                │                     → 变更检测 → 钉钉 Webhook POST
                └── OpenlistMonitor → Process.GetProcessesByName("openlist")
                                      → 不存在则 Start-Process
                      ↓
               状态更新 → UI 绑定（INotifyPropertyChanged）
                      ↓
               TrayIcon（气泡提示状态变更）
```

#### 4.1.3 关键接口定义

**GuardService（守护引擎）**：
```csharp
public interface IGuardService
{
    event EventHandler<StatusChangedEventArgs> StatusChanged;
    void Start();                    // 启动所有守护
    void Stop();                     // 停止所有守护
    ServiceStatus GetCpolarStatus();
    ServiceStatus GetOpenlistStatus();
}
```

**CpolarMonitor（隧道监控）**：
```csharp
public interface ICpolarMonitor
{
    Task LoginAsync(string email, string password);   // 获取 JWT Token
    Task<List<TunnelInfo>> FetchTunnelsAsync();       // 轮询隧道列表
    event EventHandler<TunnelChangedEventArgs> TunnelChanged;
}
```

**ConfigService（配置管理）**：
```csharp
public interface IConfigService
{
    CpolarConfig Load();
    bool Save(CpolarConfig config);
    bool Validate(CpolarConfig config, out List<string> errors);
}
```

#### 4.1.4 安装流程设计（Inno Setup）

```
安装程序启动
  │
  ├─ 检测 cpolar 是否已安装
  │   ├─ 检测方式：注册表 HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*
  │   │            或检查默认安装路径 C:\Program Files\cpolar\
  │   ├─ 已安装 → 跳过，显示"检测到已安装 cpolar"
  │   └─ 未安装 → 提示用户"将一并安装 cpolar"，复选框默认勾选
  │
  ├─ 检测 openlist 是否已部署
  │   ├─ 检测方式：检查安装目标目录下是否存在 openlist.exe
  │   ├─ 已存在 → 跳过
  │   └─ 未存在 → 从安装包解压 openlist.zip 到目标目录
  │
  ├─ 安装主程序（WPF exe + 依赖）
  ├─ 创建桌面快捷方式 + 开始菜单
  ├─ 可选：注册开机自启（注册表 Run 键，非 shell:startup）
  └─ 完成页：勾选"立即启动 OpenCpolarSync"
```

**安装包内嵌资源**：
- `cpolar_amd64.msi`（8.38 MB）
- `openlist.zip`（71 MB）
- 主程序及 .NET 依赖

**预计安装包总体积**：~85 MB（压缩后）

#### 4.1.5 界面设计概要

**主窗口（Tab 布局）**：

```
┌─────────────────────────────────────────────┐
│  OpenCpolarSync                    [—][□][×] │  ← 关闭按钮 → 最小化到托盘
├──────────┬──────────┬──────────┬────────────┤
│  总览     │ Cpolar配置 │ Openlist │  日志      │
├──────────┴──────────┴──────────┴────────────┤
│                                                  │
│  [总览 Tab]                                      │
│  ┌─────────────────────┐ ┌────────────────────┐ │
│  │  Cpolar 隧道监控      │ │  Openlist 文件服务   │ │
│  │  状态：● 运行中       │ │  状态：● 运行中      │ │
│  │  监控隧道：1 个       │ │  PID：17228         │ │
│  │  最近推送：2分钟前    │ │  访问：localhost:5244│ │
│  │  [启动守护] [停止]    │ │  [启动守护] [停止]   │ │
│  │  [🌐 打开Web管理]     │ │  [🌐 打开Web管理]    │ │  ← cpolar→9200, openlist→5244
│  └─────────────────────┘ └────────────────────┘ │
│                                                  │
│  全局操作：[启动全部守护] [停止全部守护]          │
│                                                  │
└─────────────────────────────────────────────┘
```

**CpolarConfigTab（配置表单 + Web 管理入口）**：

```
┌─────────────────────────────────────────────┐
│  Cpolar 配置                                  │
├─────────────────────────────────────────────┤
│                                                  │
│  ┌─ 基础配置 ───────────────────────────────┐  │
│  │  钉钉 Webhook：[________________________] │  │
│  │  安全关键词：  [Cpolar________]            │  │
│  │  轮询间隔：    [1] 分钟（最小1）           │  │
│  │  监控隧道：    [OpenListHC] （逗号分隔）   │  │
│  │  Cpolar API：  [http://localhost:9200]    │  │
│  │  登录邮箱：    [________________________]   │  │
│  │  登录密码：    [________________________]   │  │
│  │  [☑ 调试模式]                                │  │
│  │                          [保存配置] [重置]   │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
│  ┌─ Web 管理入口 ───────────────────────────┐  │
│  │  cpolar 提供完整的 Web 管理界面，可在其中  │  │
│  │  创建/编辑隧道、查看在线状态、管理账号等。   │  │
│  │                                            │  │
│  │  [🌐 在内嵌浏览器中打开 cpolar 管理]        │  │  ← WebView2 加载 localhost:9200
│  │  [🔗 在外部浏览器中打开]                    │  │  ← Process.Start 降级方案
│  │                                            │  │
│  │  地址：http://localhost:9200               │  │
│  └──────────────────────────────────────────┘  │
│                                                  │
└─────────────────────────────────────────────┘
```

> **Web 管理入口设计说明**：
> - 点击"在内嵌浏览器中打开"时，在当前 Tab 下方展开 WebView2 控件（或弹出独立子窗口），加载 `http://localhost:9200`
> - cpolar Web 界面需要登录，WebView2 会持久化 Cookie，登录一次后后续自动登录
> - Win7 无 WebView2 Runtime 时，"在内嵌浏览器中打开"按钮禁用并显示提示，仅"在外部浏览器中打开"可用
> - 托盘右键菜单和总览 Tab 的快捷按钮均调用同一套 `WebView2Manager.Open(url)` 逻辑

**托盘右键菜单**：
```
OpenCpolarSync v1.0
──────────────
显示主窗口
──────────────
启动全部守护
停止全部守护
──────────────
打开 Cpolar 管理 (localhost:9200)
打开 Openlist 管理 (localhost:5244)
──────────────
退出
```

#### 4.1.6 变更文件列表

| 操作 | 文件 |
|------|------|
| 新增 | `src/OpenCpolarSync.Client/`（WPF 项目，~30 个 .cs/.xaml 文件） |
| 新增 | `src/OpenCpolarSync.Client.sln` |
| 新增 | `installer/setup.iss`（Inno Setup 脚本） |
| 新增 | `docs/WPF-Installer-Design.md`（本文档） |
| 保留 | `Cpolar/`、`Openlist/`、`Watchdog/`（现有脚本作为参考/备用） |
| 修改 | `README.md`（新增 WPF 安装版说明） |
| 修改 | `.gitignore`（新增 bin/obj/packages 忽略规则） |

#### 4.1.7 优点

1. **体验统一**：一个窗口管理所有功能，无需理解 PowerShell/计划任务
2. **无外部脚本依赖**：守护逻辑 C# 实现，不依赖 PowerShell 执行策略
3. **托盘深度集成**：状态变更实时气泡提示，右键菜单快捷操作（含 cpolar/openlist Web 管理入口）
4. **配置可视化**：cpolar 配置表单带校验，避免手写 JSON 出错
5. **双 Web 管理内嵌**：cpolar（localhost:9200）和 openlist（localhost:5244）均通过 WebView2 内嵌，共用组件，无需跳出主程序；Win7 无 Runtime 时统一降级外部浏览器
6. **安装一键完成**：Inno Setup 自动检测并安装 cpolar + openlist

#### 4.1.8 缺点

1. **开发量大**：需用 C# 重写现有 PowerShell 守护逻辑（~1500 行脚本 → C#）
2. **WebView2 在 Win7 有依赖**：Win7 用户需额外安装 WebView2 Runtime（~150MB），否则降级为外部浏览器
3. **安装包体积大**：~85 MB（含 openlist.zip 71MB）
4. **.NET Framework 限制**：不能使用 C# 8.0+ 新语法和 .NET Core API
5. **Watchdog 保活弱化**：主程序崩溃则守护全停（可通过注册开机自启 + 单实例恢复缓解，但不如独立计划任务健壮）

#### 4.1.9 适用场景

- 目标用户为非技术用户，需要"安装即用"的体验
- 希望统一管理界面，不希望用户接触命令行/脚本
- 对 Win7 兼容有硬性要求，但 Win7 用户占比不高（可接受 WebView2 降级）

---

### 方案二：轻量管理壳 + 复用现有脚本方案

**一句话概括**：WPF 仅作为图形化管理壳，守护逻辑复用现有 PowerShell 脚本，WPF 负责启动/停止/监控脚本进程和编辑配置。

**核心思路**：
- WPF 主程序 = 进程管理器 + 配置编辑器 + 托盘
- 守护逻辑不变：继续使用 `CpolarGuard.ps1` / `OpenlistGuard.ps1`
- WPF 通过 `Process` 启动/停止 PowerShell 脚本，通过 Mutex 判活
- openlist 配置用外部浏览器打开（不嵌入 Web）
- Watchdog 继续使用现有计划任务方案

#### 4.2.1 模块/组件划分

```
OpenCpolarSync.Client (WPF .NET Framework 4.8)
├── App.xaml / App.xaml.cs
├── MainWindow.xaml
│   ├── DashboardTab          # 总览 + 启动/停止脚本
│   ├── CpolarConfigTab       # cpolar 配置表单（同方案一）
│   └── LogsTab               # 读取 guard.log 显示
├── Components/
│   └── TrayIcon.cs           # 系统托盘
├── Services/
│   ├── ScriptManager.cs      # PowerShell 脚本进程管理（启动/停止/判活）
│   ├── ConfigService.cs      # config.json 读写
│   └── LogReader.cs          # guard.log 实时读取
└── Installer/
    └── setup.iss
```

#### 4.2.2 数据流设计

```
用户点击"启动守护"
  → ScriptManager.Start("CpolarGuard.ps1")
  → Process.Start("powershell.exe", "-File CpolarGuard.ps1")
  → 脚本独立运行（Mutex 防多实例）
  → WPF 轮询 Mutex 判活 + 读取 guard.log 更新 UI

用户编辑配置
  → ConfigService.Save(config)
  → 写入 config.json
  → PowerShell 脚本下一轮自动热重载（现有功能）
```

#### 4.2.3 关键接口定义

**ScriptManager（脚本进程管理）**：
```csharp
public interface IScriptManager
{
    bool Start(string scriptName);       // 启动 PowerShell 脚本
    void Stop(string scriptName);         // 停止脚本进程
    bool IsRunning(string scriptName);    // 通过 Mutex 判活
    event EventHandler<ScriptStatusEventArgs> StatusChanged;
}
```

#### 4.2.4 安装流程设计

与方案一基本相同，但额外需要：
- 确保 PowerShell 执行策略允许运行脚本（`Set-ExecutionPolicy RemoteSigned`，安装时请求管理员权限执行）
- 安装 Watchdog 计划任务（调用现有 `WatchdogManager.bat setup all`）

#### 4.2.5 界面设计概要

与方案一类似，但：
- CpolarConfigTab：配置表单 + "在外部浏览器中打开 cpolar 管理"按钮（不内嵌 WebView2）
- Openlist Tab 改为"外部管理"：显示 openlist 状态 + "在浏览器中打开管理界面"按钮
- 日志 Tab 直接读取 `logs/guard.log` 文件内容
- 托盘菜单保留 cpolar/openlist 外部浏览器快捷入口

#### 4.2.6 变更文件列表

| 操作 | 文件 |
|------|------|
| 新增 | `src/OpenCpolarSync.Client/`（WPF 项目，~15 个文件，比方案一少一半） |
| 新增 | `installer/setup.iss` |
| 保留 | `Cpolar/`、`Openlist/`、`Watchdog/`（运行时实际使用） |
| 修改 | `README.md` |

#### 4.2.7 优点

1. **开发量小**：守护逻辑复用现有已验证的 PowerShell 脚本，WPF 只需做进程管理和 UI
2. **风险低**：守护逻辑已经过生产验证（Git 历史显示多次边界修复），重写引入新 Bug 的风险高
3. **体积小**：无需 WebView2/CefSharp，安装包仅 ~80MB（主要是 openlist.zip）
4. **Win7 完全兼容**：无 WebView2 依赖，PowerShell 5.0+ Win7 自带
5. **Watchdog 保活保留**：继续使用计划任务方案，主程序崩溃不影响守护运行

#### 4.2.8 缺点

1. **体验割裂**：PowerShell 脚本在后台运行，WPF 与脚本之间通过文件/Mutex 间接通信，状态更新有延迟
2. **PowerShell 依赖**：需确保执行策略允许脚本运行，部分企业环境可能限制
3. **日志分散**：守护日志在 `logs/guard.log`，WPF 日志在别处，需统一读取
4. **openlist 配置跳出**：外部浏览器打开，不在主程序内
5. **脚本进程管理复杂**：停止脚本需找到 powershell.exe 进程并优雅终止，可能残留子进程
6. **托盘与脚本状态同步延迟**：WPF 轮询 Mutex 有间隔（如 2 秒），状态非实时

#### 4.2.9 适用场景

- 希望快速出 MVP，降低开发风险
- 目标用户有一定技术基础，能接受"管理壳 + 后台脚本"的模式
- Win7 用户占比较高，不能接受 WebView2 额外依赖
- 希望保留现有 Watchdog 计划任务的健壮保活能力

---

## 五、方案对比

| 维度 | 方案一：全内嵌一体化 | 方案二：轻量壳+复用脚本 |
|------|---------------------|------------------------|
| **开发工作量** | 高（~25-30 人天） | 中（~12-15 人天） |
| **守护逻辑** | C# 重写 | 复用现有 PowerShell |
| **风险** | 中（重写可能引入新 Bug） | 低（已验证逻辑） |
| **用户体验** | 最佳（统一界面、cpolar+openlist 双内嵌 Web、实时状态） | 一般（状态有延迟、cpolar/openlist 均外部浏览器跳出） |
| **Win7 兼容性** | ⚠️ WebView2 需额外安装 Runtime | ✅ 完全兼容（无额外依赖） |
| **安装包体积** | ~85 MB | ~80 MB |
| **托盘集成度** | 高（直接控制守护） | 中（通过 Mutex 间接判活） |
| **配置校验** | ✅ WPF 表单实时校验 | ✅ 同方案一 |
| **Watchdog 保活** | 弱（主程序在则守护在） | 强（独立计划任务） |
| **可维护性** | 高（单一 C# 代码库） | 中（C# + PowerShell 双栈） |
| **钉钉推送** | C# 实现（HttpClient） | 复用脚本（Invoke-RestMethod） |
| **退出程序行为** | 关闭→托盘；退出→守护全停 | 关闭→托盘；退出→守护继续跑（计划任务保活） |

### 关键差异总结

两个方案的**本质差异**在于守护逻辑的归属：
- **方案一**：WPF 主程序即守护引擎，程序与守护同生共死
- **方案二**：WPF 是管理壳，守护由独立 PowerShell 进程承担，WPF 退出不影响守护

这直接决定了：
1. 退出主程序后守护是否继续运行
2. 是否需要重写已验证的守护逻辑
3. Win7 上是否有额外依赖

---

## 六、建议

### 推荐方案：方案一（全内嵌一体化），但采用分阶段实施策略

**推荐理由**：

1. **用户体验是核心价值**：本项目的目标就是将脚本工具"产品化"，方案一的统一界面、内嵌 Web、实时状态才是真正的产品体验。方案二本质上还是"脚本 + 壳"，用户仍然能感知到底层脚本的存在。

2. **长期可维护性更好**：单一 C# 代码库比 C# + PowerShell 双栈更容易维护、测试和迭代。PowerShell 脚本的调试和单元测试远不如 C# 成熟。

3. **Win7 问题可缓解**：
   - WebView2 在 Win10 1803+ 系统自带，Win7 用户可在安装时检测并引导安装 Evergreen Runtime（Inno Setup 可自动下载安装）
   - 若 Win7 用户拒绝安装 WebView2，自动降级为外部浏览器打开 openlist 管理界面（功能不缺失，只是体验降级）

4. **Watchdog 保活可补强**：
   - 主程序注册为开机自启（注册表 Run 键）
   - 主程序启动时检测单实例（Mutex），崩溃后重启系统自动恢复
   - 可选：注册一个轻量计划任务，仅在主程序进程不存在时拉起主程序（类似现有 Watchdog，但只守护主程序一个进程）

### 分阶段实施策略

| 阶段 | 内容 | 交付物 | 预计工期 |
|------|------|--------|----------|
| **P0** | WPF 主程序框架 + 托盘 + cpolar 配置表单 | 可运行的 WPF 程序，能编辑 config.json | 5 人天 |
| **P1** | C# 守护引擎（cpolar 隧道监控 + 钉钉推送） | 守护功能完整，替代 CpolarGuard.ps1 | 8 人天 |
| **P2** | openlist 进程守护 + WebView2 嵌入（含 Win7 降级） | openlist 管理完整 | 5 人天 |
| **P3** | Inno Setup 安装包（集成 cpolar MSI + openlist.zip + 检测逻辑） | 可分发的 .exe 安装包 | 4 人天 |
| **P4** | 日志查看 + 开机自启 + 测试 + 文档 | 正式发布 v1.0 | 3 人天 |

**合计**：~25 人天

### 不推荐方案二的原因

方案二虽然开发快、风险低，但它是一个"过渡方案"——用户最终还是会要求更好的体验（内嵌 Web、实时状态、统一日志），届时仍需迁移到方案一。与其做两次，不如一次到位。

如果工期确实紧张，可以先做方案二的 MVP（~12 人天）快速验证用户反馈，再迭代到方案一。但这需要接受"返工"的成本。

---

## 七、待确认事项

以下事项需要用户确认后才能进入详细设计/开发：

| 编号 | 事项 | 选项 | 影响 |
|------|------|------|------|
| Q1 | cpolar 安装包是否使用项目中已有的 `cpolar_amd64.msi`（2023年版本）？ | A. 用现有包 B. 下载最新版 | 安装包内容、cpolar 功能版本 |
| Q2 | openlist 是否使用项目中已有的 `openlist.zip`？ | A. 用现有包 B. 下载最新版 | 安装包内容、openlist 功能版本 |
| Q3 | Win7 用户占比大概多少？是否值得为 Win7 做 WebView2 自动安装？ | A. 占比高，必须做 B. 占比低，降级即可 | 安装器复杂度、用户体验 |
| Q4 | 关闭主窗口后，守护是否继续运行？ | A. 继续（托盘常驻） B. 停止 | 守护引擎设计、托盘行为 |
| Q5 | 是否需要保留现有 PowerShell 脚本作为备用/命令行模式？ | A. 保留 B. 完全替代 | 仓库结构、维护成本 |
| Q6 | 钉钉推送功能是否在 WPF 中完整实现？还是仅保留配置、推送由其他方式？ | A. 完整实现 B. 仅配置 | CpolarMonitor 开发量 |
| Q7 | 安装程序是否需要支持"仅安装主程序，不安装 cpolar/openlist"的自定义选项？ | A. 支持自定义 B. 强制一并安装 | Inno Setup 脚本复杂度 |

---

## 八、附录

### 8.1 参考资料

- [Hardcodet.NotifyIcon.Wpf](https://www.nuget.org/packages/Hardcodet.NotifyIcon.Wpf/) — WPF 托盘图标库
- [WebView2 文档](https://learn.microsoft.com/zh-cn/microsoft-edge/webview2/) — 微软 Edge Chromium 嵌入控件
- [Inno Setup 文档](https://jrsoftware.org/isinfo.php) — 安装包制作工具
- [cpolar 官方文档](https://www.cpolar.com/docs) — cpolar 使用指南
- [Alist 官方文档](https://alist.nn.ci/zh/) — openlist 底层 Alist 文档

### 8.2 现有脚本与 C# 实现对照

| 现有 PowerShell 功能 | C# 对应实现 | 难度 |
|----------------------|------------|------|
| `CpolarGuard.ps1` 登录获取 Token | `HttpClient.PostAsync` + `JsonSerializer` | 低 |
| 轮询 `/api/v1/tunnels` | `HttpClient.GetAsync` + `System.Threading.Timer` | 低 |
| 变更检测（新增/更新/重连/离线） | LINQ 对比 + 自定义相等比较器 | 中 |
| 钉钉 Webhook 推送 | `HttpClient.PostAsync` | 低 |
| 配置热重载 | `FileSystemWatcher` 监听 config.json | 低 |
| 日志周轮转 | 自定义 `FileLogger` + `DateTime` 周计算 | 中 |
| `OpenlistGuard.ps1` 进程守护 | `Process.GetProcessesByName` + `Timer` | 低 |
| Mutex 防多实例 | `System.Threading.Mutex` | 低 |
| `Watchdog` 计划任务保活 | 可选：`TaskService` 或轻量计划任务 | 中 |

### 8.3 术语表

| 术语 | 说明 |
|------|------|
| WPF | Windows Presentation Foundation，微软桌面 UI 框架 |
| WebView2 | 基于 Edge Chromium 的嵌入式 Web 浏览器控件 |
| Inno Setup | 免费的 Windows 安装程序制作工具 |
| Mutex | 互斥体，用于进程间同步和单实例检测 |
| S4U | Service for User，Windows 计划任务的非交互登录类型 |
| JWT | JSON Web Token，cpolar API 的鉴权令牌 |
