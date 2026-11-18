using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Unbox.Kit;

namespace Unbox;

/// <summary>
/// Invented folders and files for screenshots and for trying the interface without Box Drive:
///   unbox.exe --demo [--theme light|dark] [--language en] [--snapshot &lt;folder&gt;]
/// Demo mode never reads or changes anything in Box, keeps its settings in memory, leaves the
/// login item alone and does not check for updates. With --snapshot the flyout is saved at 2x as
/// windows-list.png and windows-settings.png (with a -dark suffix in dark mode) and the app quits.
/// </summary>
public static class Demo
{
    private static readonly string[] Arguments = Environment.GetCommandLineArgs();

    public static bool IsEnabled { get; } = Arguments.Contains("--demo");
    public static string? SnapshotFolder { get; } = After("--snapshot");
    public static string? Theme { get; } = After("--theme");
    public static bool LaunchAtLogin { get; set; } = true;

    private sealed record Entry(string Path, bool IsFolder, double Size, int Power, bool OnlineOnly);

    // Sizes in File Explorer's binary units (power 1 = KB, 2 = MB, 3 = GB), so they read the same as in the list.
    private static readonly Entry[] Entries =
    [
        new(@"\Acme Corp\Marketing\Brand Guidelines", true, 1.24, 3, false),
        new(@"\Acme Corp\Marketing\Campaigns\Spring Campaign 2026", true, 6.8, 3, true),
        new(@"\Acme Corp\Legal\Master Services Agreement.pdf", false, 2.1, 2, false),
        new(@"\Northwind Studio\Photography\Product Shoot – RAW", true, 14.3, 3, true),
        new(@"\Northwind Studio\Website Redesign", true, 842, 2, false),
        new(@"\Globex\HR\Onboarding Videos", true, 3.6, 3, false),
        new(@"\Invoices 2026.xlsx", false, 186, 1, false),
    ];

    private const string Root = @"C:\Users\Public\Box (demo)";
    private static readonly HashSet<string> Removed = [];

    public static Settings CreateSettings() => new()
    {
        IsTransient = true,
        Language = AppLanguages.FromCode(After("--language")).Code(),
    };

    public static IReadOnlyList<OfflineItem> Items =>
    [
        .. Entries.Where(entry => !Removed.Contains(entry.Path))
                  .Select(entry => new OfflineItem(entry.Path, Path.Combine(Root, entry.Path.TrimStart('\\')), entry.IsFolder)),
    ];

    public static long Size(OfflineItem item)
    {
        var entry = Entries.First(entry => entry.Path == item.Id);
        return (long)(entry.Size * Math.Pow(1024, entry.Power));
    }

    public static bool StartsOnlineOnly(OfflineItem item) => Entries.Any(entry => entry.Path == item.Id && entry.OnlineOnly);

    /// <summary>Pretends to make the item online-only and returns the space it would free.</summary>
    public static async Task<long> MakeOnlineOnlyAsync(OfflineItem item, bool freeSpace, long size)
    {
        await Task.Delay(700);
        Removed.Add(item.Id);
        return freeSpace ? size : 0;
    }

    public static void ApplyTheme(Application app)
    {
        if (Theme == "dark") app.ThemeMode = ThemeMode.Dark;
        else if (Theme == "light") app.ThemeMode = ThemeMode.Light;
    }

    /// <summary>Renders the window at 2x; scripts/screenshots.sh adds the rounded frame and shadow.</summary>
    public static void SaveSnapshot(Window window, string name)
    {
        if (SnapshotFolder == null) return;
        window.UpdateLayout();
        bool dark = Theme == "dark" || (Theme == null && !NativeMethods.AppsUseLightTheme);
        const double scale = 2;
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth * scale), (int)Math.Ceiling(window.ActualHeight * scale),
                                            96 * scale, 96 * scale, PixelFormats.Pbgra32);
        bitmap.Render(window);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        Directory.CreateDirectory(SnapshotFolder);
        using var file = File.Create(Path.Combine(SnapshotFolder, $"windows-{name}{(dark ? "-dark" : "")}.png"));
        encoder.Save(file);
    }

    private static string? After(string flag)
    {
        int index = Array.IndexOf(Arguments, flag);
        return index >= 0 && index + 1 < Arguments.Length ? Arguments[index + 1] : null;
    }
}
