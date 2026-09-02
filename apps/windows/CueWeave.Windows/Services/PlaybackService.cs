using CueWeave.WinUI.Timeline;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage.Streams;

namespace CueWeave.WinUI.Services;

public sealed class PlaybackService : IDisposable
{
    private readonly MediaPlayer player = new() { AudioCategory = MediaPlayerAudioCategory.Media };
    private MediaSource? source;
    private IRandomAccessStream? content;

    public double PositionMs => player.PlaybackSession.Position.TotalMilliseconds;
    public double DurationMs => player.PlaybackSession.NaturalDuration.TotalMilliseconds;
    public MediaPlaybackState TransportState => player.PlaybackSession.PlaybackState;
    public bool IsPlaying => TransportState == MediaPlaybackState.Playing;
    public bool IsTransportActive => TransportState is MediaPlaybackState.Playing
        or MediaPlaybackState.Buffering or MediaPlaybackState.Opening;
    public double Rate => player.PlaybackSession.PlaybackRate;
    public double? LoopStartMs { get; private set; }
    public double? LoopEndMs { get; private set; }
    public event Action? StateChanged;

    public PlaybackService()
    {
        player.CommandManager.IsEnabled = false;
        player.PlaybackSession.PlaybackStateChanged += (_, _) => StateChanged?.Invoke();
    }

    public async Task LoadAsync(string path)
    {
        ReleaseSource();
        var normalized = WinPaths.Normalize(path);
        content = await CopyFile(normalized);
        source = MediaSource.CreateFromStream(content, Mime(normalized));
        player.Source = source;
        player.PlaybackSession.Position = TimeSpan.Zero;
        ClearLoop();
    }

    public void Play() => player.Play();
    public void Pause() => player.Pause();

    public void PlayPause()
    {
        if (IsTransportActive) Pause(); else Play();
    }

    public void Seek(double milliseconds) => player.PlaybackSession.Position =
        TimeSpan.FromMilliseconds(Math.Clamp(milliseconds, 0, Math.Max(DurationMs, 0)));

    public void SetRate(double value) => player.PlaybackSession.PlaybackRate = Math.Clamp(value, .5, 2);

    public double Tick()
    {
        var position = TimelineViewport.ApplyLoop(PositionMs, IsPlaying, LoopStartMs, LoopEndMs);
        if (position != PositionMs) Seek(position);
        return position;
    }

    public void MarkA()
    {
        LoopStartMs = PositionMs;
        if (LoopEndMs <= LoopStartMs) LoopEndMs = null;
    }

    public void MarkB()
    {
        var position = PositionMs;
        if (LoopStartMs is not double start) { LoopStartMs = 0; LoopEndMs = position; }
        else if (position > start) LoopEndMs = position;
        else { LoopStartMs = position; LoopEndMs = start; }
    }

    public void ClearLoop() { LoopStartMs = null; LoopEndMs = null; }

    public void Dispose()
    {
        ReleaseSource();
        player.Dispose();
        GC.SuppressFinalize(this);
    }

    private void ReleaseSource()
    {
        player.Source = null;
        source?.Dispose();
        source = null;
        content?.Dispose();
        content = null;
    }

    private static async Task<IRandomAccessStream> CopyFile(string path)
    {
        var memory = new InMemoryRandomAccessStream();
        await using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var writer = new DataWriter(memory);
        var buffer = new byte[64 * 1024];
        int read;
        while ((read = await file.ReadAsync(buffer, 0, buffer.Length)) > 0)
        {
            writer.WriteBytes(read == buffer.Length ? buffer : buffer[..read]);
            await writer.StoreAsync();
        }
        await writer.FlushAsync();
        writer.DetachStream();
        writer.Dispose();
        memory.Seek(0);
        return memory;
    }

    private static string Mime(string path) => Path.GetExtension(path).ToLowerInvariant() switch
    {
        ".wav" => "audio/wav",
        ".flac" => "audio/flac",
        ".m4a" or ".mp4" or ".aac" => "audio/mp4",
        _ => "audio/mpeg"
    };
}
