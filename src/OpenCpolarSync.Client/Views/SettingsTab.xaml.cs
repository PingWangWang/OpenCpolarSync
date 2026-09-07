using System;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace OpenCpolarSync.Client.Views
{
    /// <summary>
    /// SettingsTab.xaml 的交互逻辑 — 全局设置页面，支持开机自启动开关等
    /// </summary>
    public partial class SettingsTab : UserControl
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AutoStartValueName = "OpenCpolarSync";
        private bool _isLoading;

        public SettingsTab()
        {
            InitializeComponent();
            Loaded += SettingsTab_Loaded;
        }

        /// <summary>
        /// 页面加载时读取当前开机自启动状态
        /// </summary>
        private void SettingsTab_Loaded(object sender, RoutedEventArgs e)
        {
            RefreshAutoStartState();
        }

        /// <summary>
        /// 从注册表读取开机自启动当前状态并更新界面
        /// </summary>
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
            catch (Exception ex)
            {
                ChkAutoStart.IsChecked = false;
                System.Diagnostics.Debug.WriteLine($"读取开机自启动状态失败: {ex.Message}");
            }
            finally
            {
                _isLoading = false;
            }
        }

        /// <summary>
        /// 勾选开机自启动：写入注册表
        /// </summary>
        private void ChkAutoStart_Checked(object sender, RoutedEventArgs e)
        {
            if (_isLoading) return;
            SetAutoStart(true);
        }

        /// <summary>
        /// 取消开机自启动：删除注册表值
        /// </summary>
        private void ChkAutoStart_Unchecked(object sender, RoutedEventArgs e)
        {
            if (_isLoading) return;
            SetAutoStart(false);
        }

        /// <summary>
        /// 设置或取消开机自启动
        /// </summary>
        /// <param name="enable">true=写入注册表开启自启，false=删除注册表值关闭自启</param>
        private void SetAutoStart(bool enable)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true))
                {
                    if (key == null)
                    {
                        MessageBox.Show("无法访问注册表启动项，设置失败。", "错误",
                            MessageBoxButton.OK, MessageBoxImage.Error);
                        RefreshAutoStartState();
                        return;
                    }

                    if (enable)
                    {
                        var exePath = System.Reflection.Assembly.GetExecutingAssembly().Location;
                        key.SetValue(AutoStartValueName, $"\"{exePath}\"", RegistryValueKind.String);
                    }
                    else
                    {
                        if (key.GetValue(AutoStartValueName) != null)
                        {
                            key.DeleteValue(AutoStartValueName, false);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show($"设置开机自启动失败：{ex.Message}", "错误",
                    MessageBoxButton.OK, MessageBoxImage.Error);
                RefreshAutoStartState();
            }
        }
    }
}
