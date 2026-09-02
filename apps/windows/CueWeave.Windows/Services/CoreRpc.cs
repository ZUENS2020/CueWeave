using System.Text;
using System.Text.Json;

namespace CueWeave.WinUI.Services;

public sealed class CoreException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

internal static class CoreRpc
{
    public static JsonElement ReadResult(ReadOnlySpan<byte> stdout, string requestId)
    {
        if (stdout.Length >= 3 && stdout[0] == 0xEF && stdout[1] == 0xBB && stdout[2] == 0xBF)
            stdout = stdout[3..];
        stdout = stdout.Trim("\r\n\t "u8);
        if (stdout.IsEmpty)
            throw new CoreException("invalid_response", L10n.T("error.invalidResponse", "empty"));

        JsonDocument document;
        try
        {
            var reader = new Utf8JsonReader(stdout);
            document = JsonDocument.ParseValue(ref reader);
        }
        catch (JsonException exception)
        {
            throw new CoreException("invalid_response", L10n.T("error.invalidResponse", exception.Message));
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
                throw new CoreException("invalid_response", L10n.T("error.invalidResponse", "envelope"));
            if (!root.TryGetProperty("request_id", out var id) || id.GetString() != requestId)
                throw new CoreException("invalid_response", L10n.T("error.coreMismatch"));
            if (!root.TryGetProperty("ok", out var ok) || ok.ValueKind != JsonValueKind.True)
            {
                var error = root.TryGetProperty("error", out var payload) ? payload : default;
                throw new CoreException(
                    error.ValueKind == JsonValueKind.Object && error.TryGetProperty("code", out var code)
                        ? code.GetString() ?? "core_error" : "core_error",
                    error.ValueKind == JsonValueKind.Object && error.TryGetProperty("message", out var message)
                        ? message.GetString() ?? L10n.T("error.coreFailed") : L10n.T("error.coreFailed"));
            }
            return root.TryGetProperty("result", out var result) ? result.Clone() : default;
        }
    }

    public static string Preview(ReadOnlySpan<byte> stdout)
    {
        var length = Math.Min(stdout.Length, 900);
        return Encoding.UTF8.GetString(stdout[..length]);
    }
}
