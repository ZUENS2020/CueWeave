using Microsoft.UI.Dispatching;
using CueWeave.WinUI.Services;
using Microsoft.UI.Xaml;
using WinRT;

namespace CueWeave.WinUI;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        try
        {
            BootLog.Append("main");
            Environment.SetEnvironmentVariable("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY", AppContext.BaseDirectory);
            Environment.SetEnvironmentVariable("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY_PID",
                Environment.ProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture));
            ComWrappersSupport.InitializeComWrappers();
            Application.Start(_ =>
            {
                SynchronizationContext.SetSynchronizationContext(
                    new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
                BootLog.Append("app");
                new App();
            });
        }
        catch (Exception ex)
        {
            BootLog.Append(ex.ToString());
        }
    }
}
