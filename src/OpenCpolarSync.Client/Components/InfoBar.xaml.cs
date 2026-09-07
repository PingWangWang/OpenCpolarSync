using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace OpenCpolarSync.Client.Components
{
    /// <summary>
    /// InfoBar 通知类型 — 对齐 qfluentwidgets InfoBar
    /// </summary>
    public enum InfoBarType
    {
        Information,
        Success,
        Warning,
        Error
    }

    /// <summary>
    /// InfoBar 通知组件 — 右下角弹出式通知，替代原生 MessageBox 用于操作反馈
    /// 参考 Ghost-Downloader-3 的 qfluentwidgets InfoBar 实现
    /// </summary>
    public partial class InfoBar : UserControl
    {
        /// <summary>
        /// 通知关闭事件
        /// </summary>
        public event EventHandler Closed;

        private readonly InfoBarType _type;
        private System.Windows.Threading.DispatcherTimer _autoCloseTimer;

        /// <summary>
        /// 创建 InfoBar
        /// </summary>
        /// <param name="type">通知类型</param>
        /// <param name="title">标题</param>
        /// <param name="content">内容（可选）</param>
        /// <param name="autoCloseMs">自动关闭毫秒数，0=不自动关闭</param>
        public InfoBar(InfoBarType type, string title, string content = "", int autoCloseMs = 3000)
        {
            InitializeComponent();
            _type = type;
            DataContext = this;

            TitleText.Text = title;
            if (string.IsNullOrEmpty(content))
            {
                ContentText.Visibility = Visibility.Collapsed;
            }
            else
            {
                ContentText.Text = content;
            }

            ApplyTypeStyle();

            if (autoCloseMs > 0)
            {
                _autoCloseTimer = new System.Windows.Threading.DispatcherTimer
                {
                    Interval = TimeSpan.FromMilliseconds(autoCloseMs)
                };
                _autoCloseTimer.Tick += (s, e) => Close();
                _autoCloseTimer.Start();
            }
        }

        /// <summary>
        /// 根据类型应用颜色和图标
        /// </summary>
        private void ApplyTypeStyle()
        {
            Color bgColor, borderColor, iconColor;
            string icon;

            switch (_type)
            {
                case InfoBarType.Success:
                    bgColor = Color.FromArgb(0x14, 0x52, 0xC4, 0x1A);
                    borderColor = Color.FromArgb(0x40, 0x52, 0xC4, 0x1A);
                    iconColor = Color.FromRgb(0x52, 0xC4, 0x1A);
                    icon = "✓";
                    break;
                case InfoBarType.Warning:
                    bgColor = Color.FromArgb(0x14, 0xFA, 0xAD, 0x14);
                    borderColor = Color.FromArgb(0x40, 0xFA, 0xAD, 0x14);
                    iconColor = Color.FromRgb(0xFA, 0xAD, 0x14);
                    icon = "⚠";
                    break;
                case InfoBarType.Error:
                    bgColor = Color.FromArgb(0x14, 0xEA, 0x66, 0x68);
                    borderColor = Color.FromArgb(0x40, 0xEA, 0x66, 0x68);
                    iconColor = Color.FromRgb(0xEA, 0x66, 0x68);
                    icon = "✕";
                    break;
                default:
                    bgColor = Color.FromArgb(0x14, 0x4F, 0x46, 0xE5);
                    borderColor = Color.FromArgb(0x40, 0x4F, 0x46, 0xE5);
                    iconColor = Color.FromRgb(0x4F, 0x46, 0xE5);
                    icon = "ⓘ";
                    break;
            }

            RootBorder.Background = new SolidColorBrush(bgColor);
            RootBorder.BorderBrush = new SolidColorBrush(borderColor);
            IconText.Foreground = new SolidColorBrush(iconColor);
            IconText.Text = icon;
        }

        /// <summary>
        /// 关闭按钮点击
        /// </summary>
        private void CloseButton_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }

        /// <summary>
        /// 关闭通知（淡出动画后触发 Closed 事件）
        /// </summary>
        public void Close()
        {
            _autoCloseTimer?.Stop();

            var fadeOut = new DoubleAnimation(0, TimeSpan.FromMilliseconds(200));
            fadeOut.Completed += (s, e) => Closed?.Invoke(this, EventArgs.Empty);
            BeginAnimation(OpacityProperty, fadeOut);
        }
    }
}
