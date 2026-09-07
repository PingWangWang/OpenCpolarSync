using System.Windows;
using System.Windows.Controls;
using OpenCpolarSync.Client.Models;

namespace OpenCpolarSync.Client.Views
{
    /// <summary>
    /// OpenlistConfigTab.xaml 的交互逻辑 — Openlist(alist) 管理密码配置页，独立于 Cpolar 配置
    /// </summary>
    public partial class OpenlistConfigTab : UserControl
    {
        private bool _isLoading;

        /// <summary>
        /// 保存配置请求事件
        /// </summary>
        public event RoutedEventHandler SaveConfigRequested;

        public OpenlistConfigTab()
        {
            InitializeComponent();
        }

        /// <summary>
        /// 加载配置到界面（仅同步密码；用户名固定为 admin）
        /// </summary>
        public void LoadConfig(CpolarConfig config)
        {
            _isLoading = true;
            try
            {
                TxtOpenlistPassword.Password = config.OpenlistPassword ?? "";
                TxtOpenlistPasswordVisible.Text = config.OpenlistPassword ?? "";
            }
            finally
            {
                _isLoading = false;
            }
        }

        /// <summary>
        /// 从界面获取当前配置的 Openlist 密码
        /// </summary>
        public string GetPassword() => TxtOpenlistPassword.Password;

        private void BtnSave_Click(object sender, RoutedEventArgs e)
        {
            SaveConfigRequested?.Invoke(sender, e);
        }

        private void BtnReset_Click(object sender, RoutedEventArgs e)
        {
            _isLoading = true;
            try
            {
                TxtOpenlistPassword.Password = "";
                TxtOpenlistPasswordVisible.Text = "";
            }
            finally
            {
                _isLoading = false;
            }
        }

        /// <summary>
        /// 密码框内容变更时同步到可见文本框
        /// </summary>
        private void TxtOpenlistPassword_PasswordChanged(object sender, RoutedEventArgs e)
        {
            if (_isLoading) return;
            if (TxtOpenlistPasswordVisible.Text != TxtOpenlistPassword.Password)
            {
                TxtOpenlistPasswordVisible.Text = TxtOpenlistPassword.Password;
            }
        }

        /// <summary>
        /// 可见密码文本框内容变更时同步到密码框
        /// </summary>
        private void TxtOpenlistPasswordVisible_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (_isLoading) return;
            if (TxtOpenlistPassword.Password != TxtOpenlistPasswordVisible.Text)
            {
                TxtOpenlistPassword.Password = TxtOpenlistPasswordVisible.Text;
            }
        }

        /// <summary>
        /// 勾选"显示密码"：切换到明文显示
        /// </summary>
        private void ChkOpenlistShowPassword_Checked(object sender, RoutedEventArgs e)
        {
            TxtOpenlistPasswordVisible.Text = TxtOpenlistPassword.Password;
            TxtOpenlistPassword.Visibility = Visibility.Collapsed;
            TxtOpenlistPasswordVisible.Visibility = Visibility.Visible;
            TxtOpenlistPasswordVisible.Focus();
            TxtOpenlistPasswordVisible.SelectionStart = TxtOpenlistPasswordVisible.Text.Length;
        }

        /// <summary>
        /// 取消"显示密码"：切回密码框
        /// </summary>
        private void ChkOpenlistShowPassword_Unchecked(object sender, RoutedEventArgs e)
        {
            TxtOpenlistPassword.Password = TxtOpenlistPasswordVisible.Text;
            TxtOpenlistPasswordVisible.Visibility = Visibility.Collapsed;
            TxtOpenlistPassword.Visibility = Visibility.Visible;
            TxtOpenlistPassword.Focus();
        }
    }
}
