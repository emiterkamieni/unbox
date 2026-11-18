using CommunityToolkit.Mvvm.ComponentModel;
using Unbox.Kit;

namespace Unbox;

public enum RowActivity { None, Waiting, Working, Done, Failed }

public enum BannerKind { Success, Warning, Failure }

public sealed record Banner(BannerKind Kind, string Message)
{
    public string Glyph => Kind switch { BannerKind.Success => "\uE73E", BannerKind.Warning => "\uE7BA", _ => "\uEA39" };
}

public sealed partial class ItemViewModel(OfflineItem item, AppModel owner, bool keepOffline = true) : ObservableObject
{
    public OfflineItem Item { get; } = item;
    public string Name => Item.Name;
    public string Subpath => string.Join(" › ", Item.IntermediatePath);
    public bool HasSubpath => Item.IntermediatePath.Count > 0;
    public string Glyph => Item.IsFolder ? "\uE8B7" : "\uE8A5";
    public string FullPath => Item.FullPath;

    [ObservableProperty] private long? size;
    [ObservableProperty] private RowActivity activity;
    [ObservableProperty] private bool isFirstInGroup;

    private bool keepOffline = keepOffline;
    public bool KeepOffline
    {
        get => keepOffline;
        set
        {
            if (owner.IsApplying || !SetProperty(ref keepOffline, value)) return;
            OnPropertyChanged(nameof(CheckboxTooltip));
            OnPropertyChanged(nameof(SizeTooltip));
            owner.SelectionChanged();
        }
    }

    public string SizeText => Size is long bytes ? L10n.Bytes(bytes) : "…";
    public bool ShowsSize => Activity == RowActivity.None;

    public string CheckboxTooltip => KeepOffline
        ? L10n.Text("Uncheck to make it online-only", "Odznacz, aby ustawić jako tylko online")
        : L10n.Text("Keep offline", "Pozostaw offline");

    public string SizeTooltip => KeepOffline
        ? L10n.Text("Space used on disk", "Miejsce zajmowane na dysku")
        : L10n.Text("Space that will be freed", "Tyle miejsca się zwolni");

    public string RevealTooltip => L10n.Text("Show in File Explorer", "Pokaż w Eksploratorze plików");

    public string ActivityGlyph => Activity switch
    {
        RowActivity.Waiting => "\uE823",
        RowActivity.Done => "\uE73E",
        RowActivity.Failed => "\uEA39",
        _ => "",
    };

    partial void OnSizeChanged(long? value) => OnPropertyChanged(nameof(SizeText));

    partial void OnActivityChanged(RowActivity value)
    {
        OnPropertyChanged(nameof(ShowsSize));
        OnPropertyChanged(nameof(ActivityGlyph));
    }

    public void RefreshTexts() => OnPropertyChanged(string.Empty);
}

public sealed class GroupViewModel(string name, IReadOnlyList<ItemViewModel> items)
{
    public string Name { get; } = name;
    public IReadOnlyList<ItemViewModel> Items { get; } = items;
    public long? TotalSize => Items.All(item => item.Size.HasValue) ? Items.Sum(item => item.Size!.Value) : null;
    public string SizeText => TotalSize is long bytes ? L10n.Bytes(bytes) : "";
}

public sealed record Choice<T>(T Value, string Title);
