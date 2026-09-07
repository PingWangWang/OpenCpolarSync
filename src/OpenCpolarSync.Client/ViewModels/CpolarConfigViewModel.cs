using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using OpenCpolarSync.Client.Models;

namespace OpenCpolarSync.Client.ViewModels
{
    /// <summary>
    /// Cpolar 配置视图模型 — 绑定配置表单，支持加载/保存/校验
    /// </summary>
    public class CpolarConfigViewModel : INotifyPropertyChanged
    {
        private string _webhookUrl = "";
        private int _interval = 1;
        private string _selectedTunnelNames = "";
        private string _cpolarApiBase = "http://localhost:9200";
        private string _username = "";
        private string _password = "";
        private string _keyword = "Cpolar";
        private bool _debug;
        private string _openlistPassword = "";
        private List<string> _validationErrors = new List<string>();

        public string WebhookUrl
        {
            get => _webhookUrl;
            set { _webhookUrl = value; OnPropertyChanged(); }
        }

        public int Interval
        {
            get => _interval;
            set { _interval = value; OnPropertyChanged(); }
        }

        public string SelectedTunnelNamesText
        {
            get => _selectedTunnelNames;
            set { _selectedTunnelNames = value; OnPropertyChanged(); }
        }

        public string CpolarApiBase
        {
            get => _cpolarApiBase;
            set { _cpolarApiBase = value; OnPropertyChanged(); }
        }

        public string Username
        {
            get => _username;
            set { _username = value; OnPropertyChanged(); }
        }

        public string Password
        {
            get => _password;
            set { _password = value; OnPropertyChanged(); }
        }

        public string Keyword
        {
            get => _keyword;
            set { _keyword = value; OnPropertyChanged(); }
        }

        public bool Debug
        {
            get => _debug;
            set { _debug = value; OnPropertyChanged(); }
        }

        public string OpenlistPassword
        {
            get => _openlistPassword;
            set { _openlistPassword = value; OnPropertyChanged(); }
        }

        public List<string> ValidationErrors
        {
            get => _validationErrors;
            set { _validationErrors = value; OnPropertyChanged(); OnPropertyChanged(nameof(HasErrors)); }
        }

        public bool HasErrors => _validationErrors != null && _validationErrors.Count > 0;

        /// <summary>
        /// 从配置模型加载
        /// </summary>
        public void LoadFromConfig(CpolarConfig config)
        {
            WebhookUrl = config.WebhookUrl;
            Interval = config.Interval;
            SelectedTunnelNamesText = config.SelectedTunnelNames != null
                ? string.Join(", ", config.SelectedTunnelNames)
                : "";
            CpolarApiBase = config.CpolarApiBase;
            Username = config.Username;
            Password = config.Password;
            Keyword = config.Keyword;
            Debug = config.Debug;
            OpenlistPassword = config.OpenlistPassword;
        }

        /// <summary>
        /// 转换为配置模型
        /// </summary>
        public CpolarConfig ToConfig()
        {
            var names = new List<string>();
            if (!string.IsNullOrWhiteSpace(SelectedTunnelNamesText))
            {
                foreach (var name in SelectedTunnelNamesText.Split(','))
                {
                    var trimmed = name.Trim();
                    if (!string.IsNullOrEmpty(trimmed)) names.Add(trimmed);
                }
            }

            return new CpolarConfig
            {
                WebhookUrl = WebhookUrl,
                Interval = Interval,
                SelectedTunnelNames = names,
                CpolarApiBase = CpolarApiBase,
                Username = Username,
                Password = Password,
                Keyword = Keyword,
                Debug = Debug,
                OpenlistPassword = OpenlistPassword
            };
        }

        public event PropertyChangedEventHandler PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
