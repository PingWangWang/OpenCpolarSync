using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using OpenCpolarSync.Client.Components;
using OpenCpolarSync.Client.Models;
using OpenCpolarSync.Client.Services;
using OpenCpolarSync.Client.ViewModels;
using OpenCpolarSync.Client.Views;

namespace OpenCpolarSync.Client
{
    /// <summary>
    /// MainWindow.xaml 的交互逻辑 — 主窗口，左侧导航 + 内容区，协调守护生命周期
    /// </summary>
    public partial class MainWindow : Window
    {
        private GuardService _guardService;
        private ConfigService _configService;
        private TrayIconComponent _trayIcon;
        private CpolarConfig _currentConfig;
        private readonly string _appDir;
        private string _openlistExePath;
        private string _openlistWorkDir;
        private bool _isExiting;
        private string _currentPage = "dashboard";
        private DispatcherTimer _pidRefreshTimer;
        private bool _themeInitialized;

        public MainWindow()
        {
            try
            {
                InitializeComponent();
                _appDir = AppDomain.CurrentDomain.BaseDirectory;

                InitializeServices();
                InitializeTrayIcon();
                InitializeTabs();
                LoadConfig();

                Loaded += MainWindow_Loaded;
                StartPidRefresh();
                // 应用保存的主题（用户选择持久化），此时深色开关事件尚未就绪，不会触发保存
                ApplySavedTheme();
                // 深色开关在初始化阶段可能触发事件，标记就绪后再允许响应，避免误切换主题
                _themeInitialized = true;
            }
            catch (Exception ex)
            {
                // [修复] 构造函数异常时写入详细日志，便于定位启动失败原因
                try
                {
                    var logPath = Path.Combine(_appDir ?? AppDomain.CurrentDomain.BaseDirectory, "startup-error.log");
                    File.WriteAllText(logPath, $"[构造函数异常] {DateTime.Now:yyyy-MM-dd HH:mm:ss}\n{ex}");
                }
                catch { }
                throw;
            }
        }

        /// <summary>
        /// 启动服务 PID 周期刷新 — 进程可能在守护事件之外被拉起/退出，定时刷新以保持界面 PID 准确
        /// </summary>
        private void StartPidRefresh()
        {
            _pidRefreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
            _pidRefreshTimer.Tick += (s, e) => RefreshProcessIds();
            _pidRefreshTimer.Start();
        }

        /// <summary>
        /// 刷新总览页两个服务的进程 PID
        /// </summary>
        private void RefreshProcessIds()
        {
            if (DashboardTab?.DataContext is DashboardViewModel dv)
            {
                dv.CpolarProcessId = _guardService?.CpolarMonitor.CurrentProcessId ?? 0;
                dv.OpenlistProcessId = _guardService?.OpenlistMonitor.CurrentProcessId ?? 0;
            }
        }

        private void InitializeServices()
        {
            var configPath = GetConfigPath();
            var openlistDir = Path.Combine(_appDir, "openlist");
            _openlistExePath = Path.Combine(openlistDir, "openlist.exe");
            // [修改] 原因：openlist 工作目录原指向其所在 Program Files 子目录，
            //         alist 启动 server 需在该目录写 data（config.json/data.db/日志），
            //         Program Files 对普通用户不可写，导致 openlist 启动后立即退出。
            //         现改为可写的用户级应用数据目录（见 EnsureOpenlistDataDir）。
            _openlistWorkDir = EnsureOpenlistDataDir(openlistDir);

            _configService = new ConfigService(configPath);
            _guardService = new GuardService(_openlistExePath, _openlistWorkDir);

            _guardService.LogMessage += (s, e) => LogsTab?.AppendLog(e);
            _guardService.StatusChanged += OnGuardStatusChanged;

            _configService.ConfigChanged += (s, config) =>
            {
                Dispatcher.Invoke(() =>
                {
                    _currentConfig = config;
                    CpolarConfigTab.LoadConfig(config);
                    _guardService.UpdateCpolarConfig(config);
                    LogsTab.AppendLog("配置已热重载");
                });
            };
            _configService.StartWatching();
        }

        /// <summary>
        /// 计算并确保配置文件所在的用户级可写目录存在，并迁移应用目录下的旧配置
        /// 返回:
        ///     string，config.json 的绝对路径（位于 %LocalAppData%\OpenCpolarSync\config）
        /// </summary>
        private string GetConfigPath()
        {
            // [修改] 原因：原配置放在应用目录（Program Files）下，普通用户无写权限导致保存失败，迁移到用户数据目录
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var dir = Path.Combine(appData, "OpenCpolarSync", "config");
            Directory.CreateDirectory(dir);
            var path = Path.Combine(dir, "config.json");

            // 迁移旧配置（若存在且新位置尚无），避免用户已有设置丢失
            var legacy = Path.Combine(_appDir, "config", "config.json");
            if (!File.Exists(path) && File.Exists(legacy))
            {
                try { File.Copy(legacy, path, false); } catch { }
            }
            return path;
        }

        /// <summary>
        /// 确定并确保 openlist 的可写数据工作目录存在。
        /// 参数:
        ///     openlistDir: 部署目录（Program Files 下的 openlist 子目录），用于探测历史数据
        /// 返回:
        ///     string，openlist 启动时应使用的工作目录（用户级应用数据目录，必然可写）
        /// </summary>
        private string EnsureOpenlistDataDir(string openlistDir)
        {
            // [修改] 原因：原实现把 openlist 工作目录设为其所在 Program Files 子目录，
            //         普通用户无写权限导致 alist 初始化 data 失败而启动即退出。
            //         这里改用 LocalApplicationData（用户级、必然可写）作为工作目录。
            var dataRoot = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var workDir = Path.Combine(dataRoot, "OpenCpolarSync", "openlist");
            Directory.CreateDirectory(workDir);

            // 迁移升级前可能已生成于 Program Files 子目录的历史 data，避免数据丢失；
            // 新目录已存在 data 或历史目录不存在（全新安装）时跳过。
            var legacyData = Path.Combine(openlistDir, "data");
            var newData = Path.Combine(workDir, "data");
            if (!Directory.Exists(newData) && Directory.Exists(legacyData))
            {
                try
                {
                    Directory.Move(legacyData, newData);
                }
                catch
                {
                    // 迁移失败不阻断 openlist：alist 会在新目录重新初始化（首次创建为空配置）。
                }
            }
            return workDir;
        }

        private void InitializeTrayIcon()
        {
            _trayIcon = new TrayIconComponent();
            _trayIcon.Initialize();

            _trayIcon.ShowMainWindowRequested += (s, e) => Dispatcher.Invoke(ShowMainWindow);
            _trayIcon.ExitApplicationRequested += (s, e) => Dispatcher.Invoke(ExitApplication);
            _trayIcon.StartAllRequested += (s, e) => Dispatcher.Invoke(StartAllGuards);
            _trayIcon.StopAllRequested += (s, e) => Dispatcher.Invoke(StopAllGuards);
            _trayIcon.OpenCpolarWebRequested += (s, e) => OpenUrl("http://localhost:9200");
            _trayIcon.OpenOpenlistWebRequested += (s, e) => OpenUrl("http://localhost:5244");
        }

        private void InitializeTabs()
        {
            CpolarConfigTab.SaveConfigRequested += (s, e) => SaveConfig();
            OpenlistConfigTab.SaveConfigRequested += (s, e) => SaveOpenlistConfig();
        }

        public static void OpenUrl(string url)
        {
            try
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                MessageBox.Show($"无法打开浏览器：{ex.Message}", "错误",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void LoadConfig()
        {
            _currentConfig = _configService.Load();
            CpolarConfigTab.LoadConfig(_currentConfig);
            OpenlistConfigTab.LoadConfig(_currentConfig);
        }

        private void SaveConfig()
        {
            var config = CpolarConfigTab.GetConfig();
            var errors = _configService.Validate(config);

            if (errors.Count > 0)
            {
                MessageBox.Show($"配置校验失败：\n{string.Join("\n", errors)}", "配置错误",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            if (_configService.Save(config))
            {
                _currentConfig = config;
                _guardService.UpdateCpolarConfig(config);
                UpdateStatus("配置已保存");
                LogsTab.AppendLog("配置已保存");

                MessageBox.Show("配置保存成功！", "成功", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            else
            {
                MessageBox.Show("配置保存失败，请检查文件权限。", "错误",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        /// <summary>
        /// 保存 Openlist 配置 — 更新管理密码并应用到 alist（admin 密码）
        /// </summary>
        private void SaveOpenlistConfig()
        {
            var password = OpenlistConfigTab.GetPassword();
            _currentConfig.OpenlistPassword = password ?? "";

            if (!_configService.Save(_currentConfig))
            {
                MessageBox.Show("配置保存失败，请检查文件权限。", "错误",
                    MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }

            UpdateStatus("Openlist 配置已保存");
            LogsTab.AppendLog("[Openlist] 配置已保存");

            if (string.IsNullOrEmpty(password))
            {
                LogsTab.AppendLog("[Openlist] 未填写密码，未应用");
            }
            else if (_guardService.OpenlistMonitor.SetAdminPassword(password))
            {
                UpdateStatus("openlist 管理密码已更新");
                LogsTab.AppendLog("[Openlist] openlist 管理密码已应用");
            }
            else
            {
                LogsTab.AppendLog("[Openlist] openlist 管理密码应用失败；配置已保存，可停止 openlist 守护后重新保存重试");
            }

            MessageBox.Show("Openlist 配置保存成功！", "成功", MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private void StartAllGuards()
        {
            if (_currentConfig == null)
            {
                MessageBox.Show("请先配置 Cpolar 参数。", "提示", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            _guardService.StartAll(_currentConfig);
            UpdateStatus("全部守护已启动");
            _trayIcon.ShowBalloonTip("OpenCpolarSync", "全部守护已启动", Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Info);
        }

        private void StopAllGuards()
        {
            _guardService.StopAll();
            UpdateStatus("全部守护已停止");
        }

        private void StartCpolarGuard()
        {
            if (_currentConfig == null)
            {
                MessageBox.Show("请先配置 Cpolar 参数。", "提示", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            _guardService.StartCpolar(_currentConfig);
            UpdateStatus("Cpolar 监控已启动");
        }

        private void OnGuardStatusChanged(object sender, StatusChangedEventArgs e)
        {
            Dispatcher.Invoke(() =>
            {
                var vm = new DashboardViewModel
                {
                    CpolarStatus = e.ServiceName == "Cpolar" ? e.NewStatus : DashboardTab.DataContext is DashboardViewModel dv ? dv.CpolarStatus : ServiceStatus.Stopped,
                    OpenlistStatus = e.ServiceName == "Openlist" ? e.NewStatus : DashboardTab.DataContext is DashboardViewModel dv2 ? dv2.OpenlistStatus : ServiceStatus.Stopped
                };

                if (e.ServiceName == "Openlist")
                {
                    vm.OpenlistProcessId = _guardService.OpenlistMonitor.CurrentProcessId;
                }
                if (e.ServiceName == "Cpolar")
                {
                    vm.CpolarProcessId = _guardService.CpolarMonitor.CurrentProcessId;
                }

                DashboardTab.UpdateViewModel(vm);
                UpdateGlobalStatus(vm.CpolarStatus, vm.OpenlistStatus);
                UpdateStatus($"{e.ServiceName}: {e.Message}");
            });
        }

        /// <summary>
        /// 根据两个服务的状态更新左侧底部全局状态
        /// </summary>
        private void UpdateGlobalStatus(ServiceStatus cpolar, ServiceStatus openlist)
        {
            if (cpolar == ServiceStatus.Running && openlist == ServiceStatus.Running)
            {
                GlobalStatusDot.Fill = (Brush)FindResource("SuccessBrush");
                TxtGlobalStatus.Text = "全部运行中";
                TxtGlobalStatus.Foreground = (Brush)FindResource("TextSecondary");
            }
            else if (cpolar == ServiceStatus.Stopped && openlist == ServiceStatus.Stopped)
            {
                GlobalStatusDot.Fill = (Brush)FindResource("TextTertiary");
                TxtGlobalStatus.Text = "待启动";
                TxtGlobalStatus.Foreground = (Brush)FindResource("TextSecondary");
            }
            else if (cpolar == ServiceStatus.Error || openlist == ServiceStatus.Error)
            {
                GlobalStatusDot.Fill = (Brush)FindResource("ErrorBrush");
                TxtGlobalStatus.Text = "存在异常";
                TxtGlobalStatus.Foreground = (Brush)FindResource("ErrorBrush");
            }
            else
            {
                GlobalStatusDot.Fill = (Brush)FindResource("WarningBrush");
                TxtGlobalStatus.Text = "部分运行中";
                TxtGlobalStatus.Foreground = (Brush)FindResource("TextSecondary");
            }
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            LogsTab.AppendLog("OpenCpolarSync 已启动");
            LogsTab.AppendLog($"应用目录：{_appDir}");

            var cpolarInstalled = InstallDetectionService.IsCpolarInstalled();
            // [修改] 原因：原实现用 {app}\openlist.exe 检测部署，而 openlist 实际解压在
            //         {app}\openlist\openlist.exe（见 setup.iss），导致始终误报“未部署”。
            //         改用 openlist 真实可执行文件路径判断。
            var openlistDeployed = InstallDetectionService.IsOpenlistDeployed(_openlistExePath);

            LogsTab.AppendLog($"Cpolar 已安装：{cpolarInstalled}");
            LogsTab.AppendLog($"Openlist 已部署：{openlistDeployed}");

            if (!cpolarInstalled || !openlistDeployed)
            {
                var missing = "";
                if (!cpolarInstalled) missing += "Cpolar ";
                if (!openlistDeployed) missing += "Openlist ";
                UpdateStatus($"警告：{missing}未安装/部署");
            }
        }

        private void Window_Closing(object sender, CancelEventArgs e)
        {
            if (!_isExiting)
            {
                e.Cancel = true;
                Hide();
                // [修复] 防御性 null 检查：托盘图标可能因初始化失败或异常场景为 null
                if (_trayIcon != null)
                {
                    try
                    {
                        _trayIcon.ShowBalloonTip("OpenCpolarSync", "程序已最小化到系统托盘", Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Info);
                    }
                    catch { }
                }
                return;
            }

            try { _configService?.StopWatching(); } catch { }
            try { _guardService?.StopAll(); } catch { }
            try { _guardService?.Dispose(); } catch { }
            try { _trayIcon?.Dispose(); } catch { }
            try { _pidRefreshTimer?.Stop(); } catch { }

            Application.Current.Shutdown();
        }

        private void ShowMainWindow()
        {
            Show();
            WindowState = WindowState.Normal;
            Activate();
        }

        private void ExitApplication()
        {
            if (!IsVisible)
            {
                Show();
                WindowState = WindowState.Normal;
            }
            Activate();
            Topmost = true;
            Topmost = false;

            var result = MessageBox.Show(this, "确定要退出 OpenCpolarSync 吗？退出后所有守护将停止。",
                "确认退出", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (result == MessageBoxResult.Yes)
            {
                _isExiting = true;
                Close();
            }
        }

        private void UpdateStatus(string message)
        {
            TxtGlobalStatus.Text = message;
        }

        private void BtnAbout_Click(object sender, RoutedEventArgs e)
        {
            var about = new AboutWindow { Owner = this };
            about.ShowDialog();
        }

        /// <summary>
        /// 主题切换按钮点击：在浅色/深色模式间切换
        /// </summary>
        private void BtnThemeToggle_Click(object sender, RoutedEventArgs e)
        {
            if (!_themeInitialized) return;
            var current = _currentConfig?.Theme ?? "Light";
            var isDark = string.Equals(current, "Dark", StringComparison.OrdinalIgnoreCase);
            var newTheme = isDark ? "Light" : "Dark";
            SetTheme(newTheme);
            UpdateThemeIcon(newTheme);
        }

        /// <summary>
        /// 更新主题切换按钮的图标（浅色模式显示月亮，深色模式显示太阳）
        /// </summary>
        private void UpdateThemeIcon(string theme)
        {
            var isDark = string.Equals(theme, "Dark", StringComparison.OrdinalIgnoreCase);
            if (IconMoon != null) IconMoon.Visibility = isDark ? Visibility.Collapsed : Visibility.Visible;
            if (IconSun != null) IconSun.Visibility = isDark ? Visibility.Visible : Visibility.Collapsed;
        }

        /// <summary>
        /// 应用主题并持久化到配置
        /// </summary>
        private void SetTheme(string theme)
        {
            ThemeManager.Apply(theme);
            _currentConfig.Theme = theme;
            _configService.Save(_currentConfig);
        }

        /// <summary>
        /// 启动时应用配置中保存的主题
        /// </summary>
        private void ApplySavedTheme()
        {
            var saved = _currentConfig?.Theme ?? "Light";
            ThemeManager.Apply(saved);
            UpdateThemeIcon(saved);
        }

        private void BtnStartAllTop_Click(object sender, RoutedEventArgs e) => StartAllGuards();
        private void BtnStopAllTop_Click(object sender, RoutedEventArgs e) => StopAllGuards();

        // ==================== 导航切换 ====================
        private void NavDashboard_Click(object sender, RoutedEventArgs e) => NavigateTo("dashboard");
        private void NavCpolar_Click(object sender, RoutedEventArgs e) => NavigateTo("cpolar");
        private void NavOpenlist_Click(object sender, RoutedEventArgs e) => NavigateTo("openlist");
        private void NavLogs_Click(object sender, RoutedEventArgs e) => NavigateTo("logs");

        private void NavigateTo(string page)
        {
            if (_currentPage == page) return;
            _currentPage = page;

            // 切换页面可见性
            DashboardTab.Visibility = page == "dashboard" ? Visibility.Visible : Visibility.Collapsed;
            CpolarConfigTab.Visibility = page == "cpolar" ? Visibility.Visible : Visibility.Collapsed;
            OpenlistConfigTab.Visibility = page == "openlist" ? Visibility.Visible : Visibility.Collapsed;
            LogsTab.Visibility = page == "logs" ? Visibility.Visible : Visibility.Collapsed;

            // 顶部「启动/停止全部守护」仅总览页面显示
            var showTopActions = page == "dashboard";
            BtnStartAllTop.Visibility = showTopActions ? Visibility.Visible : Visibility.Collapsed;
            BtnStopAllTop.Visibility = showTopActions ? Visibility.Visible : Visibility.Collapsed;

            // 更新导航按钮样式
            SetNavActive(NavDashboard, page == "dashboard");
            SetNavActive(NavCpolar, page == "cpolar");
            SetNavActive(NavOpenlist, page == "openlist");
            SetNavActive(NavLogs, page == "logs");

            // 更新页面标题
            switch (page)
            {
                case "dashboard": TxtPageTitle.Text = "服务总览"; break;
                case "cpolar": TxtPageTitle.Text = "Cpolar 配置"; break;
                case "openlist": TxtPageTitle.Text = "Openlist 配置"; break;
                case "logs": TxtPageTitle.Text = "运行日志"; break;
            }
        }

        private void SetNavActive(Button btn, bool active)
        {
            btn.Style = active ? (Style)FindResource("NavItemActiveStyle") : (Style)FindResource("NavItemStyle");
        }
    }
}
