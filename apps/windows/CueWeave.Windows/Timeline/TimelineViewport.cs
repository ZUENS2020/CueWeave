namespace CueWeave.WinUI.Timeline;

public sealed class TimelineViewport
{
    public const double MaximumZoom = 100;
    public const double DragThreshold = 4;
    public double DurationMs { get; private set; } = 1;
    public double VisibleStartMs { get; private set; }
    public double VisibleDurationMs { get; private set; } = 1;
    public bool FollowEnabled { get; set; } = true;
    public bool GestureActive { get; set; }
    public (double Start, double End)? Selection { get; set; }
    private int followFreeze;
    public double VisibleEndMs => VisibleStartMs + VisibleDurationMs;
    public double Zoom => DurationMs / VisibleDurationMs;

    public void SetDocument(double durationMs)
    {
        DurationMs = Math.Max(1, durationMs);
        VisibleDurationMs = DurationMs;
        VisibleStartMs = 0;
    }

    public double TimeAt(double x, double width) => Clamp(VisibleStartMs + Math.Clamp(x / Math.Max(width, 1), 0, 1) * VisibleDurationMs);
    public double XAt(double timeMs, double width) => (timeMs - VisibleStartMs) / VisibleDurationMs * width;
    public double SeekStep => Math.Max(1, VisibleDurationMs * .01);

    public void ZoomAt(double scale, double anchorMs)
    {
        if (!double.IsFinite(scale) || scale <= 0) return;
        var fraction = (Clamp(anchorMs) - VisibleStartMs) / VisibleDurationMs;
        var newDuration = Math.Clamp(VisibleDurationMs / scale, DurationMs / MaximumZoom, DurationMs);
        SetRange(anchorMs - fraction * newDuration, newDuration);
    }

    public void SetZoom(double zoom, double playheadMs)
    {
        var anchor = playheadMs >= VisibleStartMs && playheadMs <= VisibleEndMs
            ? playheadMs : VisibleStartMs + VisibleDurationMs / 2;
        var newDuration = DurationMs / Math.Clamp(zoom, 1, MaximumZoom);
        SetRange(anchor - newDuration / 2, newDuration);
    }

    public void Pan(double deltaMs) => SetRange(VisibleStartMs + deltaMs, VisibleDurationMs);
    public void SetStart(double startMs) => SetRange(startMs, VisibleDurationMs);

    public void ZoomSelection(double x0, double x1, double width)
    {
        var start = TimeAt(Math.Min(x0, x1), width); var end = TimeAt(Math.Max(x0, x1), width);
        if (end <= start) return;
        var padding = (end - start) * .04;
        SetRange(start - padding, end - start + padding * 2);
        Selection = null;
    }

    public void Follow(double playheadMs)
    {
        if (!FollowEnabled || GestureActive) return;
        if (followFreeze > 0)
        {
            followFreeze--;
            return;
        }
        SetRange(playheadMs - VisibleDurationMs / 2, VisibleDurationMs);
    }

    public void NoteUserInteraction(int frames = 24) => followFreeze = Math.Max(followFreeze, frames);

    public static double ApplyLoop(double positionMs, bool isPlaying, double? start, double? end) =>
        isPlaying && start is double a && end is double b && b > a && positionMs >= b ? a : positionMs;

    public static bool IsSelection(double startX, double currentX) => Math.Abs(currentX - startX) > DragThreshold;
    public static long NudgeDelta(int heldStep, bool right) => (right ? 1L : -1L) * heldStep;
    public static (double Ruler, double Waveform, double Bands, double Lyrics) Layout(double height)
    {
        var remaining = Math.Max(0, height - 24 - 72); return (24, remaining / 2, remaining / 2, 72);
    }

    private void SetRange(double start, double duration)
    {
        VisibleDurationMs = Math.Clamp(duration, DurationMs / MaximumZoom, DurationMs);
        VisibleStartMs = Math.Clamp(start, 0, Math.Max(0, DurationMs - VisibleDurationMs));
    }

    private double Clamp(double value) => Math.Clamp(value, 0, DurationMs);
}
