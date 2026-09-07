using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using OpenCpolarSync.Client.Models;

namespace OpenCpolarSync.Client.Services
{
    /// <summary>
    /// Openlist 进程守护服务 — 轮询 openlist.exe 进程，崩溃自动重启
    /// 替代原 OpenlistGuard.ps1 的核心逻辑
    /// </summary>
    public class OpenlistMonitor : IDisposable
    {
        private Timer _pollTimer;
        private Process _openlistProcess;
        private string _exePath;
        private string _workDir;
        private bool _disposed;
        private ServiceStatus _currentStatus = ServiceStatus.Stopped;
        private const int PollIntervalMs = 60000;   // 常规轮询间隔 60 秒

        /// <summary>
        /// 状态变更事件
        /// </summary>
        public event EventHandler<StatusChangedEventArgs> StatusChanged;

        /// <summary>
        /// 日志事件
        /// </summary>
        public event EventHandler<string> LogMessage;

        /// <summary>
        /// 当前 openlist 进程 ID（0 表示未运行）
        /// </summary>
        public int CurrentProcessId => IsProcessAlive() ? _openlistProcess?.Id ?? 0 : 0;

        /// <summary>
        /// openlist 是否正在运行
        /// </summary>
        public bool IsRunning => IsProcessAlive();

        public OpenlistMonitor(string exePath, string workDir)
        {
            _exePath = exePath;
            _workDir = workDir;
        }

        /// <summary>
        /// 检测 openlist 进程是否还活着
        /// 完全采用按进程名模糊匹配的方式（与原 PowerShell 脚本 Get-Process 一致），
        /// 不依赖 Process.Start 返回的进程对象（启动器可能退出，实际工作进程 PID 不同）
        /// </summary>
        private bool IsProcessAlive()
        {
            try
            {
                // 方式1：精确匹配进程名 openlist
                var procs = Process.GetProcessesByName("openlist");
                if (procs.Length > 0)
                {
                    _openlistProcess = procs[0];
                    return true;
                }

                // 方式2：模糊匹配——遍历所有进程，匹配进程名包含 openlist 的
                // （处理 openlist.exe 实际进程名可能不同的情况）
                foreach (var p in Process.GetProcesses())
                {
                    try
                    {
                        if (p.ProcessName.IndexOf("openlist", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            _openlistProcess = p;
                            OnLog($"[OpenlistMonitor] 通过模糊匹配找到进程: {p.ProcessName} (PID={p.Id})");
                            return true;
                        }
                    }
                    catch { }
                }
            }
            catch (Exception ex)
            {
                OnLog($"[OpenlistMonitor] IsProcessAlive 异常: {ex.Message}");
            }
            return false;
        }

        /// <summary>
        /// 启动守护（非阻塞）
        /// </summary>
        public void Start()
        {
            // 先检查是否已在运行
            if (IsProcessAlive())
            {
                _currentStatus = ServiceStatus.Running;
                OnLog($"[OpenlistMonitor] openlist.exe 已在运行，PID={_openlistProcess.Id}");
                OnStatusChanged(ServiceStatus.Running, "Openlist 守护已启动");
            }
            else
            {
                // 未运行：先报启动中，再启动进程
                _currentStatus = ServiceStatus.Starting;
                OnStatusChanged(ServiceStatus.Starting, "正在启动 openlist.exe...");
                StartOpenlist();

                // 启动后立即确认：如果进程对象有效且未退出，直接报运行中
                if (IsProcessAlive())
                {
                    _currentStatus = ServiceStatus.Running;
                    OnStatusChanged(ServiceStatus.Running, $"openlist.exe 运行中，PID={_openlistProcess.Id}");
                }
                else
                {
                    OnLog("[OpenlistMonitor] openlist.exe 启动后立即退出，将在下一轮轮询中重试");
                }
            }

            _pollTimer = new Timer(PollCallback, null, PollIntervalMs, PollIntervalMs);
            OnLog("[OpenlistMonitor] 守护已启动，轮询间隔 60 秒");
        }

        /// <summary>
        /// 停止守护（不终止 openlist 进程）
        /// </summary>
        public void Stop()
        {
            _pollTimer?.Dispose();
            _pollTimer = null;
            _currentStatus = ServiceStatus.Stopped;
            OnStatusChanged(ServiceStatus.Stopped, "Openlist 守护已停止");
            OnLog("[OpenlistMonitor] 已停止");
        }

        /// <summary>
        /// 停止守护并终止 openlist 进程
        /// </summary>
        public void StopAndKill()
        {
            Stop();
            try
            {
                if (_openlistProcess != null && !_openlistProcess.HasExited)
                {
                    _openlistProcess.Kill();
                    OnLog($"[OpenlistMonitor] 已终止 openlist.exe，PID={_openlistProcess.Id}");
                }
            }
            catch (Exception ex)
            {
                OnLog($"[OpenlistMonitor] 终止进程失败: {ex.Message}");
            }
        }

        /// <summary>
        /// 轮询回调（在 ThreadPool 线程执行，不阻塞 UI）
        /// </summary>
        private void PollCallback(object state)
        {
            try
            {
                if (IsProcessAlive())
                {
                    // 进程运行中：如果之前不是 Running，更新状态
                    if (_currentStatus != ServiceStatus.Running)
                    {
                        _currentStatus = ServiceStatus.Running;
                        OnStatusChanged(ServiceStatus.Running, $"openlist.exe 运行中，PID={_openlistProcess.Id}");
                    }
                    OnLog($"[OpenlistMonitor] openlist.exe 运行中，PID={_openlistProcess.Id}");
                }
                else
                {
                    // 进程不在：先输出诊断日志，列出系统中所有包含 open 的进程
                    try
                    {
                        var found = new System.Text.StringBuilder();
                        foreach (var p in Process.GetProcesses())
                        {
                            try
                            {
                                if (p.ProcessName.IndexOf("open", StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    found.Append($"{p.ProcessName}(PID={p.Id}) ");
                                }
                            }
                            catch { }
                        }
                        if (found.Length > 0)
                        {
                            OnLog($"[OpenlistMonitor] 诊断：系统中包含 'open' 的进程: {found.ToString().Trim()}");
                        }
                        else
                        {
                            OnLog("[OpenlistMonitor] 诊断：系统中未找到任何包含 'open' 的进程");
                        }
                    }
                    catch { }

                    // 触发 Starting 状态，重启进程
                    if (_currentStatus != ServiceStatus.Starting)
                    {
                        _currentStatus = ServiceStatus.Starting;
                        OnStatusChanged(ServiceStatus.Starting, "openlist.exe 未响应，正在重启...");
                    }
                    OnLog("[OpenlistMonitor] openlist.exe 未找到，尝试重启...");
                    StartOpenlist();

                    // 重启后立即确认
                    if (IsProcessAlive())
                    {
                        _currentStatus = ServiceStatus.Running;
                        OnLog($"[OpenlistMonitor] openlist.exe 已重启，PID={_openlistProcess.Id}");
                        OnStatusChanged(ServiceStatus.Running, $"openlist.exe 运行中，PID={_openlistProcess.Id}");
                    }
                }
            }
            catch (Exception ex)
            {
                OnLog($"[OpenlistMonitor] 轮询异常: {ex.Message}");
            }
        }

        /// <summary>
        /// 启动 openlist.exe
        /// </summary>
        private void StartOpenlist()
        {
            try
            {
                if (!File.Exists(_exePath))
                {
                    OnLog($"[OpenlistMonitor] openlist.exe 未找到: {_exePath}");
                    _currentStatus = ServiceStatus.Error;
                    OnStatusChanged(ServiceStatus.Error, $"openlist.exe 未找到: {_exePath}");
                    return;
                }

                // 注意：必须使用 UseShellExecute=true（与 PowerShell Start-Process 行为一致）。
                // openlist.exe 是 Go 编写的控制台程序，UseShellExecute=false + CreateNoWindow=true
                // 会导致程序没有控制台环境，启动后立即退出。
                // ShellExecute 方式会为程序创建隐藏的控制台窗口，程序能正常运行。
                var startInfo = new ProcessStartInfo
                {
                    FileName = _exePath,
                    Arguments = "server",
                    WorkingDirectory = _workDir,
                    UseShellExecute = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                _openlistProcess = Process.Start(startInfo);
                if (_openlistProcess != null && _openlistProcess.Id > 0)
                {
                    OnLog($"[OpenlistMonitor] openlist.exe 已启动，PID={_openlistProcess.Id}");
                }
                else
                {
                    OnLog("[OpenlistMonitor] openlist.exe 启动失败");
                }
            }
            catch (Exception ex)
            {
                OnLog($"[OpenlistMonitor] 启动 openlist.exe 异常: {ex.Message}");
            }
        }

        /// <summary>
        /// 设置 openlist(alist) 管理员密码，通过 CLI `admin set` 直接改写数据目录中的密码
        /// 参数:
        ///     password: 新密码，仅当 openlist 已被初始化（存在 config.json）且服务未运行时生效
        /// 返回:
        ///     bool，是否应用成功；未初始化或服务运行中返回 false
        /// </summary>
        public bool SetAdminPassword(string password)
        {
            try
            {
                var dataDir = Path.Combine(_workDir, "data");
                // openlist(alist) 在数据目录不存在/未初始化时会自动初始化，无需预检；先确保目录存在
                Directory.CreateDirectory(dataDir);

                // [修改] 原因：alist 管理员用户名固定为 admin，CLI 仅支持改密码；`--data` 需指向数据目录
                var startInfo = new ProcessStartInfo
                {
                    FileName = _exePath,
                    Arguments = $"admin set \"{password}\" --data \"{dataDir}\"",
                    WorkingDirectory = _workDir,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using (var p = Process.Start(startInfo))
                {
                    var outp = p.StandardOutput.ReadToEnd();
                    var err = p.StandardError.ReadToEnd();
                    p.WaitForExit();
                    if (p.ExitCode == 0)
                    {
                        OnLog($"[OpenlistMonitor] admin 密码已更新: {(outp + " " + err).Trim()}");
                        return true;
                    }
                    OnLog($"[OpenlistMonitor] 设置密码失败(exit={p.ExitCode}): {(outp + " " + err).Trim()}");
                    return false;
                }
            }
            catch (Exception ex)
            {
                OnLog($"[OpenlistMonitor] 设置密码异常: {ex.Message}");
                return false;
            }
        }

        private void OnStatusChanged(ServiceStatus status, string message)
        {
            StatusChanged?.Invoke(this, new StatusChangedEventArgs("Openlist", status, message));
        }

        private void OnLog(string message)
        {
            LogMessage?.Invoke(this, message);
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _pollTimer?.Dispose();
                _openlistProcess?.Dispose();
                _disposed = true;
            }
        }
    }
}
