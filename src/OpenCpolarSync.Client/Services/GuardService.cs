using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using OpenCpolarSync.Client.Models;

namespace OpenCpolarSync.Client.Services
{
    /// <summary>
    /// 守护服务 — 统一管理 CpolarMonitor 和 OpenlistMonitor，协调启动/停止
    /// </summary>
    public class GuardService : IDisposable
    {
        private readonly CpolarMonitor _cpolarMonitor;
        private readonly OpenlistMonitor _openlistMonitor;
        private readonly DingTalkService _dingTalkService;
        private CpolarConfig _config;
        private bool _disposed;

        /// <summary>
        /// Cpolar 监控实例
        /// </summary>
        public CpolarMonitor CpolarMonitor => _cpolarMonitor;

        /// <summary>
        /// Openlist 守护实例
        /// </summary>
        public OpenlistMonitor OpenlistMonitor => _openlistMonitor;

        /// <summary>
        /// 全局日志事件
        /// </summary>
        public event EventHandler<string> LogMessage;

        /// <summary>
        /// 状态变更事件
        /// </summary>
        public event EventHandler<StatusChangedEventArgs> StatusChanged;

        public GuardService(string openlistExePath, string openlistWorkDir)
        {
            _cpolarMonitor = new CpolarMonitor();
            _openlistMonitor = new OpenlistMonitor(openlistExePath, openlistWorkDir);
            _dingTalkService = new DingTalkService();

            // 转发日志事件
            _cpolarMonitor.LogMessage += (s, e) => LogMessage?.Invoke(this, e);
            _openlistMonitor.LogMessage += (s, e) => LogMessage?.Invoke(this, e);

            // 转发状态事件
            _cpolarMonitor.StatusChanged += (s, e) => StatusChanged?.Invoke(this, e);
            _openlistMonitor.StatusChanged += (s, e) => StatusChanged?.Invoke(this, e);

            // 隧道变更时推送钉钉
            _cpolarMonitor.TunnelChanged += OnTunnelChanged;
        }

        /// <summary>
        /// 启动全部守护
        /// </summary>
        public void StartAll(CpolarConfig config)
        {
            _config = config;
            _cpolarMonitor.Start(config);
            EnsureCpolarRunning();
            _openlistMonitor.Start();
            OnLog("[GuardService] 全部守护已启动");
        }

        /// <summary>
        /// 停止全部守护
        /// </summary>
        public void StopAll()
        {
            _cpolarMonitor.Stop();
            _openlistMonitor.Stop();
            OnLog("[GuardService] 全部守护已停止");
        }

        /// <summary>
        /// 仅启动 Cpolar 监控
        /// </summary>
        public void StartCpolar(CpolarConfig config)
        {
            _config = config;
            _cpolarMonitor.Start(config);
            EnsureCpolarRunning();
        }

        /// <summary>
        /// 仅停止 Cpolar 监控
        /// </summary>
        public void StopCpolar()
        {
            _cpolarMonitor.Stop();
        }

        /// <summary>
        /// 仅启动 Openlist 守护
        /// </summary>
        public void StartOpenlist()
        {
            _openlistMonitor.Start();
        }

        /// <summary>
        /// 仅停止 Openlist 守护
        /// </summary>
        public void StopOpenlist()
        {
            _openlistMonitor.Stop();
        }

        /// <summary>
        /// 确保 cpolar 进程已在运行 — 已安装但未运行时自动拉起，避免主界面进程 ID 恒为 0
        /// 仅做启动守护时的保活，不负责崩溃后的自动重启循环
        /// </summary>
        private void EnsureCpolarRunning()
        {
            try
            {
                // 已运行则不重复拉起，避免重复实例与端口冲突
                if (Process.GetProcessesByName("cpolar").Length > 0) return;

                // 未安装时无法启动
                var installPath = InstallDetectionService.GetCpolarInstallPath();
                if (string.IsNullOrEmpty(installPath)) return;

                var exePath = Path.Combine(installPath, "cpolar.exe");
                if (!File.Exists(exePath)) return;

                // 与 openlist 同理：cpolar 为 Go 程序，用 UseShellExecute 提供控制台环境，避免启动后立即退出
                var startInfo = new ProcessStartInfo
                {
                    FileName = exePath,
                    WorkingDirectory = installPath,
                    UseShellExecute = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                Process.Start(startInfo);
                OnLog("[GuardService] cpolar.exe 未运行，已自动启动");
            }
            catch (Exception ex)
            {
                OnLog($"[GuardService] 自动启动 cpolar.exe 失败: {ex.Message}");
            }
        }

        /// <summary>
        /// 更新 Cpolar 配置（热重载）
        /// </summary>
        public void UpdateCpolarConfig(CpolarConfig config)
        {
            _config = config;
            _cpolarMonitor.UpdateConfig(config);
        }

        /// <summary>
        /// 隧道变更时构建并推送钉钉消息
        /// </summary>
        private async void OnTunnelChanged(object sender, TunnelChangedEventArgs e)
        {
            if (_config == null || string.IsNullOrEmpty(_config.WebhookUrl)) return;

            try
            {
                var sb = new StringBuilder();
                sb.AppendLine($"{_config.Keyword}");
                sb.AppendLine();
                sb.AppendLine("## Cpolar 监控报告");
                sb.AppendLine();
                sb.AppendLine("━━━ 隧道状态变更 ━━━");
                sb.AppendLine();

                foreach (var change in e.Changes)
                {
                    string emoji;
                    string title;
                    switch (change.ChangeType)
                    {
                        case TunnelChangeType.Added:
                            emoji = "🟢"; title = "新增上线"; break;
                        case TunnelChangeType.Reconnected:
                            emoji = "🟢"; title = "重新上线"; break;
                        case TunnelChangeType.Updated:
                            emoji = "🔄"; title = "信息变更"; break;
                        case TunnelChangeType.Removed:
                            emoji = "🔴"; title = "已离线"; break;
                        default:
                            emoji = "ℹ️"; title = "变更"; break;
                    }

                    sb.AppendLine($"**{emoji} {change.Tunnel.Name} — {title}**");
                    sb.AppendLine($"- 协议：{change.Tunnel.Protocol}");
                    sb.AppendLine($"- 公网地址：{change.Tunnel.PublicUrl}");
                    sb.AppendLine($"- 本地地址：{change.Tunnel.LocalAddr}");
                    sb.AppendLine();
                }

                sb.AppendLine("---");
                sb.AppendLine($"⏱ 检测时间：{DateTime.Now:yyyy-MM-dd HH:mm:ss}");

                await _dingTalkService.SendMarkdownAsync(
                    _config.WebhookUrl, "Cpolar 监控报告", sb.ToString());

                OnLog($"[GuardService] 隧道变更已推送钉钉，{e.Changes.Count} 项变更");
            }
            catch (Exception ex)
            {
                OnLog($"[GuardService] 钉钉推送异常: {ex.Message}");
            }
        }

        private void OnLog(string message)
        {
            LogMessage?.Invoke(this, message);
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _cpolarMonitor?.Dispose();
                _openlistMonitor?.Dispose();
                _disposed = true;
            }
        }
    }
}
