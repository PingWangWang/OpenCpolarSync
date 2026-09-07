using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using OpenCpolarSync.Client.ViewModels;

namespace OpenCpolarSync.Client.Views
{
    /// <summary>
    /// DashboardTab.xaml 的交互逻辑 — 总览页面，展示服务状态和快捷操作
    /// </summary>
    public partial class DashboardTab : UserControl
    {
        private readonly DashboardViewModel _viewModel;

        public DashboardTab()
        {
            InitializeComponent();
            _viewModel = new DashboardViewModel();
            DataContext = _viewModel;
        }

        /// <summary>
        /// 更新视图模型
        /// </summary>
        public void UpdateViewModel(DashboardViewModel vm)
        {
            _viewModel.CpolarStatus = vm.CpolarStatus;
            _viewModel.OpenlistStatus = vm.OpenlistStatus;
            _viewModel.CpolarTunnelCount = vm.CpolarTunnelCount;
            _viewModel.CpolarProcessId = vm.CpolarProcessId;
            _viewModel.OpenlistProcessId = vm.OpenlistProcessId;
            _viewModel.LastPushTime = vm.LastPushTime;
        }

        /// <summary>
        /// 用系统默认浏览器打开 URL
        /// </summary>
        private static void OpenInBrowser(string url)
        {
            try
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            }
            catch (System.Exception ex)
            {
                MessageBox.Show($"无法打开浏览器：{ex.Message}", "错误",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void BtnOpenCpolarWeb_Click(object sender, RoutedEventArgs e)
        {
            OpenInBrowser("http://localhost:9200");
        }

        private void BtnOpenOpenlistWeb_Click(object sender, RoutedEventArgs e)
        {
            OpenInBrowser("http://localhost:5244");
        }
    }
}
