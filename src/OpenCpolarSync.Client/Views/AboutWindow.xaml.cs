using System;
using System.Diagnostics;
using System.Reflection;
using System.Windows;

namespace OpenCpolarSync.Client.Views
{
    /// <summary>
    /// AboutWindow.xaml 的交互逻辑 — 关于对话框，显示版本号和功能介绍
    /// </summary>
    public partial class AboutWindow : Window
    {
        public AboutWindow()
        {
            InitializeComponent();
            LoadVersionInfo();
        }

        /// <summary>
        /// 从程序集加载版本信息
        /// </summary>
        private void LoadVersionInfo()
        {
            try
            {
                var assembly = Assembly.GetExecutingAssembly();

                // 版本号
                var version = assembly.GetName().Version;
                if (version != null)
                {
                    TxtVersion.Text = $"v{version.Major}.{version.Minor}.{version.Build}";
                }

                // 编译时间（取 exe 文件的最后写入时间）
                var exePath = assembly.Location;
                if (!string.IsNullOrEmpty(exePath) && System.IO.File.Exists(exePath))
                {
                    var buildTime = System.IO.File.GetLastWriteTime(exePath);
                    TxtBuildTime.Text = $"构建时间：{buildTime:yyyy-MM-dd HH:mm:ss}";
                }
            }
            catch
            {
                // 版本信息加载失败时保持默认
            }
        }

        private void BtnClose_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }
    }
}
