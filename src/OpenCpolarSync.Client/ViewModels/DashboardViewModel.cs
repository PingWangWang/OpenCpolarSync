using System.ComponentModel;
using System.Runtime.CompilerServices;
using OpenCpolarSync.Client.Models;

namespace OpenCpolarSync.Client.ViewModels
{
    /// <summary>
    /// 总览视图模型 — 展示两个服务的状态和快捷操作
    /// </summary>
    public class DashboardViewModel : INotifyPropertyChanged
    {
        private ServiceStatus _cpolarStatus = ServiceStatus.Stopped;
        private ServiceStatus _openlistStatus = ServiceStatus.Stopped;
        private int _cpolarTunnelCount;
        private int _cpolarProcessId;
        private int _openlistProcessId;
        private string _lastPushTime = "—";

        public ServiceStatus CpolarStatus
        {
            get => _cpolarStatus;
            set { _cpolarStatus = value; OnPropertyChanged(); OnPropertyChanged(nameof(CpolarStatusText)); }
        }

        public ServiceStatus OpenlistStatus
        {
            get => _openlistStatus;
            set { _openlistStatus = value; OnPropertyChanged(); OnPropertyChanged(nameof(OpenlistStatusText)); }
        }

        public int CpolarTunnelCount
        {
            get => _cpolarTunnelCount;
            set { _cpolarTunnelCount = value; OnPropertyChanged(); }
        }

        public int CpolarProcessId
        {
            get => _cpolarProcessId;
            set { _cpolarProcessId = value; OnPropertyChanged(); }
        }

        public int OpenlistProcessId
        {
            get => _openlistProcessId;
            set { _openlistProcessId = value; OnPropertyChanged(); }
        }

        public string LastPushTime
        {
            get => _lastPushTime;
            set { _lastPushTime = value; OnPropertyChanged(); }
        }

        public string CpolarStatusText => GetStatusText(_cpolarStatus);
        public string OpenlistStatusText => GetStatusText(_openlistStatus);

        private static string GetStatusText(ServiceStatus status)
        {
            switch (status)
            {
                case ServiceStatus.Running: return "● 运行中";
                case ServiceStatus.Stopped: return "○ 已停止";
                case ServiceStatus.Starting: return "◐ 启动中...";
                case ServiceStatus.Stopping: return "◐ 停止中...";
                case ServiceStatus.Error: return "● 异常";
                default: return "?";
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
