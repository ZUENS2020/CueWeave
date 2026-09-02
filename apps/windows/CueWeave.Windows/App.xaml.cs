using Microsoft.UI.Xaml;

namespace CueWeave.WinUI;

public partial class App : Application
{
    public static MainWindow MainWindow { get; private set; } = null!;

    public App()
    {
        UnhandledException += (_, e) =>
        {
            try
            {
                File.AppendAllText(
                    Path.Combine(AppContext.BaseDirectory, "boot.log"),
                    $"{DateTime.Now:O} unhandled {e.Exception}{Environment.NewLine}");
            }
            catch { /* boot diagnostics must not throw */ }
        };
        InitializeComponent();
        try
        {
            File.AppendAllText(
                Path.Combine(AppContext.BaseDirectory, "boot.log"),
                $"{DateTime.Now:O} app-init{Environment.NewLine}");
        }
        catch { /* boot diagnostics must not throw */ }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            File.AppendAllText(
                Path.Combine(AppContext.BaseDirectory, "boot.log"),
                $"{DateTime.Now:O} launched{Environment.NewLine}");
        }
        catch { /* boot diagnostics must not throw */ }
        MainWindow = new MainWindow();
        MainWindow.Activate();
        try
        {
            File.AppendAllText(
                Path.Combine(AppContext.BaseDirectory, "boot.log"),
                $"{DateTime.Now:O} activated{Environment.NewLine}");
        }
        catch { /* boot diagnostics must not throw */ }
        MainWindow.LoadPage();
        try
        {
            File.AppendAllText(
                Path.Combine(AppContext.BaseDirectory, "boot.log"),
                $"{DateTime.Now:O} page{Environment.NewLine}");
        }
        catch { /* boot diagnostics must not throw */ }
    }
}
