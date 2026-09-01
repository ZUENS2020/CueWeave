namespace CueWeave.WinUI.Timeline;

public sealed record AudioVizAdapterInfo(
    string Id,
    string Title,
    string Detail,
    string Surface,
    string[] Series,
    string? Scale);

public static class AudioVizCatalog
{
    public static readonly AudioVizAdapterInfo[] All =
    [
        new("peak", "Peak", "Peak envelope", "waveform", ["peak"], null),
        new("rms", "RMS", "RMS envelope", "waveform", ["rms"], null),
        new("peakRms", "Peak + RMS", "Peak envelope with RMS overlay", "waveform", ["peak", "rms"], null),
        new("bands", "Band Energy", "Low / mid / high energy", "bands", [], null),
        new("specLinear", "Spec · Linear", "Linear STFT", "spectrogram", [], "linear"),
        new("specLog", "Spec · Log", "Log-frequency STFT", "spectrogram", [], "log"),
        new("specMel", "Spec · Mel", "Mel spectrogram", "spectrogram", [], "mel"),
    ];

    public static AudioVizAdapterInfo? Find(string id) =>
        All.FirstOrDefault(adapter => adapter.Id == id);
}
