using CueWeave.WinUI.Timeline;

namespace CueWeave.WinUI.Services;

public static class PlaybackTick
{
    public static double Update(Func<double> readPosition, Action<double> seek,
        bool playing, double? loopStart, double? loopEnd)
    {
        // The media clock advances between reads. Compare against one snapshot,
        // otherwise an ordinary rendering frame can repeatedly seek backwards.
        var sampled = readPosition();
        var position = TimelineViewport.ApplyLoop(sampled, playing, loopStart, loopEnd);
        if (position != sampled) seek(position);
        return position;
    }
}
