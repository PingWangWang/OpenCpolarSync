using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;

namespace OpenCpolarSync.Client.Components
{
    /// <summary>
    /// InfoBar 通知管理器 — 管理右下角通知的堆叠显示
    /// 参考 Ghost-Downloader-3 的 InfoBarPosition.BOTTOM_RIGHT 实现
    /// </summary>
    public static class InfoBarManager
    {
        private static Window _ownerWindow;
        private static StackPanel _container;
        private static readonly List<InfoBar> _activeBars = new List<InfoBar>();

        /// <summary>
        /// 初始化通知管理器，绑定到宿主窗口
        /// </summary>
        /// <param name="owner">宿主窗口</param>
        public static void Initialize(Window owner)
        {
            _ownerWindow = owner;

            // 创建覆盖层容器（右下角）
            var overlay = new Grid
            {
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(0, 0, 16, 16),
                Width = 340
            };

            _container = new StackPanel();
            overlay.Children.Add(_container);

            // 添加到窗口的顶层 Grid
            if (owner.Content is Grid rootGrid)
            {
                // 确保覆盖层在最上层
                Grid.SetRowSpan(overlay, 10);
                Grid.SetColumnSpan(overlay, 10);
                rootGrid.Children.Add(overlay);
                Panel.SetZIndex(overlay, 10000);
            }
        }

        /// <summary>
        /// 显示通知
        /// </summary>
        public static void Show(InfoBarType type, string title, string content = "", int autoCloseMs = 3000)
        {
            if (_container == null) return;

            var bar = new InfoBar(type, title, content, autoCloseMs);
            bar.Closed += (s, e) =>
            {
                _activeBars.Remove(bar);
                _container.Children.Remove(bar);
            };

            _activeBars.Add(bar);
            _container.Children.Add(bar);

            // 限制最多显示 5 条，超出移除最旧的
            while (_activeBars.Count > 5)
            {
                var oldest = _activeBars[0];
                oldest.Close();
            }
        }

        /// <summary>
        /// 显示成功通知
        /// </summary>
        public static void Success(string title, string content = "", int autoCloseMs = 3000)
        {
            Show(InfoBarType.Success, title, content, autoCloseMs);
        }

        /// <summary>
        /// 显示错误通知
        /// </summary>
        public static void Error(string title, string content = "", int autoCloseMs = 5000)
        {
            Show(InfoBarType.Error, title, content, autoCloseMs);
        }

        /// <summary>
        /// 显示警告通知
        /// </summary>
        public static void Warning(string title, string content = "", int autoCloseMs = 4000)
        {
            Show(InfoBarType.Warning, title, content, autoCloseMs);
        }

        /// <summary>
        /// 显示信息通知
        /// </summary>
        public static void Information(string title, string content = "", int autoCloseMs = 3000)
        {
            Show(InfoBarType.Information, title, content, autoCloseMs);
        }
    }
}
