using System.Windows;
using System.Windows.Threading;

namespace Unbox;

public partial class App : Application
{
    private TrayIcon? tray;
    private FlyoutWindow? flyout;
    private AppModel? model;
    private readonly DispatcherTimer refreshTimer = new();
    private EventWaitHandle? showSignal;

    /// <summary>Started by the login item: stay in the notification area without opening the flyout.</summary>
    public bool StartedAtLogin { get; init; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var settings = Settings.Load();
        var updates = new UpdateService(settings);
        model = new AppModel(settings, updates);
        flyout = new FlyoutWindow(model);
        tray = new TrayIcon(model, flyout.Toggle, settings => flyout.ShowFlyout(settings));

        refreshTimer.Interval = TimeSpan.FromMinutes(Math.Max(1, model.RefreshMinutes));
        refreshTimer.Tick += (_, _) => model.Refresh();
        refreshTimer.Start();
        model.RefreshIntervalChanged += () => refreshTimer.Interval = TimeSpan.FromMinutes(Math.Max(1, model.RefreshMinutes));

        // A second launch (Start menu, installer) asks this instance to show itself.
        showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, Program.ShowEvent);
        ThreadPool.RegisterWaitForSingleObject(showSignal, (_, _) => Dispatcher.Invoke(() => flyout.ShowFlyout(false, nearCursor: false)), null, -1, false);

        LoginItem.Refresh();
        model.Refresh(force: true);
        updates.Start();

        // New notification area icons start hidden in the overflow; show the flyout once so it is found.
        if (!StartedAtLogin) Dispatcher.BeginInvoke(() => flyout.ShowFlyout(false, nearCursor: false), DispatcherPriority.ApplicationIdle);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        tray?.Dispose();
        showSignal?.Dispose();
        base.OnExit(e);
    }
}
