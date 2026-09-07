using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using OpenCpolarSync.Client.Models;

namespace OpenCpolarSync.Client.Services
{
    /// <summary>
    /// Cpolar 隧道监控服务 — 自动登录获取 JWT Token，轮询隧道列表，检测变更并触发事件
    /// 替代原 CpolarGuard.ps1 的核心逻辑
    /// </summary>
    public class CpolarMonitor : IDisposable
    {
        private readonly HttpClient _httpClient;
        private Timer _pollTimer;
        private string _apiToken;
        private List<TunnelInfo> _lastTunnels = new List<TunnelInfo>();
        private CpolarConfig _config;
        private int _consecutiveApiFails;
        private bool _isFirstRun = true;
        private bool _disposed;

        /// <summary>
        /// 隧道变更事件（新增/更新/重连/离线）
        /// </summary>
        public event EventHandler<TunnelChangedEventArgs> TunnelChanged;

        /// <summary>
        /// 状态变更事件
        /// </summary>
        public event EventHandler<StatusChangedEventArgs> StatusChanged;

        /// <summary>
        /// 日志事件
        /// </summary>
        public event EventHandler<string> LogMessage;

        /// <summary>
        /// 当前监控的隧道列表
        /// </summary>
        public IReadOnlyList<TunnelInfo> CurrentTunnels => _lastTunnels.AsReadOnly();

        /// <summary>
        /// API 连续失败次数
        /// </summary>
        public int ConsecutiveApiFails => _consecutiveApiFails;

        /// <summary>
        /// 当前 cpolar 进程 ID（0 表示未运行）
        /// </summary>
        public int CurrentProcessId
        {
            get
            {
                try
                {
                    // 先尝试精确匹配进程名
                    var procs = System.Diagnostics.Process.GetProcessesByName("cpolar");
                    if (procs.Length > 0) return procs[0].Id;

                    // 回退：遍历所有进程，匹配进程名包含 cpolar 的（处理服务模式或不同进程名的情况）
                    foreach (var p in System.Diagnostics.Process.GetProcesses())
                    {
                        try
                        {
                            if (p.ProcessName.IndexOf("cpolar", System.StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                return p.Id;
                            }
                        }
                        catch { }
                    }

                    // 回退：用 WMI 查询，覆盖作为服务/运行在不同会话的进程（普通进程枚举受限时的兜底）
                    using (var searcher = new ManagementObjectSearcher(
                        "SELECT ProcessId FROM Win32_Process WHERE Name='cpolar.exe'"))
                    {
                        foreach (var obj in searcher.Get())
                        {
                            var pid = obj["ProcessId"];
                            if (pid != null) return Convert.ToInt32(pid);
                        }
                    }
                }
                catch { }
                return 0;
            }
        }

        public CpolarMonitor()
        {
            _httpClient = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(15)
            };
        }

        /// <summary>
        /// 启动监控
        /// </summary>
        public void Start(CpolarConfig config)
        {
            _config = config;
            _isFirstRun = true;
            _consecutiveApiFails = 0;

            var intervalMs = Math.Max(60, config.Interval) * 1000;
            _pollTimer = new Timer(async _ => await PollAsync(), null, 0, intervalMs);

            OnStatusChanged(ServiceStatus.Running, "Cpolar 监控已启动");
            OnLog($"[CpolarMonitor] 启动，轮询间隔 {config.Interval} 分钟");
        }

        /// <summary>
        /// 停止监控
        /// </summary>
        public void Stop()
        {
            _pollTimer?.Dispose();
            _pollTimer = null;
            _apiToken = null;
            OnStatusChanged(ServiceStatus.Stopped, "Cpolar 监控已停止");
            OnLog("[CpolarMonitor] 已停止");
        }

        /// <summary>
        /// 更新配置（热重载）
        /// </summary>
        public void UpdateConfig(CpolarConfig config)
        {
            var oldInterval = _config?.Interval ?? 1;
            _config = config;

            if (oldInterval != config.Interval && _pollTimer != null)
            {
                var intervalMs = Math.Max(60, config.Interval) * 1000;
                _pollTimer.Change(0, intervalMs);
                OnLog($"[CpolarMonitor] 轮询间隔已更新为 {config.Interval} 分钟");
            }
        }

        /// <summary>
        /// 执行一次轮询
        /// </summary>
        private async Task PollAsync()
        {
            try
            {
                var tunnels = await FetchTunnelsAsync();
                if (tunnels == null)
                {
                    _consecutiveApiFails++;
                    OnLog($"[CpolarMonitor] API 请求失败（连续 {_consecutiveApiFails} 次）");
                    return;
                }

                if (_consecutiveApiFails > 0)
                {
                    OnLog($"[CpolarMonitor] API 已恢复（之前连续失败 {_consecutiveApiFails} 次）");
                    _consecutiveApiFails = 0;
                }

                // 筛选勾选的隧道
                var selected = FilterSelectedTunnels(tunnels);

                // 检测变更
                if (!_isFirstRun)
                {
                    var changes = DetectChanges(_lastTunnels, selected);
                    if (changes.Count > 0)
                    {
                        OnTunnelChanged(changes);
                    }
                }

                _lastTunnels = selected;
                _isFirstRun = false;
            }
            catch (Exception ex)
            {
                OnLog($"[CpolarMonitor] 轮询异常: {ex.Message}");
            }
        }

        /// <summary>
        /// 登录 Cpolar 获取 JWT Token
        /// </summary>
        private async Task<string> LoginAsync()
        {
            try
            {
                var loginUrl = $"{_config.CpolarApiBase.TrimEnd('/')}/api/v1/user/login";
                var body = new { email = _config.Username, password = _config.Password };
                var json = JsonConvert.SerializeObject(body);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                var response = await _httpClient.PostAsync(loginUrl, content);
                var responseBody = await response.Content.ReadAsStringAsync();
                var result = JObject.Parse(responseBody);

                // 兼容多种响应格式
                string token = null;
                if (result["code"]?.Value<int>() == 0 && result["data"]?["token"] != null)
                {
                    token = result["data"]["token"].Value<string>();
                }
                else if (result["data"]?["token"] != null)
                {
                    token = result["data"]["token"].Value<string>();
                }
                else if (result["token"] != null)
                {
                    token = result["token"].Value<string>();
                }

                if (!string.IsNullOrEmpty(token))
                {
                    OnLog("[CpolarMonitor] 登录成功");
                    return token;
                }

                OnLog($"[CpolarMonitor] 登录失败: {result["message"]}");
                return null;
            }
            catch (Exception ex)
            {
                OnLog($"[CpolarMonitor] 登录异常: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// 获取隧道列表
        /// </summary>
        private async Task<List<TunnelInfo>> FetchTunnelsAsync()
        {
            if (string.IsNullOrEmpty(_apiToken))
            {
                _apiToken = await LoginAsync();
                if (string.IsNullOrEmpty(_apiToken)) return null;
            }

            var apiUrl = $"{_config.CpolarApiBase.TrimEnd('/')}/api/v1/tunnels";

            try
            {
                _httpClient.DefaultRequestHeaders.Authorization =
                    new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _apiToken);

                var response = await _httpClient.GetAsync(apiUrl);
                var responseBody = await response.Content.ReadAsStringAsync();
                var result = JObject.Parse(responseBody);

                // 业务错误码处理：非 20000 视为失败
                var code = result["code"]?.Value<int>() ?? -1;
                if (code != 20000)
                {
                    if (code == 50014) // Token 过期
                    {
                        OnLog("[CpolarMonitor] Token 已过期，重新登录...");
                        _apiToken = await LoginAsync();
                        if (string.IsNullOrEmpty(_apiToken)) return null;

                        // 重试一次
                        _httpClient.DefaultRequestHeaders.Authorization =
                            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _apiToken);
                        response = await _httpClient.GetAsync(apiUrl);
                        responseBody = await response.Content.ReadAsStringAsync();
                        result = JObject.Parse(responseBody);
                        code = result["code"]?.Value<int>() ?? -1;
                    }

                    if (code != 20000)
                    {
                        OnLog($"[CpolarMonitor] API 返回错误码 code={code}: {result["message"]}");
                        return null;
                    }
                }

                // 解析隧道列表
                var tunnels = new List<TunnelInfo>();
                var items = result["data"]?["items"];
                if (items != null)
                {
                    foreach (var item in items)
                    {
                        var tunnel = ParseTunnel(item);
                        if (tunnel != null) tunnels.Add(tunnel);
                    }
                }

                return tunnels;
            }
            catch (Exception ex)
            {
                OnLog($"[CpolarMonitor] 获取隧道列表异常: {ex.Message}");
                return null;
            }
        }

        /// <summary>
        /// 解析单个隧道数据
        /// </summary>
        private TunnelInfo ParseTunnel(JToken item)
        {
            try
            {
                var tunnel = new TunnelInfo
                {
                    Id = item["id"]?.Value<string>() ?? "",
                    Name = item["name"]?.Value<string>() ?? "",
                    Status = item["status"]?.Value<string>() ?? ""
                };

                // 从 publish_tunnels 提取协议和公网地址
                var pub = item["publish_tunnels"]?.FirstOrDefault();
                if (pub != null)
                {
                    tunnel.Protocol = pub["proto"]?.Value<string>() ?? "";
                    tunnel.PublicUrl = pub["public_url"]?.Value<string>() ?? "";
                    if (pub["create_datetime"] != null)
                    {
                        tunnel.CreateTime = pub["create_datetime"].Value<string>();
                    }
                }

                // 本地地址
                var cfg = item["configuration"];
                if (cfg != null && cfg["addr"] != null)
                {
                    tunnel.LocalAddr = $"http://localhost:{cfg["addr"].Value<string>()}";
                }

                return tunnel;
            }
            catch
            {
                return null;
            }
        }

        /// <summary>
        /// 筛选勾选的隧道
        /// </summary>
        private List<TunnelInfo> FilterSelectedTunnels(List<TunnelInfo> tunnels)
        {
            if (_config.SelectedTunnelNames == null || _config.SelectedTunnelNames.Count == 0)
            {
                return new List<TunnelInfo>();
            }

            return tunnels
                .Where(t => _config.SelectedTunnelNames.Contains(t.Name))
                .ToList();
        }

        /// <summary>
        /// 检测隧道变更
        /// </summary>
        private List<TunnelChangeInfo> DetectChanges(List<TunnelInfo> oldList, List<TunnelInfo> newList)
        {
            var changes = new List<TunnelChangeInfo>();
            var oldMap = oldList.ToDictionary(t => t.CompositeKey);
            var newMap = newList.ToDictionary(t => t.CompositeKey);

            foreach (var kv in newMap)
            {
                if (!oldMap.ContainsKey(kv.Key))
                {
                    changes.Add(new TunnelChangeInfo { Tunnel = kv.Value, ChangeType = TunnelChangeType.Added });
                }
                else
                {
                    var old = oldMap[kv.Key];
                    var newT = kv.Value;

                    if (newT.Status == "inactive" && old.Status != "inactive")
                    {
                        changes.Add(new TunnelChangeInfo { Tunnel = newT, ChangeType = TunnelChangeType.Removed });
                    }
                    else if (old.Status == "inactive" && newT.Status != "inactive")
                    {
                        changes.Add(new TunnelChangeInfo { Tunnel = newT, ChangeType = TunnelChangeType.Reconnected });
                    }
                    else if (old.PublicUrl != newT.PublicUrl || old.Protocol != newT.Protocol || old.LocalAddr != newT.LocalAddr)
                    {
                        changes.Add(new TunnelChangeInfo { Tunnel = newT, ChangeType = TunnelChangeType.Updated });
                    }
                    else if (old.CreateTime != newT.CreateTime && !string.IsNullOrEmpty(newT.CreateTime))
                    {
                        changes.Add(new TunnelChangeInfo { Tunnel = newT, ChangeType = TunnelChangeType.Reconnected });
                    }
                }
            }

            foreach (var kv in oldMap)
            {
                if (!newMap.ContainsKey(kv.Key))
                {
                    var t = kv.Value;
                    t.Status = "offline";
                    changes.Add(new TunnelChangeInfo { Tunnel = t, ChangeType = TunnelChangeType.Removed });
                }
            }

            return changes;
        }

        private void OnTunnelChanged(List<TunnelChangeInfo> changes)
        {
            TunnelChanged?.Invoke(this, new TunnelChangedEventArgs(changes));
        }

        private void OnStatusChanged(ServiceStatus status, string message)
        {
            StatusChanged?.Invoke(this, new StatusChangedEventArgs("Cpolar", status, message));
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
                _httpClient?.Dispose();
                _disposed = true;
            }
        }
    }

    /// <summary>
    /// 隧道变更信息
    /// </summary>
    public class TunnelChangeInfo
    {
        public TunnelInfo Tunnel { get; set; }
        public TunnelChangeType ChangeType { get; set; }
    }

    /// <summary>
    /// 隧道变更事件参数
    /// </summary>
    public class TunnelChangedEventArgs : EventArgs
    {
        public List<TunnelChangeInfo> Changes { get; }

        public TunnelChangedEventArgs(List<TunnelChangeInfo> changes)
        {
            Changes = changes;
        }
    }
}
