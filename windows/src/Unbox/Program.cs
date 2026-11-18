using Velopack;

namespace Unbox;

public static class Program
{
    private const string InstanceMutex = @"Local\unbox-single-instance";
    internal const string ShowEvent = @"Local\unbox-show-flyout";

    [STAThread]
    public static void Main(string[] args)
    {
        // Velopack runs install/update/uninstall hooks here and exits for them.
        VelopackApp.Build()
            .OnBeforeUninstallFastCallback(_ => LoginItem.Remove())
            .Run();

        // The demo (see Demo.cs) may run next to the real app.
        Mutex? mutex = null;
        if (!Demo.IsEnabled)
        {
            mutex = new Mutex(initiallyOwned: true, InstanceMutex, out bool isFirst);
            if (!isFirst)
            {
                // Starting unbox again (e.g. from the Start menu) opens the running instance.
                if (EventWaitHandle.TryOpenExisting(ShowEvent, out var show)) show.Set();
                mutex.Dispose();
                return;
            }
        }

        var app = new App { StartedAtLogin = args.Contains(LoginItem.BackgroundArgument) };
        app.InitializeComponent();
        app.Run();
        mutex?.Dispose();
    }
}
