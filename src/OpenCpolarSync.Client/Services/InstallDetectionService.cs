using System;
using System.IO;
using Microsoft.Win32;

namespace OpenCpolarSync.Client.Services
{
    /// <summary>
    /// 安装检测服务 — 检测 cpolar 和 openlist 是否已安装/部署
    /// </summary>
    public class InstallDetectionService
    {
        /// <summary>
        /// 检测 cpolar 是否已安装
        /// 检测方式：注册表卸载项 → 默认安装路径 → 进程检测
        /// </summary>
        public static bool IsCpolarInstalled()
        {
            // 方式1：检查注册表卸载项（64位 + 32位）
            try
            {
                var uninstallKeys = new[]
                {
                    @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                    @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
                };

                foreach (var keyPath in uninstallKeys)
                {
                    using (var key = Registry.LocalMachine.OpenSubKey(keyPath))
                    {
                        if (key == null) continue;
                        foreach (var subKeyName in key.GetSubKeyNames())
                        {
                            using (var subKey = key.OpenSubKey(subKeyName))
                            {
                                var displayName = subKey?.GetValue("DisplayName") as string;
                                if (!string.IsNullOrEmpty(displayName) &&
                                    displayName.IndexOf("cpolar", StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    return true;
                                }
                            }
                        }
                    }
                }
            }
            catch { }

            // 方式2：检查默认安装路径（使用 ProgramW6432 环境变量获取真实64位路径）
            try
            {
                var programFiles64 = Environment.GetEnvironmentVariable("ProgramW6432");
                var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
                var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);

                var candidatePaths = new[]
                {
                    Path.Combine(programFiles64 ?? @"C:\Program Files", @"cpolar\cpolar.exe"),
                    Path.Combine(programFiles, @"cpolar\cpolar.exe"),
                    Path.Combine(programFilesX86, @"cpolar\cpolar.exe"),
                    @"C:\Program Files\cpolar\cpolar.exe",
                    @"C:\Program Files (x86)\cpolar\cpolar.exe"
                };

                foreach (var path in candidatePaths)
                {
                    if (!string.IsNullOrEmpty(path) && File.Exists(path)) return true;
                }
            }
            catch { }

            // 方式3：检查 cpolar 进程是否在运行（最可靠的运行时检测）
            try
            {
                var processes = System.Diagnostics.Process.GetProcessesByName("cpolar");
                if (processes.Length > 0) return true;

                // 模糊匹配进程名
                foreach (var p in System.Diagnostics.Process.GetProcesses())
                {
                    try
                    {
                        if (p.ProcessName.IndexOf("cpolar", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            return true;
                        }
                    }
                    catch { }
                }
            }
            catch { }

            return false;
        }

        /// <summary>
        /// 检测 openlist 是否已部署
        /// </summary>
        /// <param name="exePath">openlist.exe 预期路径</param>
        public static bool IsOpenlistDeployed(string exePath)
        {
            return File.Exists(exePath);
        }

        /// <summary>
        /// 获取 cpolar 安装路径（未安装返回 null）
        /// </summary>
        public static string GetCpolarInstallPath()
        {
            try
            {
                var programFiles64 = Environment.GetEnvironmentVariable("ProgramW6432");
                var candidatePaths = new[]
                {
                    Path.Combine(programFiles64 ?? @"C:\Program Files", "cpolar"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "cpolar"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "cpolar"),
                    @"C:\Program Files\cpolar",
                    @"C:\Program Files (x86)\cpolar"
                };

                foreach (var path in candidatePaths)
                {
                    if (!string.IsNullOrEmpty(path) && Directory.Exists(path)) return path;
                }
            }
            catch { }

            return null;
        }

        /// <summary>
        /// 检测 WebView2 Runtime 是否已安装（Win7 需要单独安装）
        /// </summary>
        public static bool IsWebView2Installed()
        {
            try
            {
                // 检查注册表
                using (var key = Registry.LocalMachine.OpenSubKey(
                    @"SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"))
                {
                    if (key != null)
                    {
                        var pv = key.GetValue("pv") as string;
                        if (!string.IsNullOrEmpty(pv)) return true;
                    }
                }

                using (var key = Registry.CurrentUser.OpenSubKey(
                    @"SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"))
                {
                    if (key != null)
                    {
                        var pv = key.GetValue("pv") as string;
                        if (!string.IsNullOrEmpty(pv)) return true;
                    }
                }
            }
            catch { }

            return false;
        }
    }
}
