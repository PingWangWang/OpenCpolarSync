using System.Collections.Generic;
using Newtonsoft.Json;

namespace OpenCpolarSync.Client.Models
{
    /// <summary>
    /// Cpolar 配置模型 — 对应 config/config.json，支持 JSON 序列化/反序列化
    /// </summary>
    public class CpolarConfig
    {
        /// <summary>
        /// 钉钉机器人 Webhook 地址
        /// </summary>
        [JsonProperty("webhookUrl")]
        public string WebhookUrl { get; set; } = "";

        /// <summary>
        /// 轮询检测间隔（分钟，最小 1）
        /// </summary>
        [JsonProperty("interval")]
        public int Interval { get; set; } = 1;

        /// <summary>
        /// 要监控的隧道名称列表
        /// </summary>
        [JsonProperty("selectedTunnelNames")]
        public List<string> SelectedTunnelNames { get; set; } = new List<string>();

        /// <summary>
        /// Cpolar Web 管理界面地址
        /// </summary>
        [JsonProperty("cpolarApiBase")]
        public string CpolarApiBase { get; set; } = "http://localhost:9200";

        /// <summary>
        /// Cpolar Web 登录邮箱
        /// </summary>
        [JsonProperty("username")]
        public string Username { get; set; } = "";

        /// <summary>
        /// Cpolar Web 登录密码
        /// </summary>
        [JsonProperty("password")]
        public string Password { get; set; } = "";

        /// <summary>
        /// 钉钉机器人安全关键词
        /// </summary>
        [JsonProperty("keyword")]
        public string Keyword { get; set; } = "Cpolar";

        /// <summary>
        /// 调试日志开关
        /// </summary>
        [JsonProperty("debug")]
        public bool Debug { get; set; } = false;

        /// <summary>
        /// Openlist 管理界面登录密码
        /// </summary>
        [JsonProperty("openlistPassword")]
        public string OpenlistPassword { get; set; } = "";

        /// <summary>
        /// 界面主题（Light / Dark）
        /// </summary>
        [JsonProperty("theme")]
        public string Theme { get; set; } = "Light";

        /// <summary>
        /// 深拷贝当前配置
        /// </summary>
        public CpolarConfig Clone()
        {
            var json = JsonConvert.SerializeObject(this);
            return JsonConvert.DeserializeObject<CpolarConfig>(json);
        }
    }
}
