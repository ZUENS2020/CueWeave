namespace CueWeave.WinUI.Services;

internal static class WinPaths
{
    public const int SuggestedNameLimit = 64;

    public static bool IsTooLong(Exception exception)
    {
        if (exception is PathTooLongException) return true;
        if (exception.HResult is unchecked((int)0x800700CE) or 206) return true;
        return IsTooLong(exception.Message);
    }

    public static bool IsTooLong(string message) =>
        message.Contains("路径过长", StringComparison.Ordinal)
        || message.Contains("path is too long", StringComparison.OrdinalIgnoreCase)
        || message.Contains("filename or extension is too long", StringComparison.OrdinalIgnoreCase);

    public static string SuggestedFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var cleaned = new string([.. name.Where(value => value >= 32 && !invalid.Contains(value))]).Trim();
        if (cleaned.Length > SuggestedNameLimit) cleaned = cleaned[..SuggestedNameLimit].Trim();
        return string.IsNullOrEmpty(cleaned) ? "project" : cleaned.TrimEnd('.');
    }
}
