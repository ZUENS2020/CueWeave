using System.Security.Cryptography;
using System.Text;

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
        || message.Contains("超出了最大长度", StringComparison.Ordinal)
        || message.Contains("path is too long", StringComparison.OrdinalIgnoreCase)
        || message.Contains("exceeds the maximum", StringComparison.OrdinalIgnoreCase)
        || message.Contains("filename or extension is too long", StringComparison.OrdinalIgnoreCase);

    public static string Normalize(string path) =>
        Path.GetFullPath(path.Replace('/', Path.DirectorySeparatorChar));

    public static bool NeedsLocalCopy(string path)
    {
        if (path.StartsWith(@"\\", StringComparison.Ordinal) || path.StartsWith("//", StringComparison.Ordinal))
            return true;
        var source = Normalize(path);
        if (source.Length >= 240) return true;
        var root = Path.GetPathRoot(source);
        if (string.IsNullOrEmpty(root) || root.Length < 2 || root[1] != ':') return false;
        try
        {
            return new DriveInfo(root).DriveType is DriveType.Network or DriveType.Unknown;
        }
        catch
        {
            return true;
        }
    }

    public static string Materialize(string path, string? fingerprint = null)
    {
        var source = Normalize(path);
        if (!File.Exists(source)) throw new FileNotFoundException(source, source);
        if (!NeedsLocalCopy(source)) return source;
        var root = Path.Combine(Path.GetTempPath(), "CueWeave", "audio");
        Directory.CreateDirectory(root);
        var extension = Path.GetExtension(source);
        if (string.IsNullOrEmpty(extension)) extension = ".mp3";
        var tag = string.IsNullOrWhiteSpace(fingerprint)
            ? Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(source)))[..16]
            : fingerprint[..Math.Min(16, fingerprint.Length)];
        var dest = Path.Combine(root, $"{tag}{extension.ToLowerInvariant()}");
        if (PathsEqual(source, dest)) return dest;
        var sourceInfo = new FileInfo(source);
        if (File.Exists(dest))
        {
            var destInfo = new FileInfo(dest);
            if (destInfo.Length == sourceInfo.Length && destInfo.LastWriteTimeUtc >= sourceInfo.LastWriteTimeUtc)
                return dest;
        }
        var temporary = dest + ".tmp";
        File.Copy(source, temporary, overwrite: true);
        File.Move(temporary, dest, overwrite: true);
        return dest;
    }

    public static string SuggestedFileName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var cleaned = new string([.. name.Where(value => value >= 32 && !invalid.Contains(value))]).Trim();
        if (cleaned.Length > SuggestedNameLimit) cleaned = cleaned[..SuggestedNameLimit].Trim();
        return string.IsNullOrEmpty(cleaned) ? "project" : cleaned.TrimEnd('.');
    }

    private static bool PathsEqual(string left, string right) =>
        string.Equals(Path.GetFullPath(left), Path.GetFullPath(right), StringComparison.OrdinalIgnoreCase);
}
