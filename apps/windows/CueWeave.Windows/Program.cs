using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using WinRT;

namespace CueWeave.WinUI;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        var log = Path.Combine(AppContext.BaseDirectory, "boot.log");
        try
        {
            File.WriteAllText(log, $"{DateTime.Now:O} main{Environment.NewLine}");
            Environment.SetEnvironmentVariable("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY", AppContext.BaseDirectory);
            Environment.SetEnvironmentVariable("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY_PID",
                Environment.ProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture));
            ComWrappersSupport.InitializeComWrappers();
            Application.Start(_ =>
            {
                SynchronizationContext.SetSynchronizationContext(
                    new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
                File.AppendAllText(log, $"{DateTime.Now:O} app{Environment.NewLine}");
                new App();
            });
        }
        catch (Exception ex)
        {
            File.AppendAllText(log, ex.ToString());
        }
    }
}
