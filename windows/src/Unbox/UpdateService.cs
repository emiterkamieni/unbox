using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using Unbox.Kit;
using Velopack;
using Velopack.Sources;

namespace Unbox;

public enum UpdateState { Idle, Checking, UpToDate, Available, Downloading, Failed, NotInstalled }

/// <summary>
/// Updates through Velopack and GitHub Releases. A silent check runs every 24 hours when
/// “Notify about new versions” is on; installing downloads the package (deltas when possible)
/// and restarts the app. Velopack installs per user, without administrator rights.
/// </summary>
public sealed partial class UpdateService : ObservableObject
{
    public const string Repository = "https://github.com/emiterkamieni/unbox";
    public static readonly TimeSpan CheckInterval = TimeSpan.FromHours(24);

    private readonly Settings settings;
    private readonly UpdateManager manager;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMinutes(30) };
    private UpdateInfo? pending;

    [ObservableProperty] private UpdateState state;
    [ObservableProperty] private string? availableVersion;
    [ObservableProperty] private int progress;

    /// <summary>Raised when a background check finds a version the user was not told about yet.</summary>
    public event Action<string>? UpdateFound;

    public UpdateService(Settings settings)
    {
        this.settings = settings;
        // UNBOX_UPDATE_SOURCE (a folder or URL with Velopack releases) is used for local testing.
        var source = Environment.GetEnvironmentVariable("UNBOX_UPDATE_SOURCE");
        manager = string.IsNullOrEmpty(source)
            ? new UpdateManager(new GithubSource(Repository, null, false))
            : new UpdateManager(source);
        state = manager.IsInstalled || Demo.IsEnabled ? UpdateState.Idle : UpdateState.NotInstalled;
        timer.Tick += (_, _) => CheckIfDue();
        if (!Demo.IsEnabled) Log.Write($"updates: source={(string.IsNullOrEmpty(source) ? Repository : source)} installed={manager.IsInstalled} version={CurrentVersion}");
    }

    public string CurrentVersion => manager.CurrentVersion?.ToString()
        ?? typeof(UpdateService).Assembly.GetName().Version?.ToString(3) ?? "?";

    public bool IsBusy => State is UpdateState.Checking or UpdateState.Downloading;

    public void Start()
    {
        if (Demo.IsEnabled) return;
        timer.Start();
        CheckIfDue();
    }

    public void CheckIfDue()
    {
        if (!settings.NotifyAboutUpdates || !manager.IsInstalled || IsBusy) return;
        var last = settings.LastUpdateCheck ?? DateTime.MinValue;
        if (DateTime.UtcNow - last < CheckInterval && last <= DateTime.UtcNow) return;
        _ = CheckAsync(userInitiated: false);
    }

    public async Task CheckAsync(bool userInitiated)
    {
        if (Demo.IsEnabled) { State = UpdateState.UpToDate; return; }
        if (!manager.IsInstalled) { State = UpdateState.NotInstalled; return; }
        if (IsBusy) return;
        var previous = State;
        State = UpdateState.Checking;
        settings.LastUpdateCheck = DateTime.UtcNow;
        settings.Save();
        try
        {
            pending = await manager.CheckForUpdatesAsync();
            Log.Write($"updates: check ({(userInitiated ? "manual" : "scheduled")}) found {pending?.TargetFullRelease.Version.ToString() ?? "nothing"}");
            if (pending == null)
            {
                AvailableVersion = null;
                State = UpdateState.UpToDate;
                return;
            }
            var version = pending.TargetFullRelease.Version.ToString();
            AvailableVersion = version;
            State = UpdateState.Available;
            if (!userInitiated && settings.NotifyAboutUpdates && settings.NotifiedVersion != version)
            {
                settings.NotifiedVersion = version;
                settings.Save();
                UpdateFound?.Invoke(version);
            }
        }
        catch (Exception error)
        {
            Log.Write($"updates: check failed: {error.GetType().Name}: {error.Message}");
            // A failed background check stays quiet; the user sees errors of checks they started.
            State = userInitiated ? UpdateState.Failed : previous == UpdateState.Available ? previous : UpdateState.Idle;
        }
    }

    /// <summary>Downloads the update and restarts unbox into the new version.</summary>
    public async Task InstallAsync()
    {
        if (IsBusy) return;
        if (pending == null)
        {
            await CheckAsync(userInitiated: true);
            if (pending == null) return;
        }
        State = UpdateState.Downloading;
        Progress = 0;
        try
        {
            await manager.DownloadUpdatesAsync(pending, value => System.Windows.Application.Current.Dispatcher.Invoke(() => Progress = value));
            Log.Write($"updates: installing {pending.TargetFullRelease.Version}");
            manager.ApplyUpdatesAndRestart(pending.TargetFullRelease, [LoginItem.BackgroundArgument]);
        }
        catch (Exception error)
        {
            Log.Write($"updates: install failed: {error.GetType().Name}: {error.Message}");
            State = UpdateState.Failed;
        }
    }

    partial void OnStateChanged(UpdateState value)
    {
        OnPropertyChanged(nameof(IsBusy));
        OnPropertyChanged(nameof(StatusText));
    }

    public string StatusText => State switch
    {
        UpdateState.Checking => L10n.Text("Checking for updates…", "Sprawdzanie aktualizacji…"),
        UpdateState.UpToDate => L10n.Text("unbox is up to date.", "Masz najnowszą wersję unbox."),
        UpdateState.Available => L10n.Format("unbox %@ is available.", "Dostępna jest wersja unbox %@.", AvailableVersion ?? ""),
        UpdateState.Downloading => L10n.Text("Downloading update…", "Pobieranie aktualizacji…"),
        UpdateState.Failed => L10n.Text("Could not check for updates. Check your internet connection.",
                                        "Nie udało się sprawdzić aktualizacji. Sprawdź połączenie z internetem."),
        UpdateState.NotInstalled => L10n.Text("Updates are available in the installed app only.",
                                              "Aktualizacje działają tylko w zainstalowanej aplikacji."),
        _ => "",
    };

    partial void OnAvailableVersionChanged(string? value) => OnPropertyChanged(nameof(StatusText));

    /// <summary>Re-reads the localized texts after a language change.</summary>
    public void RefreshTexts() => OnPropertyChanged(string.Empty);
}
