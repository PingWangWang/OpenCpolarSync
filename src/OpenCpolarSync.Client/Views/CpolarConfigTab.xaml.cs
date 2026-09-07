using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using Newtonsoft.Json;
using OpenCpolarSync.Client.Models;
using OpenCpolarSync.Client.ViewModels;

namespace OpenCpolarSync.Client.Views
{
    /// <summary>
    /// CpolarConfigTab.xaml 的交互逻辑 — Cpolar 配置页面，支持配置编辑、保存、导出、导入
    /// </summary>
    public partial class CpolarConfigTab : UserControl
    {
        private readonly CpolarConfigViewModel _viewModel;
        private bool _isLoading;

        /// <summary>
        /// 保存配置请求事件
        /// </summary>
        public event RoutedEventHandler SaveConfigRequested;

        public CpolarConfigTab()
        {
            InitializeComponent();
            _viewModel = new CpolarConfigViewModel();
            DataContext = _viewModel;
        }

        /// <summary>
        /// 加载配置到界面
        /// </summary>
        public void LoadConfig(CpolarConfig config)
        {
            _isLoading = true;
            try
            {
                _viewModel.WebhookUrl = config.WebhookUrl ?? "";
                _viewModel.Keyword = config.Keyword ?? "";
                _viewModel.Interval = config.Interval;
                _viewModel.SelectedTunnelNamesText = config.SelectedTunnelNames != null
                    ? string.Join(",", config.SelectedTunnelNames)
                    : "";
                _viewModel.CpolarApiBase = config.CpolarApiBase ?? "http://localhost:9200";
                _viewModel.Username = config.Username ?? "";
                _viewModel.Password = config.Password ?? "";
                _viewModel.Debug = config.Debug;

                // 同步到密码框
                TxtPassword.Password = _viewModel.Password;
                TxtPasswordVisible.Text = _viewModel.Password;
            }
            finally
            {
                _isLoading = false;
            }
        }

        /// <summary>
        /// 从界面获取配置
        /// </summary>
        public CpolarConfig GetConfig()
        {
            return _viewModel.ToConfig();
        }

        private void BtnSave_Click(object sender, RoutedEventArgs e)
        {
            SaveConfigRequested?.Invoke(sender, e);
        }

        private void BtnReset_Click(object sender, RoutedEventArgs e)
        {
            // 重置为默认值
            _viewModel.WebhookUrl = "";
            _viewModel.Keyword = "";
            _viewModel.Interval = 5;
            _viewModel.SelectedTunnelNamesText = "";
            _viewModel.CpolarApiBase = "http://localhost:9200";
            _viewModel.Username = "";
            _viewModel.Password = "";
            _viewModel.Debug = false;
            TxtPassword.Password = "";
            TxtPasswordVisible.Text = "";
        }

        /// <summary>
        /// 导出配置到 JSON 文件
        /// </summary>
        private void BtnExport_Click(object sender, RoutedEventArgs e)
        {
            var config = _viewModel.ToConfig();
            var json = JsonConvert.SerializeObject(config, Formatting.Indented);

            var dialog = new SaveFileDialog
            {
                Filter = "JSON 配置文件 (*.json)|*.json|所有文件 (*.*)|*.*",
                FileName = "cpolar-config.json",
                Title = "导出 Cpolar 配置"
            };

            if (dialog.ShowDialog() == true)
            {
                try
                {
                    File.WriteAllText(dialog.FileName, json);
                    MessageBox.Show("配置已导出到：\n" + dialog.FileName, "导出成功",
                        MessageBoxButton.OK, MessageBoxImage.Information);
                }
                catch (IOException ex)
                {
                    MessageBox.Show("导出失败：" + ex.Message, "错误",
                        MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        /// <summary>
        /// 从 JSON 文件导入配置
        /// </summary>
        private void BtnImport_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog
            {
                Filter = "JSON 配置文件 (*.json)|*.json|所有文件 (*.*)|*.*",
                Title = "导入 Cpolar 配置"
            };

            if (dialog.ShowDialog() == true)
            {
                try
                {
                    var json = File.ReadAllText(dialog.FileName);
                    var config = JsonConvert.DeserializeObject<CpolarConfig>(json);
                    if (config == null)
                    {
                        MessageBox.Show("配置文件格式无效，无法解析。", "导入失败",
                            MessageBoxButton.OK, MessageBoxImage.Warning);
                        return;
                    }

                    LoadConfig(config);
                    MessageBox.Show("配置已导入，请点击「保存配置」使其生效。", "导入成功",
                        MessageBoxButton.OK, MessageBoxImage.Information);
                }
                catch (JsonException ex)
                {
                    MessageBox.Show("配置文件解析失败：" + ex.Message, "导入失败",
                        MessageBoxButton.OK, MessageBoxImage.Error);
                }
                catch (IOException ex)
                {
                    MessageBox.Show("读取文件失败：" + ex.Message, "导入失败",
                        MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        /// <summary>
        /// 密码框内容变更时同步到 ViewModel
        /// </summary>
        private void TxtPassword_PasswordChanged(object sender, RoutedEventArgs e)
        {
            if (_isLoading) return;
            _viewModel.Password = TxtPassword.Password;
            // 同步到可见文本框（如果当前显示的是密码框则不需要，但保持一致）
            if (TxtPasswordVisible.Text != TxtPassword.Password)
            {
                TxtPasswordVisible.Text = TxtPassword.Password;
            }
        }

        /// <summary>
        /// 可见密码文本框内容变更时同步到 ViewModel 和密码框
        /// </summary>
        private void TxtPasswordVisible_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (_isLoading) return;
            _viewModel.Password = TxtPasswordVisible.Text;
            if (TxtPassword.Password != TxtPasswordVisible.Text)
            {
                TxtPassword.Password = TxtPasswordVisible.Text;
            }
        }

        /// <summary>
        /// 勾选"显示密码"：切换到 TextBox 显示明文
        /// </summary>
        private void ChkShowPassword_Checked(object sender, RoutedEventArgs e)
        {
            // 先同步内容，再切换可见性
            TxtPasswordVisible.Text = TxtPassword.Password;
            TxtPassword.Visibility = Visibility.Collapsed;
            TxtPasswordVisible.Visibility = Visibility.Visible;
            TxtPasswordVisible.Focus();
            // 光标移到末尾
            TxtPasswordVisible.SelectionStart = TxtPasswordVisible.Text.Length;
        }

        /// <summary>
        /// 取消"显示密码"：切换回 PasswordBox
        /// </summary>
        private void ChkShowPassword_Unchecked(object sender, RoutedEventArgs e)
        {
            TxtPassword.Password = TxtPasswordVisible.Text;
            TxtPasswordVisible.Visibility = Visibility.Collapsed;
            TxtPassword.Visibility = Visibility.Visible;
            TxtPassword.Focus();
        }
    }
}
