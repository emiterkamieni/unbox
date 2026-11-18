using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Unbox;

internal static partial class NativeMethods
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public int Size;
        public RECT Monitor;
        public RECT Work;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS { public int Left, Right, Top, Bottom; }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool GetCursorPos(out POINT point);

    public const int SmallIconWidth = 49; // SM_CXSMICON

    [LibraryImport("user32.dll")]
    public static partial int GetSystemMetrics(int index);

    [LibraryImport("user32.dll")]
    public static partial IntPtr MonitorFromPoint(POINT point, uint flags);

    [LibraryImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [LibraryImport("shcore.dll")]
    public static partial int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);

    [LibraryImport("dwmapi.dll")]
    public static partial int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    [LibraryImport("dwmapi.dll")]
    public static partial int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS margins);


    public const int DwmUseImmersiveDarkMode = 20;
    public const int DwmWindowCornerPreference = 33;
    public const int DwmSystemBackdropType = 38;
    public const int CornerRound = 2;
    public const int BackdropTransient = 3; // acrylic, as used by flyouts


    /// <summary>Monitor and work area (pixels) under the cursor, plus its DPI scale.</summary>
    public static (RECT Monitor, RECT Work, double Scale, POINT Cursor) CursorScreen()
    {
        GetCursorPos(out var cursor);
        var monitor = MonitorFromPoint(cursor, 2 /* MONITOR_DEFAULTTONEAREST */);
        var info = new MONITORINFO { Size = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(monitor, ref info);
        double scale = GetDpiForMonitor(monitor, 0, out uint dpi, out _) == 0 ? dpi / 96.0 : 1.0;
        return (info.Monitor, info.Work, scale, cursor);
    }

    public static bool TaskbarUsesLightTheme =>
        Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
            ?.GetValue("SystemUsesLightTheme") is int value && value == 1;

    public static bool AppsUseLightTheme =>
        Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
            ?.GetValue("AppsUseLightTheme") is not int value || value == 1;

    /// <summary>System backdrops (Mica/Acrylic) need Windows 11 22H2.</summary>
    public static bool SupportsBackdrop => Environment.OSVersion.Version.Build >= 22621;
}
