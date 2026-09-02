using CueWeave.WinUI.Services;
using Microsoft.UI.Xaml;

namespace CueWeave.WinUI;

public partial class App : Application
{
    public static MainWindow MainWindow { get; private set; } = null!;

    public App()
    {
        UnhandledException += (_, e) => BootLog.Append($"unhandled {e.Exception}");
        InitializeComponent();
        BootLog.Append("app-init");
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        BootLog.Append("launched");
        MainWindow = new MainWindow();
        MainWindow.Activate();
        BootLog.Append("activated");
        try
        {
            MainWindow.LoadPage();
            BootLog.Append("page");
        }
        catch (Exception ex)
        {
            BootLog.Append($"page-fail {ex}");
            throw;
        }
    }
}
