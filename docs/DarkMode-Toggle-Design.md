# 深色模式切换按钮设计方案

## 需求理解

- **目标**：为 OpenCpolarSync 添加深色/浅色模式切换按钮
- **约束**：按钮控件样式与现有按钮体系（PrimaryButton / SecondaryButton / GhostButton）保持一致
- **设计语言**：Linear / Vercel / VS Code 风格，现代化、简洁、有微动效
- **范围**：仅设计切换按钮控件样式 + 深色模式配色方案，不包含完整的主题切换逻辑实现

---

## 项目现状分析

### 现有按钮设计语言

| 维度 | 规范 |
|------|------|
| 圆角 | 6px（按钮）、8px（导航项）、10px（卡片） |
| 品牌色 | #4F46E5（靛蓝），hover #4338CA |
| 内边距 | 16,8（主/次按钮）、10,6（幽灵按钮） |
| 字号 | 13px，字重 SemiBold（主按钮）/ Regular（次/幽灵） |
| 字体 | Segoe UI, Microsoft YaHei UI |
| Hover 效果 | 主按钮加深背景、次按钮浅灰背景+深边框、幽灵按钮浅灰背景+深色文字 |
| 光标 | Hand |

### 现有配色体系（浅色）

| 令牌 | 色值 | 用途 |
|------|------|------|
| BgPrimary | #FFFFFF | 主背景、卡片背景 |
| BgSecondary | #F9FAFB | 内容区背景 |
| BgTertiary | #F3F4F6 | 三级背景、hover 背景 |
| BgSidebar | #FAFAFA | 侧边栏背景 |
| TextPrimary | #111827 | 主文字 |
| TextSecondary | #6B7280 | 次文字 |
| TextTertiary | #9CA3AF | 三级文字、占位符 |
| BorderBrush | #E5E7EB | 边框 |
| BorderLightBrush | #F3F4F6 | 浅边框、分隔线 |

---

## 方案一：图标切换按钮（推荐）

### 一句话概括

在标题栏右侧放置一个幽灵样式的图标按钮，太阳/月亮图标随当前主题切换，点击即切换模式。

### 设计细节

**控件类型**：Button（复用 GhostButton 样式基础，自定义图标）

**位置**：顶部标题栏右侧，"启动全部守护"按钮左侧

**尺寸**：32×32px（正方形图标按钮，比普通按钮更紧凑）

**视觉状态**：

| 状态 | 浅色模式下 | 深色模式下 |
|------|-----------|-----------|
| 默认 | 透明背景 + 月亮图标（#6B7280） | 透明背景 + 太阳图标（#9CA3AF） |
| Hover | #F3F4F6 背景 + 月亮图标（#111827） | #2D2D3A 背景 + 太阳图标（#E5E7EB） |
| Pressed | 透明度 0.85 | 透明度 0.85 |

**图标**：
- 浅色模式显示 **月亮图标**（表示点击可切换到深色）
- 深色模式显示 **太阳图标**（表示点击可切换到浅色）
- 图标使用 Path 几何绘制，16×16 视口，线条风格（2px 描边）

**过渡动画**：
- 背景色过渡：150ms 缓动
- 图标切换：200ms 淡入淡出（旧图标淡出→新图标淡入）
- 可使用 `VisualStateManager` 或简单的 `DoubleAnimation` 实现

**XAML 结构示意**：
```xml
<Button x:Name="ThemeToggleButton" Style="{StaticResource IconButton}"
        Width="32" Height="32" Padding="0"
        Click="ThemeToggleButton_Click">
    <Grid>
        <Path x:Name="IconSun" Data="..." Visibility="Collapsed" .../>
        <Path x:Name="IconMoon" Data="..." Visibility="Visible" .../>
    </Grid>
</Button>
```

### 优点

- ✅ 与现有 GhostButton 设计语言完全一致
- ✅ 占用空间小，不破坏标题栏布局
- ✅ 太阳/月亮图标是行业通用语义，用户一眼就能理解
- ✅ 实现简单，仅需一个 Button + 两个 Path 图标
- ✅ VS Code、Linear、GitHub 等大厂均采用此模式

### 缺点

- ❌ 没有"跟随系统"选项（仅支持浅色/深色二选一）
- ❌ 纯图标按钮对新用户可能需要学习成本（但太阳/月亮已足够通用）

### 适用场景

追求简洁、空间有限、用户群体熟悉现代软件交互的场景。

---

## 方案二：现代化滑动开关（ToggleSwitch）

### 一句话概括

自定义 ToggleSwitch 控件，胶囊形轨道 + 圆形滑块，左侧太阳图标右侧月亮图标，滑块滑动指示当前模式。

### 设计细节

**控件类型**：自定义 UserControl（基于 ToggleButton 或 CheckBox 重写模板）

**位置**：侧边栏底部，"全局状态"卡片上方，或设置页面中

**尺寸**：52×28px（标准 iOS/Windows 11 开关尺寸）

**视觉状态**：

| 状态 | 浅色模式 | 深色模式 |
|------|---------|---------|
| 轨道背景 | #E5E7EB（灰） | #4F46E5（品牌色） |
| 滑块位置 | 左侧（偏移 2px） | 右侧（偏移 22px） |
| 滑块颜色 | #FFFFFF（白） | #FFFFFF（白） |
| 滑块阴影 | 微阴影（0,1,2,0.1） | 微阴影 |
| 太阳图标 | 显示（#F59E0B） | 隐藏 |
| 月亮图标 | 隐藏 | 显示（#C7D2FE） |

**过渡动画**：
- 滑块位置：200ms Cubic Ease 缓动
- 轨道背景色：200ms 过渡
- 图标淡入淡出：150ms

**XAML 结构示意**：
```xml
<ToggleButton x:Name="ThemeSwitch" Style="{StaticResource ThemeToggleSwitch}">
    <ControlTemplate TargetType="ToggleButton">
        <Grid Width="52" Height="28">
            <Border x:Name="Track" CornerRadius="14" Background="#E5E7EB"/>
            <Canvas x:Name="ThumbContainer">
                <Ellipse x:Name="Thumb" Width="24" Height="24" Fill="White" Canvas.Left="2" Canvas.Top="2"/>
            </Canvas>
            <Path x:Name="IconSun" ... HorizontalAlignment="Left" Margin="8,0,0,0"/>
            <Path x:Name="IconMoon" ... HorizontalAlignment="Right" Margin="0,0,8,0"/>
        </Grid>
        <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
                <!-- 深色模式：滑块右移 + 轨道品牌色 -->
            </Trigger>
        </ControlTemplate.Triggers>
    </ControlTemplate>
</ToggleButton>
```

### 优点

- ✅ 现代化感最强，Windows 11 / iOS 风格
- ✅ 滑动动画有愉悦感，用户反馈明确
- ✅ 太阳/月亮图标在轨道两侧，语义清晰
- ✅ 品牌色在深色模式下点亮，视觉亮点

### 缺点

- ❌ 占用空间比图标按钮大（52×28 vs 32×32）
- ❌ 不适合放在标题栏（高度不匹配），更适合侧边栏或设置页
- ❌ 实现复杂度较高（自定义控件模板 + 动画）
- ❌ WPF 原生没有 ToggleSwitch，需要完全自定义

### 适用场景

侧边栏设置区域、独立设置页面，追求视觉精致度和交互愉悦感的场景。

---

## 方案三：分段控件（Segmented Control）

### 一句话概括

类似 macOS / iOS 的分段控件，"浅色 / 深色"两个选项，点击切换，选中项高亮。

### 设计细节

**控件类型**：自定义 ListBox 或两个 Button 组合

**位置**：侧边栏底部，或设置页面中

**尺寸**：约 120×32px

**视觉状态**：

| 元素 | 浅色模式选中 | 深色模式选中 |
|------|------------|------------|
| 容器背景 | #F3F4F6（圆角 8px） | #2D2D3A |
| 选中项背景 | #FFFFFF（白卡片 + 微阴影） | #3D3D4A |
| 选中项文字 | #111827（粗体） | #FFFFFF |
| 未选中项文字 | #6B7280 | #9CA3AF |
| 图标 | 太阳/月亮小图标 | 同左 |

**过渡动画**：
- 选中项背景滑动：200ms 缓动
- 文字颜色过渡：150ms

### 优点

- ✅ 语义最清晰，文字+图标双重表达
- ✅ macOS / iOS 用户熟悉
- ✅ 可扩展为"浅色/深色/跟随系统"三选项

### 缺点

- ❌ 占用空间最大（约 120×32）
- ❌ 不适合标题栏，只能放侧边栏或设置页
- ❌ 视觉上略显笨重，不如图标按钮简洁
- ❌ WPF 实现分段控件的滑动选中效果较复杂

### 适用场景

设置页面、偏好配置区域，需要明确文字标签的场景。

---

## 方案对比

| 维度 | 方案一：图标按钮 | 方案二：滑动开关 | 方案三：分段控件 |
|------|----------------|----------------|----------------|
| 占用空间 | 小（32×32） | 中（52×28） | 大（120×32） |
| 适合位置 | 标题栏 | 侧边栏/设置页 | 侧边栏/设置页 |
| 实现复杂度 | 低 | 高 | 中高 |
| 现代化感 | ★★★★ | ★★★★★ | ★★★ |
| 语义清晰度 | ★★★★ | ★★★★★ | ★★★★★ |
| 与现有样式一致性 | ★★★★★ | ★★★★ | ★★★ |
| 动效愉悦感 | ★★★ | ★★★★★ | ★★★ |
| 可扩展性 | 低 | 低 | 高（可加跟随系统） |
| 大厂参考 | VS Code / Linear / GitHub | Windows 11 / iOS | macOS / iOS |

---

## 推荐方案

**推荐方案一：图标切换按钮**，理由：

1. **与现有设计语言最一致**：复用 GhostButton 样式体系，6px 圆角、hover 浅灰背景、Hand 光标，完全融入现有界面
2. **位置最合理**：放在标题栏右侧（"启动全部守护"按钮左侧），是用户最容易发现的位置，不破坏现有布局
3. **实现成本最低**：一个 Button + 两个 Path 图标 + 简单的 Visibility 切换，无需自定义控件
4. **行业标准**：VS Code、Linear、GitHub、Notion 等现代软件均采用太阳/月亮图标按钮切换主题
5. **空间效率最高**：32×32px，在标题栏中不显得突兀

**方案二（滑动开关）可作为后续增强**：如果未来增加设置页面，可以在设置页中放置更精致的滑动开关。

---

## 深色模式配色方案

配套深色模式的完整配色令牌（供实现时参考）：

| 令牌 | 浅色值 | 深色值 | 说明 |
|------|--------|--------|------|
| BgPrimary | #FFFFFF | #1A1B26 | 主背景、卡片背景 |
| BgSecondary | #F9FAFB | #16161E | 内容区背景 |
| BgTertiary | #F3F4F6 | #2D2D3A | 三级背景、hover 背景 |
| BgSidebar | #FAFAFA | #1E1E2E | 侧边栏背景 |
| TextPrimary | #111827 | #E5E7EB | 主文字 |
| TextSecondary | #6B7280 | #9CA3AF | 次文字 |
| TextTertiary | #9CA3AF | #6B7280 | 三级文字 |
| BorderBrush | #E5E7EB | #3D3D4A | 边框 |
| BorderLightBrush | #F3F4F6 | #2D2D3A | 浅边框、分隔线 |
| BrandBrush | #4F46E5 | #6366F1 | 品牌色（深色模式略亮） |
| BrandHoverBrush | #4338CA | #818CF8 | 品牌色 hover |
| BrandLightBrush | #EEF2FF | #312E81 | 品牌色浅底 |
| SuccessBrush | #10B981 | #34D399 | 成功 |
| WarningBrush | #F59E0B | #FBBF24 | 警告 |
| ErrorBrush | #EF4444 | #F87171 | 错误 |
| InfoBrush | #3B82F6 | #60A5FA | 信息 |
| 日志区背景 | #1E1E2E | #0D0E14 | 日志终端背景 |
| 日志区文字 | #CDD6F4 | #A6ADC8 | 日志终端文字 |

### 深色模式设计要点

1. **品牌色略提亮**：深色背景下 #4F46E5 对比度不足，提亮为 #6366F1
2. **纯黑不用**：背景使用 #1A1B26 / #16161E 而非纯黑 #000000，减少视觉疲劳
3. **文字对比度**：主文字 #E5E7EB（非纯白），在深色背景上更柔和
4. **边框可见性**：深色边框 #3D3D4A，确保卡片边界清晰
5. **阴影调整**：深色模式下阴影效果减弱，更多依赖边框区分层次

---

## 实现建议（供后续编码参考）

1. **资源字典分离**：将浅色和深色配色分别放入 `LightTheme.xaml` 和 `DarkTheme.xaml` 资源字典
2. **DynamicResource 引用**：所有控件使用 `DynamicResource` 而非 `StaticResource` 引用颜色令牌（当前 App.xaml 中大部分已使用 DynamicResource）
3. **主题切换逻辑**：在 App.xaml.cs 中实现 `ToggleTheme()` 方法，切换 `Application.Current.Resources.MergedDictionaries`
4. **主题持久化**：将用户选择保存到 `Settings` 或配置文件，下次启动时恢复
5. **按钮实现**：方案一的图标按钮可直接在 MainWindow.xaml 标题栏中添加，使用 `Path` 绘制太阳/月亮图标
