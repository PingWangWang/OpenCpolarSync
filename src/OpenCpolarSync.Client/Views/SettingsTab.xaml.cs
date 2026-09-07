using System;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using OpenCpolarSync.Client.Components;
using OpenCpolarSync.Client.Models;
using OpenCpolarSync.Client.Services;

namespace OpenCpolarSync.Client.Views
{
    /// <summary>
    /// SettingsTab.xaml 的交互逻辑 — 全局设置页面，支持开机自启动、主题、背景效果、关闭行为
    /// </summary>
    public partial class SettingsTab : UserControl
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AutoStartValueName = "OpenCpolarSync";
        private bool _isLoading;
        private CpolarConfig _config;

        /// <summary>
        /// 配置变更事件（主题/背景效果/关闭行为变更时通知主窗口保存）
        /// </summary>
        public event EventHandler ConfigChanged;

        public SettingsTab()
        {
            InitializeComponent();
            Loaded += SettingsTab_Loaded;
        }

        /// <summary>
        /// 由主窗口调用，传入当前配置引用
        /// </summary>
        public void SetConfig(CpolarConfig config)
        {
            _config = config;
            LoadSettingsFromConfig();
        }

        /// <summary>
        /// 页面加载时读取当前状态
        /// </summary>
        private void SettingsTab_Loaded(object sender, RoutedEventArgs e)
        {
            RefreshAutoStartState();
            LoadSettingsFromConfig();
        }

        /// <summary>
        /// 从配置加载主题/背景效果/关闭行为到界面
        /// </summary>
        private void LoadSettingsFromConfig()
        {
            _isLoading = true;
            try
            {
                if (_config == null) return;
                SelectComboBoxTag(CmbTheme, _config.Theme ?? "Light");
                SelectComboBoxTag(CmbBackgroundEffect, _config.BackgroundEffect ?? "Mica");
                SelectComboBoxTag(CmbCloseMode, _config.CloseMode ?? "Ask");
                ChkAutoStartGuard.IsChecked = _config.AutoStartGuard;
            }
            finally { _isLoading = false; }
        }

        /// <summary>
        /// 按 Tag 选中 ComboBox 项
        /// </summary>
        private void SelectComboBoxTag(ComboBox combo, string tag)
        {
            foreach (ComboBoxItem item in combo.Items)
            {
                if (string.Equals(item.Tag?.ToString(), tag, StringComparison.OrdinalIgnoreCase))
                {
                    combo.SelectedItem = item;
                    return;
                }
            }
        }

        /// <summary>
        /// 获取当前选中的 Tag
        /// </summary>
        private string GetSelectedTag(ComboBox combo)
        {
            return (combo.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "";
        }

        #region 开机自启动

        private void RefreshAutoStartState()
        {
            _isLoading = true;
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false))
                {
                    var value = key?.GetValue(AutoStartValueName) as string;
                    ChkAutoStart.IsChecked = !string.IsNullOrEmpty(value);
                }
            }
            catch { ChkAutoStart.IsChecked = false; }
            finally { _isLoading = false; }
        }

        private void ChkAutoStart_Checked(object sender, RoutedEventArgs e)
        {
            if (_isLoading) return;
            SetAutoStart(true);
        }

        private void ChkAutoStart_Unchecked(object sender, RoutedEventArgs e)
        {
            if (_isLoading) return;
            SetAutoStart(false);
        }

        private void SetAutoStart(bool enable)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true))
                {
                    if (key == null) return;
                    if (enable)
                    {
                        var exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
                        key.SetValue(AutoStartValueName, $"\"{exePath}\"", RegistryValueKind.String);
                    }
                    else
                    {
                        if (key.GetValue(AutoStartValueName) != null)
                            key.DeleteValue(AutoStartValueName, false);
                    }
                }
            }
            catch (Exception ex)
            {
                InfoBarManager.Error("设置失败", ex.Message);
                RefreshAutoStartState();
            }
        }

        #endregion

        #region 自动启动守护

        private void ChkAutoStartGuard_Checked(object sender, RoutedEventArgs e)
        {
            if (_isLoading || _config == null) return;
            _config.AutoStartGuard = true;
            ConfigChanged?.Invoke(this, EventArgs.Empty);
        }

        private void ChkAutoStartGuard_Unchecked(object sender, RoutedEventArgs e)
        {
            if (_isLoading || _config == null) return;
            _config.AutoStartGuard = false;
            ConfigChanged?.Invoke(this, EventArgs.Empty);
        }

        #endregion

        #region 外观设置

        private void CmbTheme_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_isLoading) return;
            var theme = GetSelectedTag(CmbTheme);
            if (string.IsNullOrEmpty(theme)) return;

            ThemeManager.Apply(theme);
            if (_config != null)
            {
                _config.Theme = theme;
                ConfigChanged?.Invoke(this, EventArgs.Empty);
            }
            // 主题变化后重新应用背景效果（深色/浅色色调不同）
            var window = Window.GetWindow(this);
            if (window != null)
            {
                var effectStr = _config?.BackgroundEffect ?? "Mica";
                if (Enum.TryParse<BackgroundEffect>(effectStr, true, out var effect))
                {
                    WindowEffect.SetBackgroundEffect(window, effect, ThemeManager.IsDark(theme));
                }
            }
        }

        private void CmbBackgroundEffect_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_isLoading) return;
            var effectStr = GetSelectedTag(CmbBackgroundEffect);
            if (string.IsNullOrEmpty(effectStr)) return;

            if (_config != null)
            {
                _config.BackgroundEffect = effectStr;
                ConfigChanged?.Invoke(this, EventArgs.Empty);
            }

            var window = Window.GetWindow(this);
            if (window != null && Enum.TryParse<BackgroundEffect>(effectStr, true, out var effect))
            {
                var isDark = ThemeManager.IsDark(_config?.Theme ?? "Light");
                WindowEffect.SetBackgroundEffect(window, effect, isDark);
            }
        }

        #endregion

        #region 关闭行为

        private void CmbCloseMode_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_isLoading) return;
            var mode = GetSelectedTag(CmbCloseMode);
            if (string.IsNullOrEmpty(mode)) return;

            if (_config != null)
            {
                _config.CloseMode = mode;
                ConfigChanged?.Invoke(this, EventArgs.Empty);
            }
        }

        #endregion
    }
}
