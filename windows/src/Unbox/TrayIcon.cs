using System.ComponentModel;
using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using H.NotifyIcon;
using H.NotifyIcon.Core;
using Microsoft.Win32;
using Unbox.Kit;

namespace Unbox;

/// <summary>The notification area icon: left click opens the flyout, right click shows a menu.</summary>
public sealed class TrayIcon : IDisposable
{
    private readonly TaskbarIcon icon;
    private readonly AppModel model;
    private readonly Action toggleFlyout;
    private readonly Action<bool> showFlyout;

    public TrayIcon(AppModel model, Action toggleFlyout, Action<bool> showFlyout)
    {
        this.model = model;
        this.toggleFlyout = toggleFlyout;
        this.showFlyout = showFlyout;
        icon = new TaskbarIcon { NoLeftClickDelay = true, MenuActivation = PopupActivationMode.RightClick };
        icon.TrayLeftMouseUp += (_, _) => toggleFlyout();
        icon.TrayBalloonTipClicked += (_, _) => showFlyout(false);
        UpdateIcon();
        UpdateTooltip();
        icon.ContextMenu = BuildMenu();
        icon.ForceCreate(enablesEfficiencyMode: false);

        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        model.PropertyChanged += OnModelChanged;
        model.Updates.UpdateFound += version => icon.ShowNotification(
            L10n.Format("unbox %@", "unbox %@", version), L10n.Text("Update available.", "Dostępna aktualizacja."));
    }

    private ContextMenu BuildMenu()
    {
        MenuItem Item(string header, Action action)
        {
            var item = new MenuItem { Header = header };
            item.Click += (_, _) => action();
            return item;
        }

        return new ContextMenu
        {
            Items =
            {
                Item(L10n.Text("Open unbox", "Otwórz unbox"), () => showFlyout(false)),
                Item(L10n.Text("Settings", "Ustawienia"), () => showFlyout(true)),
                Item(L10n.Text("Check for Updates…", "Sprawdź aktualizacje…"), () =>
                {
                    showFlyout(true);
                    model.CheckForUpdatesCommand.Execute(null);
                }),
                new Separator(),
                Item(L10n.Text("Quit unbox", "Zakończ unbox"), () => Application.Current.Shutdown()),
            },
        };
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName is null or "" or nameof(AppModel.HeaderSubtitle) or nameof(AppModel.IsApplying))
        {
            UpdateTooltip();
            if (args.PropertyName is null or "") icon.ContextMenu = BuildMenu(); // language changed
        }
    }

    private void UpdateTooltip()
    {
        icon.ToolTipText = model.IsApplying
            ? L10n.Text("unbox: changing offline settings…", "unbox: zmieniam ustawienia offline…")
            : model.HasItems
                ? L10n.Format("unbox – offline: %@", "unbox – offline: %@", Plural.Items(model.ItemCount))
                : L10n.Text("unbox – nothing is offline", "unbox – nic nie jest offline");
    }

    /// <summary>White symbol on dark taskbars, black on light ones, at the size Windows asks for.</summary>
    private void UpdateIcon()
    {
        var name = NativeMethods.TaskbarUsesLightTheme ? "TrayLight.ico" : "TrayDark.ico";
        var resource = Application.GetResourceStream(new Uri($"pack://application:,,,/Assets/{name}"));
        if (resource == null) return;
        using var stream = resource.Stream;
        int size = NativeMethods.GetSystemMetrics(NativeMethods.SmallIconWidth);
        icon.Icon = new Icon(stream, new System.Drawing.Size(size, size));
    }

    private void OnUserPreferenceChanged(object? sender, UserPreferenceChangedEventArgs args)
    {
        if (args.Category is UserPreferenceCategory.General or UserPreferenceCategory.VisualStyle)
            Application.Current.Dispatcher.Invoke(UpdateIcon);
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs args) => Application.Current.Dispatcher.Invoke(UpdateIcon);

    public void Dispose()
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        icon.Dispose();
    }
}
