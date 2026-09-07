using System.Windows;
using System.Windows.Controls;
using OpenCpolarSync.Client.Models;
using OpenCpolarSync.Client.ViewModels;

namespace OpenCpolarSync.Client.Views
{
    /// <summary>
    /// CpolarConfigTab.xaml 的交互逻辑 — Cpolar 配置页面，支持配置编辑和保存
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
