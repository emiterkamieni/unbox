using Microsoft.Win32;

namespace Unbox;

/// <summary>Launch at login through the per-user Run key (listed in Settings → Apps → Startup).</summary>
public static class LoginItem
{
    public const string BackgroundArgument = "--background";
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "unbox";

    private static string Command => $"\"{Environment.ProcessPath}\" {BackgroundArgument}";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(ValueName) is string;
        }
    }

    public static void Set(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue(ValueName, Command);
        else key.DeleteValue(ValueName, throwOnMissingValue: false);
    }

    /// <summary>Keeps the entry pointing at the current executable (it moves when Velopack updates).</summary>
    public static void Refresh()
    {
        if (IsEnabled) Set(true);
    }

    public static void Remove()
    {
        try { Set(false); } catch (Exception) { }
    }
}
