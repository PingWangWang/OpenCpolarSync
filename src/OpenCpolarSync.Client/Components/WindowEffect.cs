using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace OpenCpolarSync.Client.Components
{
    /// <summary>
    /// 窗口背景效果枚举 — 对齐 Ghost-Downloader-3 的背景效果选项
    /// </summary>
    public enum BackgroundEffect
    {
        /// <summary>无效果，纯色背景</summary>
        None = 0,
        /// <summary>亚克力模糊（Win10+）</summary>
        Acrylic = 1,
        /// <summary>云母效果（Win11 22H2+）</summary>
        Mica = 2,
        /// <summary>云母变体（Win11 22H2+）</summary>
        MicaAlt = 3
    }

    /// <summary>
    /// 窗口效果工具 — 通过 P/Invoke 调用 DWM 和 用户32 API 实现 Mica/Acrylic 背景效果
    /// 参考 Ghost-Downloader-3 的 _setBackgroundEffectWin 实现
    /// </summary>
    public static class WindowEffect
    {
        #region DWM API

        // DwmSetWindowAttribute 属性常量
        private const int DWMWA_SYSTEMBACKDROP_TYPE = 38;  // Win11 22H2+
        private const int DWMWA_MICA_EFFECT = 1029;       // Win11 早期版本（已弃用但兼容）

        // 系统背景类型
        private const int DWMSBT_AUTO = 0;
        private const int DWMSBT_NONE = 1;
        private const int DWMSBT_MAINWINDOW = 2;      // Mica
        private const int DWMSBT_TRANSIENTWINDOW = 3; // Acrylic
        private const int DWMSBT_TABBEDWINDOW = 4;    // MicaAlt

        [DllImport("dwmapi.dll", PreserveSig = false)]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("dwmapi.dll", PreserveSig = false)]
        private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

        #endregion

        #region SetWindowCompositionAttribute (Acrylic)

        [StructLayout(LayoutKind.Sequential)]
        private struct AccentPolicy
        {
            public int AccentState;
            public int AccentFlags;
            public int GradientColor;
            public int AnimationId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WindowCompositionAttributeData
        {
            public int Attribute;
            public IntPtr Data;
            public int SizeOfData;
        }

        private const int WCA_ACCENT_POLICY = 19;
        private const int ACCENT_ENABLE_BLURBEHIND = 3;
        private const int ACCENT_ENABLE_ACRYLICBLURBEHIND = 4;

        [DllImport("user32.dll")]
        private static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

        #endregion

        #region 系统版本检测

        /// <summary>
        /// 是否为 Windows 10 及以上
        /// </summary>
        public static bool IsWindows10OrGreater()
        {
            try
            {
                var os = Environment.OSVersion;
                if (os.Version.Major > 10) return true;
                if (os.Version.Major == 10 && os.Version.Build >= 10240) return true;
                return false;
            }
            catch { return false; }
        }

        /// <summary>
        /// 是否为 Windows 11 22H2 及以上（支持 Mica via DWMWA_SYSTEMBACKDROP_TYPE）
        /// Win11 22H2 内部版本号 22621
        /// </summary>
        public static bool IsWindows11_22H2OrGreater()
        {
            try
            {
                var os = Environment.OSVersion;
                if (os.Version.Major > 10) return true;
                // Win11 仍报告 Major=10，靠 Build 区分
                if (os.Version.Major == 10 && os.Version.Build >= 22621) return true;
                return false;
            }
            catch { return false; }
        }

        #endregion

        #region 公开方法

        /// <summary>
        /// 为窗口设置背景效果
        /// </summary>
        /// <param name="window">目标窗口</param>
        /// <param name="effect">背景效果类型</param>
        /// <param name="isDark">是否深色模式（影响 Acrylic 色调）</param>
        /// <returns>true=设置成功，false=系统不支持或设置失败</returns>
        public static bool SetBackgroundEffect(Window window, BackgroundEffect effect, bool isDark)
        {
            if (window == null) return false;
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero) return false;

            try
            {
                switch (effect)
                {
                    case BackgroundEffect.None:
                        return RemoveEffects(hwnd);

                    case BackgroundEffect.Mica:
                        return SetMica(hwnd, false);

                    case BackgroundEffect.MicaAlt:
                        return SetMica(hwnd, true);

                    case BackgroundEffect.Acrylic:
                        return SetAcrylic(hwnd, isDark);

                    default:
                        return false;
                }
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// 移除所有背景效果，恢复纯色
        /// </summary>
        private static bool RemoveEffects(IntPtr hwnd)
        {
            try
            {
                // 移除 DWM 背景
                if (IsWindows11_22H2OrGreater())
                {
                    int none = DWMSBT_NONE;
                    DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, ref none, sizeof(int));
                }
                // 移除 Acrylic
                var accent = new AccentPolicy { AccentState = 0 };
                var data = new WindowCompositionAttributeData
                {
                    Attribute = WCA_ACCENT_POLICY,
                    Data = Marshal.AllocHGlobal(Marshal.SizeOf(accent)),
                    SizeOfData = Marshal.SizeOf(accent)
                };
                Marshal.StructureToPtr(accent, data.Data, false);
                SetWindowCompositionAttribute(hwnd, ref data);
                Marshal.FreeHGlobal(data.Data);
                return true;
            }
            catch { return false; }
        }

        /// <summary>
        /// 设置 Mica / MicaAlt 效果
        /// </summary>
        private static bool SetMica(IntPtr hwnd, bool isAlt)
        {
            // Win11 22H2+ 使用 DWMWA_SYSTEMBACKDROP_TYPE
            if (IsWindows11_22H2OrGreater())
            {
                try
                {
                    int backdropType = isAlt ? DWMSBT_TABBEDWINDOW : DWMSBT_MAINWINDOW;
                    DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, ref backdropType, sizeof(int));
                    return true;
                }
                catch { }
            }

            // 回退：旧版 Mica 属性（Win11 早期）
            try
            {
                int enable = 1;
                DwmSetWindowAttribute(hwnd, DWMWA_MICA_EFFECT, ref enable, sizeof(int));
                return true;
            }
            catch { return false; }
        }

        /// <summary>
        /// 设置 Acrylic 模糊效果
        /// </summary>
        private static bool SetAcrylic(IntPtr hwnd, bool isDark)
        {
            if (!IsWindows10OrGreater()) return false;

            try
            {
                // 色调：深色用半透明黑，浅色用半透明白
                // 格式：0xAABBGGRR
                int gradientColor = isDark ? unchecked((int)0x99000000) : unchecked((int)0x99FFFFFF);

                var accent = new AccentPolicy
                {
                    AccentState = ACCENT_ENABLE_ACRYLICBLURBEHIND,
                    AccentFlags = 2, // 显示渐变颜色
                    GradientColor = gradientColor
                };

                var data = new WindowCompositionAttributeData
                {
                    Attribute = WCA_ACCENT_POLICY,
                    Data = Marshal.AllocHGlobal(Marshal.SizeOf(accent)),
                    SizeOfData = Marshal.SizeOf(accent)
                };
                Marshal.StructureToPtr(accent, data.Data, false);
                SetWindowCompositionAttribute(hwnd, ref data);
                Marshal.FreeHGlobal(data.Data);
                return true;
            }
            catch { return false; }
        }

        #endregion
    }
}
