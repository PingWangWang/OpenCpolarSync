using System;
using System.Text;
using System.Threading;
using System.Windows;

namespace OpenCpolarSync.Client
{
    /// <summary>
    /// App.xaml 的交互逻辑 — 应用入口，负责单实例互斥和全局异常处理
    /// </summary>
    public partial class App : Application
    {
        /// <summary>
        /// 单实例互斥体名称，防止多个应用实例同时运行
        /// </summary>
        private const string MutexName = "Global\\OpenCpolarSync-{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}";

        private Mutex _singleInstanceMutex;

        /// <summary>
        /// 应用启动时执行：检查单实例、注册全局异常处理
        /// </summary>
        protected override void OnStartup(StartupEventArgs e)
        {
            // 单实例检查：如果已有实例运行，则退出
            _singleInstanceMutex = new Mutex(true, MutexName, out bool createdNew);
            if (!createdNew)
            {
                MessageBox.Show("OpenCpolarSync 已在运行中。", "提示",
                    MessageBoxButton.OK, MessageBoxImage.Information);
                Shutdown();
                return;
            }

            // 全局未处理异常捕获
            AppDomain.CurrentDomain.UnhandledException += OnUnhandledException;
            DispatcherUnhandledException += OnDispatcherUnhandledException;

            base.OnStartup(e);

            // [修改] 手动创建主窗口：StartupUri 自动创建时启动异常无法在此处捕获，
            //         现在捕获启动阶段异常并写入日志，便于定位（同时增强健壮性）
            try
            {
                new MainWindow().Show();
            }
            catch (Exception ex)
            {
                WriteStartupError(ex);
                Shutdown();
            }
        }

        /// <summary>
        /// 将启动阶段异常写入应用目录下的 startup-error.log，便于排查
        /// </summary>
        private void WriteStartupError(Exception ex)
        {
            try
            {
                var logPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "startup-error.log");
                System.IO.File.WriteAllText(logPath, ex.ToString());
            }
            catch { }
        }

        /// <summary>
        /// 应用退出时释放互斥体
        /// </summary>
        protected override void OnExit(ExitEventArgs e)
        {
            _singleInstanceMutex?.ReleaseMutex();
            _singleInstanceMutex?.Dispose();
            base.OnExit(e);
        }

        private void OnUnhandledException(object sender, UnhandledExceptionEventArgs e)
        {
            if (e.ExceptionObject is Exception ex)
            {
                MessageBox.Show($"发生未处理异常：{ex.Message}\n\n{ex.StackTrace}",
                    "错误", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void OnDispatcherUnhandledException(object sender,
            System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
        {
            // [修改] 原因：仅显示外层消息会掩盖真实根因（XamlParseException 的 InnerException），展开整条异常链便于排查
            var sb = new StringBuilder();
            sb.AppendLine("UI 线程异常，详细信息：");
            var ex = e.Exception;
            while (ex != null)
            {
                sb.AppendLine($"[{ex.GetType().Name}] {ex.Message}");
                ex = ex.InnerException;
            }
            sb.AppendLine();
            sb.AppendLine(e.Exception.StackTrace);

            MessageBox.Show(sb.ToString(), "UI 线程异常",
                MessageBoxButton.OK, MessageBoxImage.Error);
            e.Handled = true;
        }
    }
}
