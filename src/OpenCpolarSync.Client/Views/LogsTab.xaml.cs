using System;
using System.Windows;
using System.Windows.Controls;

namespace OpenCpolarSync.Client.Views
{
    /// <summary>
    /// LogsTab.xaml 的交互逻辑 — 运行日志查看页面
    /// </summary>
    public partial class LogsTab : UserControl
    {
        public LogsTab()
        {
            InitializeComponent();
        }

        /// <summary>
        /// 追加日志行
        /// </summary>
        public void AppendLog(string message)
        {
            Dispatcher.Invoke(() =>
            {
                var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                TxtLogs.AppendText($"[{timestamp}] {message}{Environment.NewLine}");
                TxtLogs.ScrollToEnd();
            });
        }

        /// <summary>
        /// 清空日志
        /// </summary>
        public void ClearLogs()
        {
            Dispatcher.Invoke(() => TxtLogs.Clear());
        }

        private void BtnClear_Click(object sender, RoutedEventArgs e)
        {
            ClearLogs();
        }
    }
}
