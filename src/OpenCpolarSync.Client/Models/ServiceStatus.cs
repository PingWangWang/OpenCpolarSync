namespace OpenCpolarSync.Client.Models
{
    /// <summary>
    /// 服务运行状态枚举
    /// </summary>
    public enum ServiceStatus
    {
        /// <summary>
        /// 未启动
        /// </summary>
        Stopped,

        /// <summary>
        /// 运行中
        /// </summary>
        Running,

        /// <summary>
        /// 启动中
        /// </summary>
        Starting,

        /// <summary>
        /// 停止中
        /// </summary>
        Stopping,

        /// <summary>
        /// 异常
        /// </summary>
        Error
    }

    /// <summary>
    /// 隧道变更类型枚举
    /// </summary>
    public enum TunnelChangeType
    {
        /// <summary>
        /// 新增上线
        /// </summary>
        Added,

        /// <summary>
        /// 信息变更
        /// </summary>
        Updated,

        /// <summary>
        /// 重新上线
        /// </summary>
        Reconnected,

        /// <summary>
        /// 已离线
        /// </summary>
        Removed
    }

    /// <summary>
    /// 服务状态变更事件参数
    /// </summary>
    public class StatusChangedEventArgs : System.EventArgs
    {
        /// <summary>
        /// 服务名称（Cpolar / Openlist）
        /// </summary>
        public string ServiceName { get; set; }

        /// <summary>
        /// 新状态
        /// </summary>
        public ServiceStatus NewStatus { get; set; }

        /// <summary>
        /// 附加消息
        /// </summary>
        public string Message { get; set; }

        public StatusChangedEventArgs(string serviceName, ServiceStatus newStatus, string message = "")
        {
            ServiceName = serviceName;
            NewStatus = newStatus;
            Message = message;
        }
    }
}
