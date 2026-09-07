using System;
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json;
using OpenCpolarSync.Client.Models;

namespace OpenCpolarSync.Client.Services
{
    /// <summary>
    /// 配置管理服务 — 负责 config.json 的读写、校验和热重载检测
    /// </summary>
    public class ConfigService
    {
        private readonly string _configPath;
        private FileSystemWatcher _watcher;

        /// <summary>
        /// 配置文件变更事件（热重载）
        /// </summary>
        public event EventHandler<CpolarConfig> ConfigChanged;

        public ConfigService(string configPath)
        {
            _configPath = configPath;
        }

        /// <summary>
        /// 从文件加载配置，文件不存在时返回默认配置
        /// </summary>
        public CpolarConfig Load()
        {
            try
            {
                if (!File.Exists(_configPath))
                {
                    return new CpolarConfig();
                }

                var json = File.ReadAllText(_configPath, System.Text.Encoding.UTF8);
                var config = JsonConvert.DeserializeObject<CpolarConfig>(json);
                return config ?? new CpolarConfig();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[ConfigService] 加载配置失败: {ex.Message}");
                return new CpolarConfig();
            }
        }

        /// <summary>
        /// 保存配置到文件，自动创建目录
        /// </summary>
        public bool Save(CpolarConfig config)
        {
            try
            {
                var dir = Path.GetDirectoryName(_configPath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                var json = JsonConvert.SerializeObject(config, Formatting.Indented);
                File.WriteAllText(_configPath, json, System.Text.Encoding.UTF8);
                return true;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[ConfigService] 保存配置失败: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// 校验配置，返回错误信息列表
        /// </summary>
        public List<string> Validate(CpolarConfig config)
        {
            var errors = new List<string>();

            if (string.IsNullOrWhiteSpace(config.WebhookUrl))
            {
                errors.Add("钉钉 Webhook 地址不能为空");
            }
            else if (!config.WebhookUrl.StartsWith("http"))
            {
                errors.Add("钉钉 Webhook 地址格式不正确");
            }

            if (config.Interval < 1)
            {
                errors.Add("轮询间隔不能小于 1 分钟");
            }

            if (string.IsNullOrWhiteSpace(config.CpolarApiBase))
            {
                errors.Add("Cpolar API 地址不能为空");
            }

            if (string.IsNullOrWhiteSpace(config.Username))
            {
                errors.Add("Cpolar 登录邮箱不能为空");
            }

            if (string.IsNullOrWhiteSpace(config.Password))
            {
                errors.Add("Cpolar 登录密码不能为空");
            }

            return errors;
        }

        /// <summary>
        /// 启动配置文件热重载监听
        /// </summary>
        public void StartWatching()
        {
            if (_watcher != null) return;

            var dir = Path.GetDirectoryName(_configPath);
            var file = Path.GetFileName(_configPath);

            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return;

            _watcher = new FileSystemWatcher(dir, file)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName,
                EnableRaisingEvents = true
            };
            _watcher.Changed += OnConfigFileChanged;
            _watcher.Created += OnConfigFileChanged;
        }

        /// <summary>
        /// 停止配置文件热重载监听
        /// </summary>
        public void StopWatching()
        {
            if (_watcher != null)
            {
                _watcher.EnableRaisingEvents = false;
                _watcher.Dispose();
                _watcher = null;
            }
        }

        private void OnConfigFileChanged(object sender, FileSystemEventArgs e)
        {
            // 防抖：FileSystemWatcher 可能触发多次，延迟加载
            System.Threading.Thread.Sleep(200);
            var config = Load();
            ConfigChanged?.Invoke(this, config);
        }
    }
}
