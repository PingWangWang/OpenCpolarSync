using Newtonsoft.Json;

namespace OpenCpolarSync.Client.Models
{
    /// <summary>
    /// 隧道信息模型 — 对应 Cpolar API 返回的隧道数据，含计算后的显示字段
    /// </summary>
    public class TunnelInfo
    {
        /// <summary>
        /// 隧道唯一 ID
        /// </summary>
        [JsonProperty("id")]
        public string Id { get; set; } = "";

        /// <summary>
        /// 隧道名称
        /// </summary>
        [JsonProperty("name")]
        public string Name { get; set; } = "";

        /// <summary>
        /// 隧道状态（active / inactive）
        /// </summary>
        [JsonProperty("status")]
        public string Status { get; set; } = "";

        /// <summary>
        /// 协议（http / https / tcp）
        /// </summary>
        [JsonProperty("protocol")]
        public string Protocol { get; set; } = "";

        /// <summary>
        /// 公网访问地址
        /// </summary>
        [JsonProperty("publicUrl")]
        public string PublicUrl { get; set; } = "";

        /// <summary>
        /// 本地服务地址
        /// </summary>
        [JsonProperty("localAddr")]
        public string LocalAddr { get; set; } = "";

        /// <summary>
        /// 隧道创建时间（格式化后的字符串）
        /// </summary>
        [JsonProperty("createTime")]
        public string CreateTime { get; set; } = "";

        /// <summary>
        /// 复合唯一键：name|protocol，用于同名多协议隧道的独立追踪
        /// </summary>
        [JsonIgnore]
        public string CompositeKey => $"{Name}|{Protocol}";

        /// <summary>
        /// 判断隧道是否在线
        /// </summary>
        [JsonIgnore]
        public bool IsOnline => Status != "inactive" && !string.IsNullOrEmpty(PublicUrl);
    }
}
