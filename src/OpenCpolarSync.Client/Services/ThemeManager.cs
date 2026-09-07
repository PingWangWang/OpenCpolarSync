using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace OpenCpolarSync.Client.Services
{
    /// <summary>
    /// 主题管理器 — 在浅色/深色画笔值间切换并写入 Application.Resources，界面通过 DynamicResource 自动刷新
    /// </summary>
    public static class ThemeManager
    {
        private static readonly Dictionary<string, string> Light = new Dictionary<string, string>
        {
            { "BrandBrush", "#4F46E5" }, { "BrandHoverBrush", "#4338CA" },
            { "BrandLightBrush", "#EEF2FF" }, { "BrandBorderBrush", "#C7D2FE" },
            { "BgPrimary", "#FFFFFF" }, { "BgSecondary", "#F9FAFB" },
            { "BgTertiary", "#F3F4F6" }, { "BgSidebar", "#FAFAFA" },
            { "TextPrimary", "#111827" }, { "TextSecondary", "#6B7280" },
            { "TextTertiary", "#9CA3AF" }, { "BorderBrush", "#E5E7EB" },
            { "BorderLightBrush", "#F3F4F6" }, { "SuccessBrush", "#10B981" },
            { "SuccessBgBrush", "#ECFDF5" }, { "WarningBrush", "#F59E0B" },
            { "WarningBgBrush", "#FFFBEB" }, { "ErrorBrush", "#EF4444" },
            { "ErrorBgBrush", "#FEF2F2" }, { "InfoBrush", "#3B82F6" },
            { "InfoBgBrush", "#EFF6FF" }
        };

        private static readonly Dictionary<string, string> Dark = new Dictionary<string, string>
        {
            { "BrandBrush", "#818CF8" }, { "BrandHoverBrush", "#6366F1" },
            { "BrandLightBrush", "#312E81" }, { "BrandBorderBrush", "#4F46E5" },
            { "BgPrimary", "#0F172A" }, { "BgSecondary", "#1E293B" },
            { "BgTertiary", "#334155" }, { "BgSidebar", "#0B1220" },
            { "TextPrimary", "#F8FAFC" }, { "TextSecondary", "#CBD5E1" },
            { "TextTertiary", "#94A3B8" }, { "BorderBrush", "#334155" },
            { "BorderLightBrush", "#1E293B" }, { "SuccessBrush", "#34D399" },
            { "SuccessBgBrush", "#064E3B" }, { "WarningBrush", "#FBBF24" },
            { "WarningBgBrush", "#78350F" }, { "ErrorBrush", "#F87171" },
            { "ErrorBgBrush", "#7F1D1D" }, { "InfoBrush", "#60A5FA" },
            { "InfoBgBrush", "#1E3A8A" }
        };

        /// <summary>
        /// 应用指定主题
        /// 参数:
        ///     theme: 主题名，Light 或 Dark
        /// </summary>
        public static void Apply(string theme)
        {
            var map = string.Equals(theme, "Dark", System.StringComparison.OrdinalIgnoreCase) ? Dark : Light;
            foreach (var kv in map)
            {
                var color = (Color)ColorConverter.ConvertFromString(kv.Value);
                Application.Current.Resources[kv.Key] = new SolidColorBrush(color);
            }
        }
    }
}
