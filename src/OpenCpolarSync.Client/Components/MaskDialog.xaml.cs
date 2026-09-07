using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace OpenCpolarSync.Client.Components
{
    /// <summary>
    /// 遮罩式对话框 — 半透明遮罩覆盖窗口，居中显示卡片
    /// 参考 Ghost-Downloader-3 的 MaskDialogBase / MessageBox 实现
    /// </summary>
    public partial class MaskDialog : UserControl
    {
        /// <summary>
        /// 对话框结果
        /// </summary>
        public MessageBoxResult Result { get; private set; } = MessageBoxResult.Cancel;

        private readonly Window _owner;
        private Grid _overlay;

        /// <summary>
        /// 创建遮罩对话框
        /// </summary>
        /// <param name="owner">宿主窗口</param>
        /// <param name="title">标题</param>
        /// <param name="content">内容文字</param>
        /// <param name="yesButtonText">确认按钮文字</param>
        /// <param name="cancelButtonText">取消按钮文字（为空则只显示确认按钮）</param>
        public MaskDialog(Window owner, string title, string content,
            string yesButtonText = "确定", string cancelButtonText = "取消")
        {
            InitializeComponent();
            _owner = owner;

            TitleText.Text = title;
            ContentText.Text = content;
            YesButton.Content = yesButtonText;

            if (string.IsNullOrEmpty(cancelButtonText))
            {
                CancelButton.Visibility = Visibility.Collapsed;
            }
            else
            {
                CancelButton.Content = cancelButtonText;
            }
        }

        /// <summary>
        /// 显示对话框（模态，阻塞 UI 线程）
        /// </summary>
        /// <returns>用户点击的按钮结果</returns>
        public MessageBoxResult ShowDialog()
        {
            if (_owner?.Content is Grid rootGrid)
            {
                _overlay = new Grid
                {
                    Background = new SolidColorBrush(Color.FromArgb(0x80, 0, 0, 0)),
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    VerticalAlignment = VerticalAlignment.Stretch
                };
                Grid.SetRowSpan(_overlay, 10);
                Grid.SetColumnSpan(_overlay, 10);
                Panel.SetZIndex(_overlay, 9999);

                var center = new Grid
                {
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                    MaxWidth = 420
                };
                center.Children.Add(this);
                _overlay.Children.Add(center);

                rootGrid.Children.Add(_overlay);

                // 淡入动画
                var fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(150));
                _overlay.BeginAnimation(OpacityProperty, fadeIn);
            }

            // 简单的模态等待：用 DispatcherFrame 阻塞
            var frame = new System.Windows.Threading.DispatcherFrame();
            YesButton.Click += (s, e) => { Result = MessageBoxResult.Yes; frame.Continue = false; };
            CancelButton.Click += (s, e) => { Result = MessageBoxResult.Cancel; frame.Continue = false; };

            System.Windows.Threading.Dispatcher.PushFrame(frame);

            Close();
            return Result;
        }

        /// <summary>
        /// 关闭并移除遮罩
        /// </summary>
        private void Close()
        {
            if (_overlay != null && _owner?.Content is Grid rootGrid)
            {
                var fadeOut = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(150));
                fadeOut.Completed += (s, e) =>
                {
                    rootGrid.Children.Remove(_overlay);
                    _overlay = null;
                };
                _overlay.BeginAnimation(OpacityProperty, fadeOut);
            }
        }

        private void YesButton_Click(object sender, RoutedEventArgs e) { }
        private void CancelButton_Click(object sender, RoutedEventArgs e) { }
    }
}
