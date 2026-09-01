using CueWeave.WinUI.Timeline;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage;

namespace CueWeave.WinUI.Services;

public sealed class PlaybackService : IDisposable
{
    private readonly MediaPlayer player = new() { AudioCategory = MediaPlayerAudioCategory.Media };

    public double PositionMs => player.PlaybackSession.Position.TotalMilliseconds;
    public double DurationMs => player.PlaybackSession.NaturalDuration.TotalMilliseconds;
    public bool IsPlaying => player.PlaybackSession.PlaybackState == MediaPlaybackState.Playing;
    public double Rate => player.PlaybackSession.PlaybackRate;
    public double? LoopStartMs { get; private set; }
    public double? LoopEndMs { get; private set; }

    public PlaybackService() => player.CommandManager.IsEnabled = false;

    public async Task LoadAsync(string path)
    {
        var file = await StorageFile.GetFileFromPathAsync(path);
        player.Source = MediaSource.CreateFromStorageFile(file);
        player.PlaybackSession.Position = TimeSpan.Zero;
        ClearLoop();
    }

    public void PlayPause()
    {
        if (IsPlaying) player.Pause(); else player.Play();
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
    public void Dispose() { player.Dispose(); GC.SuppressFinalize(this); }
}
