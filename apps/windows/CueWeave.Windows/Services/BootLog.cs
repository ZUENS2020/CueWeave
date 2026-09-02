namespace CueWeave.WinUI.Services;

internal static class BootLog
{
    public static string FilePath { get; } = Path.Combine(AppContext.BaseDirectory, "boot.log");

    public static void Append(string message)
    {
        try
        {
            File.AppendAllText(FilePath, $"{DateTime.Now:O} {message}{Environment.NewLine}");
            Trim();
        }
        catch { /* boot diagnostics must not throw */ }
    }

    private static void Trim()
    {
        try
        {
            var info = new FileInfo(FilePath);
            if (!info.Exists || info.Length < 200_000) return;
            var text = File.ReadAllText(FilePath);
            if (text.Length < 160_000) return;
            File.WriteAllText(FilePath, text[^120_000..]);
        }
        catch { /* boot diagnostics must not throw */ }
    }
}
