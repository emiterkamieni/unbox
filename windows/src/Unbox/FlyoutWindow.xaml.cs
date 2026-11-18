using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Unbox;

/// <summary>The panel above the notification area, like the Windows 11 quick settings flyouts.</summary>
public partial class FlyoutWindow : Window
{
    private const double Margin_ = 12;
    private const double ListMaxHeight = 520;
    private readonly AppModel model;
    private DateTime hiddenAt;
    private double? anchoredBottom;

    public FlyoutWindow(AppModel model)
    {
        this.model = model;
        DataContext = model;
        InitializeComponent();
        Deactivated += (_, _) => { if (!StaysOpen) HideFlyout(); };
        SizeChanged += (_, _) => KeepAnchored();
        SourceInitialized += (_, _) => ApplyWindowStyle();
        PreviewKeyDown += (_, args) => { if (args.Key == Key.Escape) HideFlyout(); };
    }

    /// <summary>Snapshots: keep the flyout visible even when another window takes the focus.</summary>
    public bool StaysOpen { get; set; }

    public void Toggle()
    {
        if (IsVisible) { HideFlyout(); return; }
        // Clicking the tray icon first deactivates (and hides) the flyout; don't reopen it at once.
        if (DateTime.Now - hiddenAt < TimeSpan.FromMilliseconds(400)) return;
        ShowFlyout(false);
    }

    /// <param name="nearCursor">From the tray icon: open where it was clicked; otherwise in the tray corner.</param>
    public void ShowFlyout(bool settings, bool nearCursor = true)
    {
        model.ShowingSettings = settings;
        model.Refresh();
        Opacity = 0;
        Show();
        UpdateLayout();
        FitListToScreen();
        PlaceNearTray(nearCursor);
        Opacity = 1;
        Activate();
        Focus();
    }

    private void HideFlyout()
    {
        if (!IsVisible) return;
        hiddenAt = DateTime.Now;
        Hide();
        model.PopoverClosed();
    }

    /// <summary>The list gets as much height as the screen allows, up to ListMaxHeight.</summary>
    private void FitListToScreen()
    {
        var (_, work, scale, _) = NativeMethods.CursorScreen();
        double available = (work.Bottom - work.Top) / scale - 2 * Margin_;
        double chrome = ActualHeight - ListScroller.ActualHeight;
        ListScroller.MaxHeight = Math.Clamp(available - chrome, 160, ListMaxHeight);
        UpdateLayout();
    }

    /// <summary>Above the taskbar at the click position, like other notification area flyouts.</summary>
    private void PlaceNearTray(bool nearCursor)
    {
        var (monitor, work, scale, cursor) = NativeMethods.CursorScreen();
        double toDip(int pixels) => pixels / scale;
        double left = toDip(work.Left), top = toDip(work.Top), right = toDip(work.Right), bottom = toDip(work.Bottom);
        // The notification area is at the far end of the taskbar.
        double x = nearCursor ? toDip(cursor.X) : right, y = nearCursor ? toDip(cursor.Y) : bottom;
        double width = ActualWidth, height = ActualHeight;

        if (work.Top > monitor.Top) // taskbar on top
        {
            Left = Math.Clamp(x - width / 2, left + Margin_, right - width - Margin_);
            Top = top + Margin_;
            anchoredBottom = null;
        }
        else if (work.Left > monitor.Left || work.Right < monitor.Right) // taskbar on the left or right
        {
            Left = work.Left > monitor.Left ? left + Margin_ : right - width - Margin_;
            Top = Math.Clamp(y - height / 2, top + Margin_, bottom - height - Margin_);
            anchoredBottom = null;
        }
        else // taskbar at the bottom (the default)
        {
            Left = Math.Clamp(x - width / 2, left + Margin_, right - width - Margin_);
            anchoredBottom = bottom - Margin_;
            Top = anchoredBottom.Value - height;
        }
    }

    /// <summary>Grows upwards when the content changes (e.g. switching to settings).</summary>
    private void KeepAnchored()
    {
        if (anchoredBottom is double edge && IsVisible) Top = edge - ActualHeight;
    }

    /// <summary>Rounded corners and a dark/light frame that match Windows 11.</summary>
    private void ApplyWindowStyle()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        int corner = NativeMethods.CornerRound;
        NativeMethods.DwmSetWindowAttribute(hwnd, NativeMethods.DwmWindowCornerPreference, ref corner, sizeof(int));
        int dark = NativeMethods.AppsUseLightTheme ? 0 : 1;
        NativeMethods.DwmSetWindowAttribute(hwnd, NativeMethods.DwmUseImmersiveDarkMode, ref dark, sizeof(int));
    }

    private void OnSortClick(object sender, RoutedEventArgs e)
    {
        var button = (Button)sender;
        MenuItem Option(string title, bool bySize)
        {
            var item = new MenuItem { Header = title, IsCheckable = true, IsChecked = model.SortBySize == bySize };
            item.Click += (_, _) => model.SortBySize = bySize;
            return item;
        }
        var menu = new ContextMenu
        {
            PlacementTarget = button,
            Placement = PlacementMode.Bottom,
            Items = { Option(model.SortNameTitle, false), Option(model.SortSizeTitle, true) },
        };
        menu.IsOpen = true;
    }

    /// <summary>Clicking anywhere on a row toggles it, except on its checkbox and buttons.</summary>
    private void OnRowClick(object sender, MouseButtonEventArgs e)
    {
        for (var element = e.OriginalSource as DependencyObject; element != null && element != sender; element = VisualTreeHelper.GetParent(element))
        {
            if (element is ButtonBase) return;
        }
        if (sender is FrameworkElement { DataContext: ItemViewModel item } && model.CanChangeOfflineState && !model.IsApplying)
            item.KeepOffline = !item.KeepOffline;
    }
}
