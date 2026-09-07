# OpenCpolarSync 界面重构设计方案 — 参考 Ghost-Downloader-3 Fluent Design

## 需求理解

**需求**：参考 Ghost-Downloader-3（https://github.com/XiaoYouChR/Ghost-Downloader-3）的界面实现方案，对 OpenCpolarSync 的 WPF 界面进行重构。

**约束**：
- 技术栈不变：WPF + .NET Framework 4.8 + x64
- 支持 Win7 至最新 Windows
- 保留现有功能（守护、配置、日志、托盘、设置）
- 不引入重型第三方 UI 框架（保持项目轻量）

**边界**：仅重构界面层（XAML + 样式 + 窗口行为），不改动 Services/Models 业务逻辑。

---

## Ghost-Downloader-3 界面实现方案分析

### 技术栈

| 层 | 技术 | 说明 |
|----|------|------|
| 语言 | Python 3 | — |
| UI 框架 | PySide6 (Qt 6) | 跨平台 |
| 组件库 | PyQt-Fluent-Widgets (qfluentwidgets) | 微软 Fluent Design 风格组件库 |
| 主窗口基类 | `MSFluentWindow` | 左侧导航 + 右侧内容区，内置路由 |
| 编译 | Nuitka | Python 编译为原生 exe |

### 核心架构

```
MainWindow (MSFluentWindow)
├── 自定义标题栏 (TitleBar)
│   ├── 窗口图标 + 标题
│   ├── 居中搜索框 (SearchLineEdit)
│   └── 最小/最大/关闭按钮
├── 左侧导航栏 (NavigationInterface)
│   ├── 顶部区：下载任务页（主要功能）
│   ├── 顶部区：新建任务按钮（不可选中，操作型）
│   ├── 底部区：设置页
│   └── 插件页：动态注入
└── 右侧内容区 (QStackedWidget)
    ├── TaskPage（懒加载）
    ├── SettingPage（懒加载）
    └── 插件页（懒加载）
```

### 关键设计特征

1. **Fluent Design 视觉语言**
   - 亚克力/云母背景效果（Windows: Mica/Acrylic/Aero，通过 `DwmSetWindowAttribute` / `SetWindowCompositionAttribute` P/Invoke）
   - 主题色跟随系统强调色（`QPalette.Accent`）
   - 浅色/深色/自动三种主题模式，监听系统配色变化

2. **导航模式**
   - 左侧固定导航栏，顶部放主要功能，底部放设置
   - 导航项 = 图标 + 文字，选中态有圆角指示器
   - 支持「不可选中的操作按钮」（如新建任务）
   - 页面懒加载（首次点击才创建，QStackedWidget + qrouter 路由）

3. **自定义无边框窗口**
   - 自绘标题栏，窗口阴影、圆角
   - Windows 10 以下降级为系统标题栏
   - 记住窗口位置和大小

4. **通知与对话框**
   - `InfoBar`：右下角弹出式通知（成功/警告/错误/信息），可带操作按钮
   - `MessageBox`：遮罩式对话框（半透明背景遮罩 + 居中卡片）
   - 替代原生 MessageBox，视觉统一

5. **关闭行为**
   - 可配置：退出程序 / 后台运行 / 每次询问
   - 对话框带「记住我的选择」CheckBox

6. **交互细节**
   - 拖拽文件到窗口添加任务（半透明遮罩提示）
   - 页面切换动画
   - 搜索框随页面动态显示/隐藏

---

## 本项目现状

| 维度 | 当前实现 | 与 Ghost 的差距 |
|------|---------|----------------|
| 窗口 | 系统标题栏，有边框 | 无自定义标题栏、无圆角阴影 |
| 导航 | 左侧 220px 导航栏，Visibility 切换页面 | 结构类似，但样式较朴素 |
| 主题 | 浅色/深色，ThemeManager 修改画笔 | 无自动模式、不跟随系统强调色 |
| 背景 | 纯色背景 | 无亚克力/Mica 效果 |
| 通知 | 原生 MessageBox + 托盘气泡 | 无 InfoBar 式通知 |
| 对话框 | 原生 MessageBox | 无遮罩式对话框 |
| 页面加载 | 全部预创建 | 非懒加载 |
| 组件 | 自定义样式（App.xaml） | 样式基础，无 Fluent 质感 |

---

## 方案一：完整 Fluent Design 重构（推荐）

**一句话概括**：自定义无边框窗口 + Fluent 设计语言 + 亚克力背景 + 导航栏重构 + InfoBar 通知系统，全面对齐 Ghost-Downloader-3 的视觉与交互体验。

### 核心思路

在 WPF 中通过 P/Invoke 和自定义样式实现 Fluent Design 的核心视觉效果，不依赖第三方 UI 框架，保持项目轻量。

### 详细设计

#### 1. 自定义无边框窗口（FluentWindow）

- 新建 `FluentWindow` 基类，继承 `Window`
- `WindowStyle=None` + `AllowsTransparency=True`，自绘标题栏
- 标题栏布局：左侧 Logo + 标题，右侧最小/最大/关闭按钮（Fluent 风格 hover 效果）
- 窗口圆角（`CornerRadius`）+ 阴影（`DropShadowEffect` 或 DWM 阴影）
- 拖拽移动：标题栏 `MouseLeftButtonDown` + `DragMove()`
- Win7 降级：检测系统版本，Win7 下使用系统标题栏（避免兼容性问题）

```
窗口结构：
<FluentWindow>
  <Border CornerRadius="8" Background="透明或亚克力">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="36"/>  <!-- 自定义标题栏 -->
        <RowDefinition Height="*"/>   <!-- 内容区 -->
      </Grid.RowDefinitions>
      <!-- 标题栏 -->
      <Grid Grid.Row="0">
        <StackPanel Orientation="Horizontal">
          <Image Source="app.ico" Width="16"/>
          <TextBlock Text="OpenCpolarSync"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button Min/Max/Close 样式/>
        </StackPanel>
      </Grid>
      <!-- 内容区 -->
      <Grid Grid.Row="1">
        <!-- 左侧导航 + 右侧内容 -->
      </Grid>
    </Grid>
  </Border>
</FluentWindow>
```

#### 2. 亚克力/Mica 背景效果

- 新建 `WindowEffect` 静态类，封装 P/Invoke：
  - `DwmSetWindowAttribute`：设置 Mica / MicaAlt（Win11 22H2+）
  - `SetWindowCompositionAttribute`：设置 Acrylic 模糊（Win10+）
- 配置项：`背景效果 = None / Acrylic / Mica / MicaAlt`
- Win7/Win8 降级为纯色背景
- 深色/浅色模式下使用不同的模糊色调

```csharp
// 核心 P/Invoke
[DllImport("dwmapi.dll")]
private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

// Mica: DWMWA_SYSTEMBACKDROP_TYPE = 38, value = 2(Mica) / 4(MicaAlt)
// Acrylic: SetWindowCompositionAttribute, ACCENT_ENABLE_ACRYLICBLURBEHIND = 4
```

#### 3. 导航栏重构（FluentNavigationView）

- 左侧导航栏宽度 240px，半透明背景（亚克力延伸到导航区）
- 导航项样式：
  - 图标（Fluent 风格 Segoe MDL2 Assets 字体图标）+ 文字
  - 选中态：圆角矩形背景（品牌色半透明）+ 左侧指示条
  - Hover 态：浅灰背景
- 分区：顶部（总览/配置）、底部（设置/关于）
- 页面懒加载：首次点击时创建 UserControl，后续切换用 Visibility
- 导航项支持「操作按钮」类型（不可选中，如「启动全部守护」可放导航栏）

#### 4. Fluent 组件样式

重写 `App.xaml` 中的样式，对齐 Fluent Design：

| 组件 | Fluent 风格要点 |
|------|----------------|
| Button | 圆角 4px，hover 微透明，按下下沉，Primary 按钮品牌色填充 |
| TextBox | 圆角 4px，focus 时边框品牌色，底部下划线动画 |
| CheckBox | 圆角勾选框，选中时品牌色填充 + 白色对勾 |
| Card | 圆角 8px，微阴影，hover 时阴影加深 |
| ScrollBar | 细滚动条，hover 时变宽 |
| ComboBox | 圆角下拉，弹出项圆角 |

#### 5. InfoBar 通知系统

- 新建 `InfoBar` 组件，替代原生 MessageBox 用于操作反馈
- 右下角弹出，4 种类型：成功（绿）/警告（黄）/错误（红）/信息（蓝）
- 带图标 + 标题 + 内容，可自动消失（3秒）或手动关闭
- 支持带操作按钮（如「撤销」「查看」）
- 多个通知堆叠显示

#### 6. 遮罩式对话框（MaskDialog）

- 新建 `MaskDialog` 基类，替代原生 MessageBox 用于确认/设置
- 半透明黑色遮罩覆盖整个窗口，居中显示卡片
- 卡片圆角 8px，带标题 + 内容 + 按钮区
- 支持自定义内容（不只是文字）

#### 7. 主题系统增强

- 新增「自动」模式：监听系统配色变化（`Microsoft.Win32.SystemEvents.UserPreferenceChanged`）
- 主题色跟随系统强调色：读取注册表 `HKCU\Software\Microsoft\Windows\DWM\ColorizationColor` 或 `GetSysColor`
- 主题切换动画：颜色渐变过渡（`ColorAnimation`）

#### 8. 关闭行为配置

- 设置页新增「关闭窗口时」选项：退出程序 / 最小化到托盘 / 每次询问
- 选择「每次询问」时弹出 MaskDialog，带「记住我的选择」CheckBox
- 配置持久化到 config.json

### 变更文件列表

| 操作 | 文件 |
|------|------|
| 新增 | `Components/FluentWindow.cs`（无边框窗口基类） |
| 新增 | `Components/WindowEffect.cs`（P/Invoke 背景效果） |
| 新增 | `Components/InfoBar.cs` + `InfoBar.xaml`（通知组件） |
| 新增 | `Components/MaskDialog.cs` + `MaskDialog.xaml`（遮罩对话框） |
| 新增 | `Components/FluentNavigationView.xaml`（导航栏） |
| 修改 | `MainWindow.xaml` / `.cs`（继承 FluentWindow，重构布局） |
| 修改 | `App.xaml`（重写全部样式为 Fluent 风格） |
| 修改 | `Services/ThemeManager.cs`（增加自动模式、系统强调色） |
| 修改 | `Views/SettingsTab.xaml`（增加关闭行为、背景效果配置） |
| 修改 | `Models/CpolarConfig.cs`（增加 CloseMode、BackgroundEffect 字段） |

### 优点

- 视觉效果全面对齐 Ghost-Downloader-3，达到大厂软件水准
- 亚克力/Mica 背景 + 自定义标题栏，现代感强
- InfoBar + MaskDialog 替代原生弹窗，交互体验统一
- 主题自动跟随系统，用户体验好

### 缺点

- 工作量大（约 3-4 人天）
- P/Invoke 背景效果在 Win7 需降级处理
- 无边框窗口需处理窗口拖拽、缩放、系统菜单等边界情况
- .NET Framework 4.8 部分 Win11 API（Mica）需动态加载，不能直接引用

### 适用场景

追求极致视觉体验，愿意投入较多工作量，且用户主要在 Win10/Win11 上运行。

---

## 方案二：渐进式 Fluent 化（轻量重构）

**一句话概括**：保留现有窗口和导航结构，仅重写组件样式和配色，引入亚克力背景和 InfoBar 通知，不做无边框窗口重构。

### 核心思路

最小改动原则，在现有架构基础上引入 Fluent Design 的视觉元素，不改动窗口结构。

### 详细设计

1. **组件样式重写**：App.xaml 中 Button/TextBox/CheckBox/Card 等样式改为 Fluent 风格（圆角、微阴影、hover 效果）
2. **亚克力背景**：通过 `SetWindowCompositionAttribute` 给窗口设置 Acrylic 模糊，内容区背景设为半透明
3. **导航栏优化**：选中态改为圆角指示器，图标改用 Segoe MDL2 Assets
4. **InfoBar 通知**：新增 InfoBar 组件，用于保存成功/失败等操作反馈
5. **主题增强**：增加自动模式，跟随系统配色
6. **保留**：系统标题栏、现有页面结构、现有导航逻辑

### 变更文件列表

| 操作 | 文件 |
|------|------|
| 新增 | `Components/WindowEffect.cs` |
| 新增 | `Components/InfoBar.cs` + `.xaml` |
| 修改 | `App.xaml`（样式 Fluent 化） |
| 修改 | `MainWindow.xaml`（背景半透明、导航样式微调） |
| 修改 | `Services/ThemeManager.cs`（自动模式） |

### 优点

- 工作量小（约 1 人天）
- 风险低，不改动窗口结构
- 视觉提升明显

### 缺点

- 系统标题栏与 Fluent 风格不协调，整体感打折扣
- 无 Mica 效果（仅 Acrylic）
- 无遮罩式对话框

### 适用场景

希望快速提升视觉效果，投入有限，能接受系统标题栏。

---

## 方案对比

| 维度 | 方案一：完整 Fluent 重构 | 方案二：渐进式 Fluent 化 |
|------|------------------------|------------------------|
| 工作量 | 3-4 人天 | 1 人天 |
| 视觉效果 | ⭐⭐⭐⭐⭐（对齐 Ghost） | ⭐⭐⭐（明显提升但有短板） |
| 无边框窗口 | ✅ | ❌（保留系统标题栏） |
| 亚克力/Mica | ✅（Mica+Acrylic） | ✅（仅 Acrylic） |
| InfoBar 通知 | ✅ | ✅ |
| 遮罩对话框 | ✅ | ❌ |
| 主题自动跟随 | ✅ | ✅ |
| Win7 兼容 | 需降级处理 | 较好 |
| 风险 | 中（P/Invoke + 无边框边界） | 低 |
| 侵入性 | 高（主窗口重写） | 低（样式为主） |

---

## 建议

**推荐方案一（完整 Fluent 重构）**，理由：

1. 用户明确要求「参考这个项目的界面实现方案进行重构」，方案一才能真正对齐 Ghost-Downloader-3 的体验
2. 本项目用户群主要在 Win10/Win11（cpolar/openlist 本身也要求较新系统），Win7 降级影响有限
3. 自定义无边框窗口 + 亚克力背景是 Fluent Design 的核心辨识度，缺少这些只是「换了配色」而非「重构」
4. InfoBar + MaskDialog 不仅是视觉，也提升交互体验（操作反馈不打断流程）

**实施建议**：分阶段交付，降低风险：
- 阶段 1：Fluent 组件样式 + 亚克力背景 + InfoBar（视觉基础，1 人天）
- 阶段 2：自定义无边框窗口 + 导航栏重构（结构升级，1.5 人天）
- 阶段 3：MaskDialog + 主题自动 + 关闭行为配置（体验完善，0.5 人天）

每个阶段独立可运行，可随时暂停。
