using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace OpenCpolarSync.Client.Services
{
    /// <summary>
    /// 主题管理器 — 在浅色/深色/自动模式间切换，支持跟随系统强调色
    /// 参考 Ghost-Downloader-3 的 _setTheme / refreshThemeColor 实现
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

        private static bool _systemThemeListenerRegistered;

        /// <summary>
        /// 当前是否为深色主题（含 Auto 模式下的系统判断）
        /// </summary>
        public static bool IsDark(string theme)
        {
            if (string.Equals(theme, "Dark", StringComparison.OrdinalIgnoreCase)) return true;
            if (string.Equals(theme, "Auto", StringComparison.OrdinalIgnoreCase))
            {
                return IsSystemDarkTheme();
            }
            return false;
        }

        /// <summary>
        /// 应用指定主题（Light / Dark / Auto）
        /// </summary>
        public static void Apply(string theme)
        {
            var isDark = IsDark(theme);
            var map = isDark ? Dark : Light;

            foreach (var kv in map)
            {
                var color = (Color)ColorConverter.ConvertFromString(kv.Value);
                Application.Current.Resources[kv.Key] = new SolidColorBrush(color);
            }

            // 尝试跟随系统强调色
            ApplySystemAccentColor(isDark);

            // 注册系统主题变化监听（仅一次）
            RegisterSystemThemeListener();
        }

        /// <summary>
        /// 检测系统是否为深色主题
        /// 读取注册表 HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme
        /// </summary>
        public static bool IsSystemDarkTheme()
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", false))
                {
                    var value = key?.GetValue("AppsUseLightTheme");
                    if (value is int intValue)
                    {
                        return intValue == 0; // 0=深色, 1=浅色
                    }
                }
            }
            catch { }
            return false; // 默认浅色
        }

        /// <summary>
        /// 读取系统强调色并应用到 BrandBrush
        /// 读取注册表 HKCU\Software\Microsoft\Windows\DWM\ColorizationColor
        /// </summary>
        private static void ApplySystemAccentColor(bool isDark)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\DWM", false))
                {
                    var value = key?.GetValue("ColorizationColor");
                    if (value is int colorValue)
                    {
                        // ColorizationColor 格式：0xAABBGGRR
                        byte a = (byte)((colorValue >> 24) & 0xFF);
                        byte b = (byte)((colorValue >> 16) & 0xFF);
                        byte g = (byte)((colorValue >> 8) & 0xFF);
                        byte r = (byte)(colorValue & 0xFF);

                        var accent = Color.FromRgb(r, g, b);
                        Application.Current.Resources["BrandBrush"] = new SolidColorBrush(accent);

                        // 派生 hover 色（加深）
                        var hover = Color.FromRgb(
                            (byte)Math.Max(0, r - 30),
                            (byte)Math.Max(0, g - 30),
                            (byte)Math.Max(0, b - 30));
                        Application.Current.Resources["BrandHoverBrush"] = new SolidColorBrush(hover);

                        // 派生浅色背景
                        byte lightAlpha = isDark ? (byte)60 : (byte)30;
                        var lightBg = Color.FromArgb(lightAlpha, r, g, b);
                        Application.Current.Resources["BrandLightBrush"] = new SolidColorBrush(lightBg);
                    }
                }
            }
            catch
            {
                // 读取失败保持默认品牌色
            }
        }

        /// <summary>
        /// 注册系统主题变化监听（UserPreferenceChanged）
        /// </summary>
        private static void RegisterSystemThemeListener()
        {
            if (_systemThemeListenerRegistered) return;
            _systemThemeListenerRegistered = true;

            try
            {
                SystemEvents.UserPreferenceChanged += (s, e) =>
                {
                    if (e.Category == UserPreferenceCategory.General ||
                        e.Category == UserPreferenceCategory.Color)
                    {
                        // 通知外部重新应用主题（通过事件）
                        SystemThemeChanged?.Invoke(null, EventArgs.Empty);
                    }
                };
            }
            catch { }
        }

        /// <summary>
        /// 系统主题变化事件（Auto 模式下外部监听此事件重新 Apply）
        /// </summary>
        public static event EventHandler SystemThemeChanged;
    }
}
