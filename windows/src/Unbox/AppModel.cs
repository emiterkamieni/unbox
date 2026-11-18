using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Unbox.Kit;

namespace Unbox;

public sealed partial class AppModel : ObservableObject
{
    private readonly Settings settings;
    private readonly OfflineService? service;
    private List<ItemViewModel> items = [];
    private DateTime? lastRefresh;

    public UpdateService Updates { get; }
    public ObservableCollection<GroupViewModel> Groups { get; } = [];

    [ObservableProperty] private bool isLoading;
    [ObservableProperty] private bool isApplying;
    [ObservableProperty] private string? loadError;
    [ObservableProperty] private bool isBoxRunning = true;
    [ObservableProperty] private bool isOnline = NetworkInterface.GetIsNetworkAvailable();
    [ObservableProperty] private Banner? banner;
    [ObservableProperty] private bool showingSettings;

    public AppModel(Settings settings, UpdateService updates)
    {
        this.settings = settings;
        Updates = updates;
        L10n.Configure(AppLanguages.FromCode(settings.Language));
        try
        {
            service = new OfflineService();
        }
        catch (UnboxException error)
        {
            loadError = error.Message;
        }
        NetworkChange.NetworkAvailabilityChanged += (_, args) =>
            Application.Current.Dispatcher.Invoke(() => IsOnline = args.IsAvailable);
        updates.PropertyChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(ShowsUpdateNotice));
            OnPropertyChanged(nameof(IsDownloadingUpdate));
            OnPropertyChanged(nameof(UpdateButtonText));
        };
    }

    // MARK: Interface texts (re-read after a language change)

    public string SettingsGlyph => ShowingSettings ? "\uE711" : "\uE713";
    public string SettingsTooltip => ShowingSettings ? L10n.Text("Close settings", "Zamknij ustawienia") : L10n.Text("Settings", "Ustawienia");
    public string RefreshTooltip => L10n.Text("Refresh", "Odśwież");
    public string CancelText => L10n.Text("Cancel", "Anuluj");
    public string ApplyText => L10n.Text("Apply", "Zastosuj");
    public string CloseText => L10n.Text("Close", "Zamknij");
    public string OpenBoxText => L10n.Text("Open Box", "Uruchom Box");
    public string BoxNotRunningText => L10n.Text("Box Drive is not running. Open it to change offline settings.",
                                                 "Box Drive nie działa. Uruchom go, aby zmieniać ustawienia offline.");
    public string OfflineWarning => L10n.Text("No internet connection – you won’t be able to open these files until you’re back online.",
                                              "Brak internetu – po zmianie tych plików nie otworzysz do czasu połączenia.");
    public string LaunchAtLoginText => L10n.Text("Launch at login", "Uruchamiaj przy logowaniu");
    public string FreeSpaceText => L10n.Text("Remove downloaded files after unchecking", "Po odznaczeniu usuwaj pobrane pliki z dysku");
    public string RefreshEveryText => L10n.Text("Refresh the list every", "Odświeżaj listę co");
    public string LanguageText => L10n.Text("Language", "Język");
    public string NotifyText => L10n.Text("Notify about new versions", "Powiadamiaj o nowych wersjach");
    public string NotifyCaption => L10n.Text("Checks for updates every 24 hours.", "Sprawdza aktualizacje co 24 godziny.");
    public string VersionText => L10n.Format("Version %@", "Wersja %@", Updates.CurrentVersion);
    public string QuitText => L10n.Text("Quit unbox", "Zakończ unbox");
    public string DoneText => L10n.Text("Done", "Gotowe");
    public string UpdateNoticeButton => L10n.Text("Update…", "Aktualizuj…");
    public string UpdateButtonText => Updates.State == UpdateState.Available
        ? L10n.Text("Update and Restart", "Aktualizuj i uruchom ponownie")
        : L10n.Text("Check for Updates…", "Sprawdź aktualizacje…");

    // MARK: What is visible

    public bool ShowsList => !ShowingSettings;
    public bool ShowsSort => HasItems && !ShowingSettings;
    public bool ShowsUpdateNotice => Updates.State is UpdateState.Available or UpdateState.Downloading;
    public bool IsDownloadingUpdate => Updates.State == UpdateState.Downloading;
    public bool ShowsBoxNotRunning => !IsBoxRunning && service != null;
    public bool HasLoadError => LoadError != null;
    public bool HasBanner => Banner != null;
    public bool ShowsSelectionBar => HasSelection && !IsApplying;
    public bool ShowsHint => !HasSelection && !IsApplying;
    public bool ShowsOfflineWarning => ShowsSelectionBar && !IsOnline;

    partial void OnIsBoxRunningChanged(bool value) => OnPropertyChanged(nameof(ShowsBoxNotRunning));
    partial void OnLoadErrorChanged(string? value) => OnPropertyChanged(nameof(HasLoadError));
    partial void OnBannerChanged(Banner? value) => OnPropertyChanged(nameof(HasBanner));
    partial void OnIsOnlineChanged(bool value) => OnPropertyChanged(nameof(ShowsOfflineWarning));

    partial void OnIsApplyingChanged(bool value)
    {
        OnPropertyChanged(nameof(ShowsSelectionBar));
        OnPropertyChanged(nameof(ShowsHint));
        OnPropertyChanged(nameof(ShowsOfflineWarning));
        OnPropertyChanged(nameof(ApplyingText));
    }

    // MARK: Settings

    public bool FreeSpace
    {
        get => settings.FreeSpace;
        set { settings.FreeSpace = value; settings.Save(); OnPropertyChanged(); OnPropertyChanged(nameof(FreeSpaceCaption)); OnPropertyChanged(nameof(SelectionSizeText)); }
    }

    public int RefreshMinutes
    {
        get => settings.RefreshMinutes;
        set { settings.RefreshMinutes = value; settings.Save(); OnPropertyChanged(); RefreshIntervalChanged?.Invoke(); }
    }

    public bool SortBySize
    {
        get => settings.SortOrder == "size";
        set { settings.SortOrder = value ? "size" : "name"; settings.Save(); OnPropertyChanged(); RebuildGroups(); }
    }

    public AppLanguage Language
    {
        get => AppLanguages.FromCode(settings.Language);
        set
        {
            settings.Language = value.Code();
            settings.Save();
            L10n.Configure(value);
            Updates.RefreshTexts();
            foreach (var item in items) item.RefreshTexts();
            OnPropertyChanged(string.Empty);
            Refresh(force: true);
        }
    }

    public bool LaunchAtLogin
    {
        get => LoginItem.IsEnabled;
        set { LoginItem.Set(value); OnPropertyChanged(); }
    }

    public bool NotifyAboutUpdates
    {
        get => settings.NotifyAboutUpdates;
        set { settings.NotifyAboutUpdates = value; settings.Save(); OnPropertyChanged(); if (value) Updates.CheckIfDue(); }
    }

    public event Action? RefreshIntervalChanged;

    public IReadOnlyList<Choice<int>> RefreshChoices =>
        [.. new[] { 1, 5, 15, 30 }.Select(minutes => new Choice<int>(minutes, L10n.Format("%ld min", "%ld min", minutes)))];

    public IReadOnlyList<Choice<AppLanguage>> LanguageChoices =>
        [.. AppLanguages.All.Select(language => new Choice<AppLanguage>(language, language.NativeName()))];

    // MARK: Derived state

    public bool CanChangeOfflineState => service != null;
    public bool HasItems => items.Count > 0;
    public int ItemCount => items.Count;
    public bool IsEmpty => items.Count == 0;
    public int SelectionCount => items.Count(item => !item.KeepOffline);
    public bool HasSelection => SelectionCount > 0;

    public string HeaderSubtitle
    {
        get
        {
            if (ShowingSettings) return L10n.Text("Settings", "Ustawienia");
            if (items.Count == 0)
                return IsLoading ? L10n.Text("Checking…", "Sprawdzanie…")
                                 : L10n.Text("Nothing is downloaded for offline use", "Nic nie jest pobrane offline");
            var count = Plural.Items(items.Count);
            return Total(items) is long size
                ? L10n.Format("%@ offline · %@ on disk", "%@ offline · %@ na dysku", count, NativeMethods.FormatBytes(size))
                : L10n.Format("%@ offline", "%@ offline", count);
        }
    }

    public string EmptyText => IsLoading
        ? L10n.Text("Checking offline files…", "Sprawdzanie plików offline…")
        : L10n.Text("No folders or files are available offline.", "Żaden folder ani plik nie jest oznaczony offline.");

    public string SelectionText => L10n.Format("Online-only: %@", "Tylko online: %@", Plural.Items(SelectionCount));

    public string SelectionSizeText =>
        FreeSpace && Total(items.Where(item => !item.KeepOffline)) is long size
            ? L10n.Format("Frees about %@", "Zwolni ok. %@", NativeMethods.FormatBytes(size))
            : "";

    public string FooterHint => L10n.Text("Uncheck an item to stop keeping it offline.", "Odznacz element, aby przestał być dostępny offline.");

    public string LastRefreshText => lastRefresh is DateTime time
        ? L10n.Format("Checked %@", "Sprawdzono %@", time.ToString("t", L10n.Culture))
        : "";

    public string ApplyingText => FreeSpace
        ? L10n.Text("Making online-only and freeing space…", "Ustawianie jako tylko online i zwalnianie miejsca…")
        : L10n.Text("Making online-only…", "Ustawianie jako tylko online…");

    public string FreeSpaceCaption => FreeSpace
        ? L10n.Text("Space is freed right away. Files stay visible in File Explorer and download again when opened. Files with unsent changes are kept.",
                    "Miejsce zwalnia się od razu. Pliki zostają widoczne w Eksploratorze plików i pobiorą się przy otwarciu. Pliki z niewysłanymi zmianami nie są usuwane.")
        : L10n.Text("Box stops keeping the files offline, but the downloaded copies stay on disk until Box or Windows removes them.",
                    "Box przestanie trzymać pliki offline, ale pobrane kopie zostaną na dysku, dopóki Box lub Windows ich nie usunie.");

    public string SortTooltip => L10n.Format("Sort by: %@", "Sortuj według: %@", SortBySize ? SortSizeTitle : SortNameTitle);
    public string SortNameTitle => L10n.Text("Name (A–Z)", "Nazwa (A–Z)");
    public string SortSizeTitle => L10n.Text("Size (largest first)", "Rozmiar (największe)");

    private static long? Total(IEnumerable<ItemViewModel> source)
    {
        long sum = 0;
        foreach (var item in source)
        {
            if (item.Size is not long size) return null;
            sum += size;
        }
        return sum;
    }

    internal void SelectionChanged()
    {
        Banner = null;
        foreach (var name in new[] { nameof(SelectionCount), nameof(HasSelection), nameof(SelectionText), nameof(SelectionSizeText),
                                     nameof(ShowsSelectionBar), nameof(ShowsHint), nameof(ShowsOfflineWarning) })
            OnPropertyChanged(name);
    }

    partial void OnIsLoadingChanged(bool value)
    {
        OnPropertyChanged(nameof(HeaderSubtitle));
        OnPropertyChanged(nameof(EmptyText));
    }

    partial void OnShowingSettingsChanged(bool value)
    {
        foreach (var name in new[] { nameof(HeaderSubtitle), nameof(SettingsGlyph), nameof(SettingsTooltip), nameof(ShowsList), nameof(ShowsSort) })
            OnPropertyChanged(name);
    }

    // MARK: Actions

    [RelayCommand]
    private void RefreshNow() => Refresh(force: true);

    public void Refresh(bool force = false)
    {
        IsBoxRunning = OfflineService.IsBoxRunning;
        OnPropertyChanged(nameof(LaunchAtLogin));
        if (service == null || IsLoading || IsApplying) return;
        if (!force && lastRefresh is DateTime last && DateTime.Now - last < TimeSpan.FromSeconds(5)) return;
        _ = RefreshAsync(service);
    }

    private async Task RefreshAsync(OfflineService service)
    {
        IsLoading = true;
        try
        {
            var found = await service.ScanAsync();
            var unchecked_ = items.Where(item => !item.KeepOffline).Select(item => item.Item.Id).ToHashSet();
            var previousSizes = items.ToDictionary(item => item.Item.Id, item => item.Size);
            items = [.. found.Select(item => new ItemViewModel(item, this, keepOffline: !unchecked_.Contains(item.Id))
            {
                Size = previousSizes.GetValueOrDefault(item.Id),
            })];
            LoadError = null;
            lastRefresh = DateTime.Now;
            RebuildGroups();
            NotifyListChanged();

            var sizes = await Task.Run(() => found.ToDictionary(item => item.Id, item => DiskUsage.AllocatedSize(item.FullPath)));
            foreach (var item in items) item.Size = sizes.GetValueOrDefault(item.Item.Id);
            RebuildGroups();
            NotifyListChanged();
        }
        catch (Exception error) when (error is UnboxException or IOException or UnauthorizedAccessException)
        {
            LoadError = error.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    private void NotifyListChanged()
    {
        foreach (var name in new[] { nameof(HasItems), nameof(ItemCount), nameof(IsEmpty), nameof(HeaderSubtitle), nameof(EmptyText), nameof(LastRefreshText),
                                     nameof(SelectionCount), nameof(HasSelection), nameof(SelectionText), nameof(SelectionSizeText),
                                     nameof(ShowsSort), nameof(ShowsSelectionBar), nameof(ShowsHint), nameof(ShowsOfflineWarning) })
            OnPropertyChanged(name);
    }

    /// <summary>Groups and the items inside them: alphabetical, or largest first.</summary>
    private void RebuildGroups()
    {
        bool bySize = SortBySize;
        int Compare(string leftName, long? leftSize, string rightName, long? rightSize)
        {
            if (bySize && leftSize is long a && rightSize is long b && a != b) return b.CompareTo(a);
            return string.Compare(leftName, rightName, L10n.Culture, System.Globalization.CompareOptions.IgnoreCase);
        }

        var groups = items.GroupBy(item => item.Item.Group).Select(group =>
        {
            var sorted = group.ToList();
            sorted.Sort((left, right) =>
            {
                int result = Compare(left.Name, left.Size, right.Name, right.Size);
                return result != 0 ? result : string.Compare(left.Item.RelativePath, right.Item.RelativePath, StringComparison.OrdinalIgnoreCase);
            });
            for (int i = 0; i < sorted.Count; i++) sorted[i].IsFirstInGroup = i == 0;
            return new GroupViewModel(group.Key, sorted);
        }).ToList();
        groups.Sort((left, right) => Compare(left.Name, left.TotalSize, right.Name, right.TotalSize));

        Groups.Clear();
        foreach (var group in groups) Groups.Add(group);
        OnPropertyChanged(nameof(SortTooltip));
    }

    [RelayCommand]
    private async Task Apply()
    {
        if (service == null || IsApplying) return;
        var targets = items.Where(item => !item.KeepOffline).ToList();
        if (targets.Count == 0) return;

        bool freeSpace = FreeSpace;
        IsApplying = true;
        Banner = null;
        OnPropertyChanged(nameof(ApplyingText));
        foreach (var target in targets) target.Activity = RowActivity.Waiting;

        long freed = 0;
        int kept = 0;
        var failures = new List<string>();
        foreach (var target in targets)
        {
            target.Activity = RowActivity.Working;
            try
            {
                var outcome = await service.MakeOnlineOnlyAsync(target.Item, freeSpace);
                freed += outcome.FreedBytes;
                kept += outcome.FilesKeptLocally;
                target.Activity = RowActivity.Done;
            }
            catch (Exception error) when (error is UnboxException or IOException or UnauthorizedAccessException)
            {
                failures.Add($"{target.Name}: {error.Message}");
                target.Activity = RowActivity.Failed;
            }
        }

        Banner = Summary(targets.Count - failures.Count, freed, freeSpace, kept, failures);
        IsApplying = false;
        foreach (var item in items) item.Activity = RowActivity.None;
        Refresh(force: true);
    }

    [RelayCommand]
    private void CancelSelection()
    {
        foreach (var item in items) item.KeepOffline = true;
    }

    [RelayCommand]
    private static void Reveal(ItemViewModel item) =>
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{item.FullPath}\"") { UseShellExecute = true });

    [RelayCommand]
    private void OpenBox()
    {
        var box = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Box", "Box", "Box.exe");
        if (File.Exists(box)) Process.Start(new ProcessStartInfo(box) { UseShellExecute = true });
        Task.Delay(3000).ContinueWith(_ => Application.Current.Dispatcher.Invoke(() => Refresh(force: true)));
    }

    [RelayCommand]
    private void ToggleSettings() => ShowingSettings = !ShowingSettings;

    [RelayCommand]
    private void CloseSettings() => ShowingSettings = false;

    [RelayCommand]
    private void DismissBanner() => Banner = null;

    [RelayCommand]
    private Task CheckForUpdates() => Updates.State == UpdateState.Available ? Updates.InstallAsync() : Updates.CheckAsync(userInitiated: true);

    [RelayCommand]
    private Task InstallUpdate() => Updates.InstallAsync();

    [RelayCommand]
    private static void Quit() => Application.Current.Shutdown();

    public void PopoverClosed()
    {
        if (!IsApplying && Banner?.Kind == BannerKind.Success) Banner = null;
    }

    private static Banner Summary(int done, long freed, bool freeSpace, int kept, List<string> failures)
    {
        var parts = new List<string>();
        if (done > 0)
        {
            parts.Add(L10n.Format("Online-only: %@.", "Tylko online: %@.", Plural.Items(done)));
            if (freeSpace) parts.Add(L10n.Format("Freed %@.", "Zwolniono %@.", NativeMethods.FormatBytes(freed)));
        }
        if (freeSpace && kept > 0) parts.Add(Plural.FilesKept(kept));
        if (failures.Count > 0)
        {
            parts.Add(string.Join("\n", failures));
            return new Banner(done > 0 ? BannerKind.Warning : BannerKind.Failure, string.Join(" ", parts));
        }
        return new Banner(kept > 0 && freeSpace ? BannerKind.Warning : BannerKind.Success, string.Join(" ", parts));
    }
}

public static class Plural
{
    public static string Items(long count) => L10n.Plural("items", count,
        ("%ld item", "%ld items"), ("%ld element", "%ld elementy", "%ld elementów"));

    public static string FilesKept(long count) => L10n.Plural("filesKept", count,
        ("%ld file stayed on disk (unsent changes or open files).", "%ld files stayed on disk (unsent changes or open files)."),
        ("%ld plik został na dysku (niewysłane zmiany lub otwarte pliki).",
         "%ld pliki zostały na dysku (niewysłane zmiany lub otwarte pliki).",
         "%ld plików zostało na dysku (niewysłane zmiany lub otwarte pliki)."));
}
