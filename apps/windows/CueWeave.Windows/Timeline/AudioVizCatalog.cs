namespace CueWeave.WinUI.Timeline;

public sealed record AudioVizAdapterInfo(
    string Id,
    string Surface,
    string[] Series,
    string? Scale);

public static class AudioVizCatalog
{
    public static readonly AudioVizAdapterInfo[] All =
    [
        new("peak", "waveform", ["peak"], null),
        new("rms", "waveform", ["rms"], null),
        new("peakRms", "waveform", ["peak", "rms"], null),
        new("bands", "bands", [], null),
        new("specLinear", "spectrogram", [], "linear"),
        new("specLog", "spectrogram", [], "log"),
        new("specMel", "spectrogram", [], "mel"),
    ];

    public static AudioVizAdapterInfo? Find(string id) =>
        All.FirstOrDefault(adapter => adapter.Id == id);
}
