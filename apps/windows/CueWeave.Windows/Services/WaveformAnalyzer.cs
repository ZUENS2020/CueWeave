using NAudio.Dsp;
using NAudio.Wave;

namespace CueWeave.WinUI.Services;

public sealed record SpectrogramFrame(
    byte[] Values,
    int TimeBins,
    int FrequencyBins,
    ulong StartMs,
    ulong EndMs);

public sealed record WaveformData(float[] Peak, float[] Low, float[] Mid, float[] High)
{
    public float[] Rms { get; init; } = [];
    public IReadOnlyDictionary<string, SpectrogramFrame> Spectrograms { get; init; } =
        new Dictionary<string, SpectrogramFrame>();
    public static WaveformData Empty { get; } = new([], [], [], []);
}

public static class WaveformAnalyzer
{
    public static Task<WaveformData> AnalyzeAsync(string path, int bins = 4096,
        CancellationToken token = default) => Task.Run(() => Analyze(path, bins, token), token);

    internal static WaveformData Analyze(string path, int bins, CancellationToken token)
    {
        using var file = new FileStream(WinPaths.Normalize(path), FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = Open(file, path);
        var format = reader.WaveFormat;
        var channels = format.Channels;
        var sampleRate = format.SampleRate;
        var bytesPerSample = Math.Max(1, format.BitsPerSample / 8);
        var totalFrames = Math.Max(1L, (long)Math.Ceiling(reader.TotalTime.TotalSeconds * sampleRate));
        var peak = new float[bins]; var low = new float[bins]; var mid = new float[bins]; var high = new float[bins];
        const int fftSize = 1024; const int fftPower = 10;
        var bytes = new byte[fftSize * format.BlockAlign];
        var spectrum = new Complex[fftSize];
        long framePosition = 0;
        while (true) {
            token.ThrowIfCancellationRequested();
            var read = reader.Read(bytes, 0, bytes.Length);
            if (read == 0) break;
            var frames = read / format.BlockAlign;
            for (var frame = 0; frame < frames; frame++) {
                float mono = 0;
                for (var channel = 0; channel < channels; channel++)
                    mono += SampleAt(bytes, frame * format.BlockAlign + channel * bytesPerSample, format);
                mono /= channels;
                var bin = (int)Math.Min(bins - 1, (framePosition + frame) * bins / totalFrames);
                peak[bin] = Math.Max(peak[bin], Math.Abs(mono));
                spectrum[frame].X = (float)(mono * FastFourierTransform.HammingWindow(frame, fftSize));
                spectrum[frame].Y = 0;
            }
            for (var frame = frames; frame < fftSize; frame++) spectrum[frame] = new Complex();
            FastFourierTransform.FFT(true, fftPower, spectrum);
            var energyBin = (int)Math.Min(bins - 1, (framePosition + frames / 2) * bins / totalFrames);
            for (var index = 1; index < fftSize / 2; index++) {
                var frequency = index * sampleRate / (float)fftSize;
                var magnitude = spectrum[index].X * spectrum[index].X + spectrum[index].Y * spectrum[index].Y;
                if (frequency < 250) low[energyBin] += (float)magnitude;
                else if (frequency < 2_000) mid[energyBin] += (float)magnitude;
                else high[energyBin] += (float)magnitude;
            }
            framePosition += frames;
        }
        Normalize(peak, squareRoot: false); Normalize(low, true); Normalize(mid, true); Normalize(high, true);
        return new(peak, low, mid, high);
    }

    private static WaveStream Open(FileStream file, string path)
    {
        if (Path.GetExtension(path).Equals(".wav", StringComparison.OrdinalIgnoreCase))
            return new WaveFileReader(file);
#if WINDOWS
        return new StreamMediaFoundationReader(file);
#else
        return new AudioFileReader(path);
#endif
    }

    private static float SampleAt(byte[] data, int offset, WaveFormat format)
    {
        if (format.Encoding == WaveFormatEncoding.IeeeFloat && format.BitsPerSample >= 32)
            return BitConverter.ToSingle(data, offset);
        if (format.BitsPerSample == 16) return BitConverter.ToInt16(data, offset) / 32768f;
        if (format.BitsPerSample == 8) return (data[offset] - 128) / 128f;
        return 0;
    }

    private static void Normalize(float[] values, bool squareRoot)
    {
        if (squareRoot) for (var i = 0; i < values.Length; i++) values[i] = MathF.Sqrt(values[i]);
        var maximum = values.DefaultIfEmpty().Max();
        if (maximum <= 0) return;
        for (var i = 0; i < values.Length; i++) values[i] /= maximum;
    }
}
