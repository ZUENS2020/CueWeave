using System.Text.Json;
using System.Text.Json.Nodes;
using CueWeave.WinUI.Models;

namespace CueWeave.WinUI.Services;

public static class AudioVizClient
{
    public static string CacheDirectory
    {
        get
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "CueWeave",
                "Cache");
            Directory.CreateDirectory(path);
            return path;
        }
    }

    public static async Task<WaveformData> EnrichAsync(
        CoreProcess core,
        string audioPath,
        string? sha256,
        WaveformData native,
        IReadOnlyList<string> scales,
        CancellationToken token)
    {
        if (!audioPath.EndsWith(".mp3", StringComparison.OrdinalIgnoreCase)) return native;
        try
        {
            var waveform = await core.CallAsync("audio_viz", Payload(audioPath, sha256, "prepare", native.Peak.Length), token);
            var peak = Floats(waveform, "peak_max");
            var rms = Floats(waveform, "rms");
            var frames = native.Spectrograms.ToDictionary(entry => entry.Key, entry => entry.Value);
            foreach (var scale in scales.Distinct())
            {
                var spectrogram = await core.CallAsync(
                    "audio_viz",
                    Payload(audioPath, sha256, "spectrogram", scale: scale),
                    token);
                var values = Convert.FromBase64String(
                    spectrogram.TryGetProperty("values", out var encoded) ? encoded.GetString() ?? "" : "");
                frames[scale] = new SpectrogramFrame(
                    values,
                    spectrogram.TryGetProperty("time_bins", out var time) ? time.GetInt32() : 0,
                    spectrogram.TryGetProperty("frequency_bins", out var freq) ? freq.GetInt32() : 0,
                    spectrogram.TryGetProperty("start_ms", out var start) ? start.GetUInt64() : 0,
                    spectrogram.TryGetProperty("end_ms", out var end) ? end.GetUInt64() : 0);
            }
            return native with
            {
                Peak = peak.Length == native.Peak.Length ? peak : native.Peak,
                Rms = rms,
                Spectrograms = frames
            };
        }
        catch
        {
            return native;
        }
    }

    private static JsonObject Payload(string path, string? sha256, string action, int bins = 4096, string scale = "log")
    {
        var payload = new JsonObject
        {
            ["action"] = action,
            ["audio_path"] = path,
            ["cache_dir"] = CacheDirectory,
            ["waveform_bins"] = bins,
            ["scale"] = scale,
            ["frequency_bins"] = 128
        };
        if (!string.IsNullOrWhiteSpace(sha256)) payload["sha256"] = sha256;
        return payload;
    }

    private static float[] Floats(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var values) || values.ValueKind != JsonValueKind.Array) return [];
        return [.. values.EnumerateArray().Select(value => value.GetSingle())];
    }
}
