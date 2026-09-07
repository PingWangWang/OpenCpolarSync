using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using OpenCpolarSync.Client.Models;

namespace OpenCpolarSync.Client.ViewModels
{
    /// <summary>
    /// 主视图模型 — 持有全局服务实例和共享状态
    /// </summary>
    public class MainViewModel : INotifyPropertyChanged
    {
        private ServiceStatus _cpolarStatus = ServiceStatus.Stopped;
        private ServiceStatus _openlistStatus = ServiceStatus.Stopped;
        private string _statusMessage = "就绪";

        /// <summary>
        /// Cpolar 服务状态
        /// </summary>
        public ServiceStatus CpolarStatus
        {
            get => _cpolarStatus;
            set { _cpolarStatus = value; OnPropertyChanged(); OnPropertyChanged(nameof(CpolarStatusText)); }
        }

        /// <summary>
        /// Openlist 服务状态
        /// </summary>
        public ServiceStatus OpenlistStatus
        {
            get => _openlistStatus;
            set { _openlistStatus = value; OnPropertyChanged(); OnPropertyChanged(nameof(OpenlistStatusText)); }
        }

        /// <summary>
        /// 状态消息
        /// </summary>
        public string StatusMessage
        {
            get => _statusMessage;
            set { _statusMessage = value; OnPropertyChanged(); }
        }

        public string CpolarStatusText => GetStatusText(_cpolarStatus);
        public string OpenlistStatusText => GetStatusText(_openlistStatus);

        /// <summary>
        /// 日志列表
        /// </summary>
        public List<string> Logs { get; } = new List<string>();

        private static string GetStatusText(ServiceStatus status)
        {
            switch (status)
            {
                case ServiceStatus.Running: return "运行中";
                case ServiceStatus.Stopped: return "已停止";
                case ServiceStatus.Starting: return "启动中...";
                case ServiceStatus.Stopping: return "停止中...";
                case ServiceStatus.Error: return "异常";
                default: return "未知";
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
