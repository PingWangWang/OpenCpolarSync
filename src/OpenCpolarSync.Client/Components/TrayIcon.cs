using System;
using System.Drawing;
using System.Windows;
using Hardcodet.Wpf.TaskbarNotification;

namespace OpenCpolarSync.Client.Components
{
    /// <summary>
    /// 系统托盘组件 — 基于 Hardcodet.NotifyIcon.Wpf，提供托盘图标、气泡提示和右键菜单
    /// </summary>
    public class TrayIconComponent : IDisposable
    {
        private TaskbarIcon _trayIcon;
        private bool _disposed;

        /// <summary>
        /// 显示主窗口请求事件
        /// </summary>
        public event EventHandler ShowMainWindowRequested;

        /// <summary>
        /// 退出应用请求事件
        /// </summary>
        public event EventHandler ExitApplicationRequested;

        /// <summary>
        /// 启动全部守护请求事件
        /// </summary>
        public event EventHandler StartAllRequested;

        /// <summary>
        /// 停止全部守护请求事件
        /// </summary>
        public event EventHandler StopAllRequested;

        /// <summary>
        /// 打开 Cpolar 管理请求事件
        /// </summary>
        public event EventHandler OpenCpolarWebRequested;

        /// <summary>
        /// 打开 Openlist 管理请求事件
        /// </summary>
        public event EventHandler OpenOpenlistWebRequested;

        /// <summary>
        /// 初始化托盘图标
        /// </summary>
        public void Initialize()
        {
            _trayIcon = new TaskbarIcon
            {
                Icon = GenerateDefaultIcon(),
                ToolTipText = "OpenCpolarSync",
                Visibility = Visibility.Visible
            };

            // 双击托盘图标显示主窗口
            _trayIcon.TrayMouseDoubleClick += (s, e) => ShowMainWindowRequested?.Invoke(this, EventArgs.Empty);

            BuildContextMenu();
        }

        /// <summary>
        /// 构建右键菜单
        /// </summary>
        private void BuildContextMenu()
        {
            var menu = new System.Windows.Controls.ContextMenu();

            var titleItem = new System.Windows.Controls.MenuItem
            {
                Header = "OpenCpolarSync v1.0",
                IsEnabled = false
            };
            menu.Items.Add(titleItem);
            menu.Items.Add(new System.Windows.Controls.Separator());

            var showItem = new System.Windows.Controls.MenuItem { Header = "显示主窗口" };
            showItem.Click += (s, e) => ShowMainWindowRequested?.Invoke(this, EventArgs.Empty);
            menu.Items.Add(showItem);
            menu.Items.Add(new System.Windows.Controls.Separator());

            var startItem = new System.Windows.Controls.MenuItem { Header = "启动全部守护" };
            startItem.Click += (s, e) => StartAllRequested?.Invoke(this, EventArgs.Empty);
            menu.Items.Add(startItem);

            var stopItem = new System.Windows.Controls.MenuItem { Header = "停止全部守护" };
            stopItem.Click += (s, e) => StopAllRequested?.Invoke(this, EventArgs.Empty);
            menu.Items.Add(stopItem);
            menu.Items.Add(new System.Windows.Controls.Separator());

            var cpolarItem = new System.Windows.Controls.MenuItem { Header = "打开 Cpolar 管理 (localhost:9200)" };
            cpolarItem.Click += (s, e) => OpenCpolarWebRequested?.Invoke(this, EventArgs.Empty);
            menu.Items.Add(cpolarItem);

            var openlistItem = new System.Windows.Controls.MenuItem { Header = "打开 Openlist 管理 (localhost:5244)" };
            openlistItem.Click += (s, e) => OpenOpenlistWebRequested?.Invoke(this, EventArgs.Empty);
            menu.Items.Add(openlistItem);
            menu.Items.Add(new System.Windows.Controls.Separator());

            var exitItem = new System.Windows.Controls.MenuItem { Header = "退出" };
            exitItem.Click += (s, e) => ExitApplicationRequested?.Invoke(this, EventArgs.Empty);
            menu.Items.Add(exitItem);

            _trayIcon.ContextMenu = menu;
        }

        /// <summary>
        /// 显示气泡提示
        /// </summary>
        public void ShowBalloonTip(string title, string message, BalloonIcon icon = BalloonIcon.Info)
        {
            _trayIcon?.ShowBalloonTip(title, message, icon);
        }

        /// <summary>
        /// 更新托盘提示文本
        /// </summary>
        public void UpdateToolTip(string text)
        {
            if (_trayIcon != null)
            {
                _trayIcon.ToolTipText = text;
            }
        }

        /// <summary>
        /// 生成托盘图标
        /// 优先从程序集资源加载 app.ico（项目主图标），失败时回退到代码生成的默认图标
        /// </summary>
        private Icon GenerateDefaultIcon()
        {
            // 优先从嵌入资源加载 app.ico
            try
            {
                var uri = new Uri("pack://application:,,,/app.ico", UriKind.Absolute);
                var streamInfo = System.Windows.Application.GetResourceStream(uri);
                if (streamInfo != null && streamInfo.Stream != null)
                {
                    using (var stream = streamInfo.Stream)
                    {
                        return new Icon(stream);
                    }
                }
            }
            catch { }

            // 回退：代码生成默认图标（蓝色圆形带字母 O）
            try
            {
                var bitmap = new Bitmap(32, 32);
                using (var g = Graphics.FromImage(bitmap))
                {
                    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    g.Clear(Color.Transparent);

                    // 蓝色圆形背景
                    using (var brush = new SolidBrush(Color.FromArgb(74, 144, 217)))
                    {
                        g.FillEllipse(brush, 2, 2, 28, 28);
                    }

                    // 白色字母 O
                    using (var font = new Font("Arial", 16, System.Drawing.FontStyle.Bold))
                    using (var brush = new SolidBrush(Color.White))
                    {
                        var sf = new StringFormat
                        {
                            Alignment = StringAlignment.Center,
                            LineAlignment = StringAlignment.Center
                        };
                        g.DrawString("O", font, brush, new RectangleF(0, 0, 32, 32), sf);
                    }
                }

                IntPtr hIcon = bitmap.GetHicon();
                return Icon.FromHandle(hIcon);
            }
            catch
            {
                // 降级：使用系统默认图标
                return SystemIcons.Application;
            }
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _trayIcon?.Dispose();
                _disposed = true;
            }
        }
    }
}
