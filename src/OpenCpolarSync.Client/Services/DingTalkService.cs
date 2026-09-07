using System;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace OpenCpolarSync.Client.Services
{
    /// <summary>
    /// 钉钉推送服务 — 通过钉钉机器人 Webhook 发送 Markdown 消息
    /// </summary>
    public class DingTalkService
    {
        private readonly HttpClient _httpClient;

        public DingTalkService()
        {
            _httpClient = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(15)
            };
        }

        /// <summary>
        /// 发送 Markdown 消息到钉钉群机器人
        /// </summary>
        /// <param name="webhookUrl">钉钉机器人 Webhook 地址</param>
        /// <param name="title">消息标题</param>
        /// <param name="markdownText">Markdown 格式正文</param>
        /// <returns>是否发送成功</returns>
        public async Task<bool> SendMarkdownAsync(string webhookUrl, string title, string markdownText)
        {
            if (string.IsNullOrWhiteSpace(webhookUrl))
            {
                System.Diagnostics.Debug.WriteLine("[DingTalk] Webhook 未配置，跳过推送");
                return false;
            }

            try
            {
                var body = new
                {
                    msgtype = "markdown",
                    markdown = new
                    {
                        title = title,
                        text = markdownText
                    }
                };

                var json = JsonConvert.SerializeObject(body);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                var response = await _httpClient.PostAsync(webhookUrl, content);
                var responseBody = await response.Content.ReadAsStringAsync();
                var result = JsonConvert.DeserializeObject<DingTalkResponse>(responseBody);

                if (result != null && result.errcode == 0)
                {
                    return true;
                }

                System.Diagnostics.Debug.WriteLine($"[DingTalk] 推送失败: {result?.errmsg}");
                return false;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DingTalk] 推送异常: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// 钉钉 API 响应模型
        /// </summary>
        private class DingTalkResponse
        {
            public int errcode { get; set; }
            public string errmsg { get; set; }
        }
    }
}
