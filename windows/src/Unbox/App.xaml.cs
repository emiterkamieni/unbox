using System.Windows;
using System.Windows.Media;
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
        Demo.ApplyTheme(this);
        var settings = Demo.IsEnabled ? Demo.CreateSettings() : Settings.Load();
        var updates = new UpdateService(settings);
        model = new AppModel(settings, updates);
        flyout = new FlyoutWindow(model);
        if (Demo.SnapshotFolder != null)
        {
            TakeSnapshots(model, flyout);
            return;
        }
        tray = new TrayIcon(model, flyout.Toggle, settings => flyout.ShowFlyout(settings));

        refreshTimer.Interval = TimeSpan.FromMinutes(Math.Max(1, model.RefreshMinutes));
        refreshTimer.Tick += (_, _) => model.Refresh();
        refreshTimer.Start();
        model.RefreshIntervalChanged += () => refreshTimer.Interval = TimeSpan.FromMinutes(Math.Max(1, model.RefreshMinutes));

        if (!Demo.IsEnabled)
        {
            // A second launch (Start menu, installer) asks this instance to show itself.
            showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, Program.ShowEvent);
            ThreadPool.RegisterWaitForSingleObject(showSignal, (_, _) => Dispatcher.Invoke(() => flyout.ShowFlyout(false, nearCursor: false)), null, -1, false);
            LoginItem.Refresh();
        }

        model.Refresh(force: true);
        updates.Start();

        // New notification area icons start hidden in the overflow; show the flyout once so it is found.
        if (!StartedAtLogin) Dispatcher.BeginInvoke(() => flyout.ShowFlyout(false, nearCursor: false), DispatcherPriority.ApplicationIdle);
    }

    /// <summary>--demo --snapshot: saves the list and the settings, then quits.</summary>
    private void TakeSnapshots(AppModel model, FlyoutWindow flyout)
    {
        flyout.StaysOpen = true;
        TextOptions.SetTextFormattingMode(flyout, TextFormattingMode.Ideal);
        Dispatcher.BeginInvoke(async () =>
        {
            flyout.ShowFlyout(false, nearCursor: false);
            await Task.Delay(1500);
            Demo.SaveSnapshot(flyout, "list");
            model.ShowingSettings = true;
            await Task.Delay(1500);
            Demo.SaveSnapshot(flyout, "settings");
            Shutdown();
        }, DispatcherPriority.ApplicationIdle);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        tray?.Dispose();
        showSignal?.Dispose();
        base.OnExit(e);
    }
}
