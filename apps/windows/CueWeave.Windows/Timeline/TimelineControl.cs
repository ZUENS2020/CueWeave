using System.Numerics;
using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using Windows.UI.Core;

namespace CueWeave.WinUI.Timeline;

public sealed class TimelineControl : UserControl
{
    private readonly CanvasControl canvas = new();
    private readonly ScrollBar scroll = new() { Orientation = Orientation.Horizontal, Height = 12, VerticalAlignment = VerticalAlignment.Bottom };
    private IReadOnlyList<LyricSegment> segments = [];
    private WaveformData waveform = WaveformData.Empty;
    private bool changingScroll;
    private uint? pointerId;
    private double pressedX;
    private bool dragging;
    private int heldStep;
    private ulong? activeId;

    public TimelineViewport Viewport { get; } = new();
    public double PlayheadMs { get; private set; }
    public ulong? ActiveSegmentId => activeId;
    public ulong? SelectedSegmentId { get; private set; }
    public double? LoopStartMs { get; set; }
    public double? LoopEndMs { get; set; }

    public event Action<double>? SeekRequested;
    public event Action<long>? NudgeRequested;
    public event Action<string>? CommandRequested;
    public event Action<ulong?>? ActiveSegmentChanged;
    public event Action<ulong?>? SelectedSegmentChanged;
    public event Action<double>? ZoomChanged;
    public string WaveformLabel { get; private set; } = "WAVEFORM";
    public string BandLabel { get; private set; } = "BAND ENERGY  LOW / MID / HIGH";
    public string LyricsLaneLabel { get; private set; } = "LYRICS / TIMESTAMPS";

    public TimelineControl()
    {
        IsTabStop = true;
        var grid = new Grid(); grid.Children.Add(canvas); grid.Children.Add(scroll); Content = grid;
        canvas.Draw += Draw;
        canvas.PointerPressed += OnPointerPressed; canvas.PointerMoved += OnPointerMoved;
        canvas.PointerReleased += OnPointerReleased; canvas.PointerCaptureLost += OnPointerCaptureLost;
        canvas.PointerWheelChanged += PointerWheel;
        canvas.ManipulationMode = ManipulationModes.Scale;
        canvas.ManipulationStarted += (_, _) => Viewport.GestureActive = true;
        canvas.ManipulationDelta += OnManipulationDelta;
        canvas.ManipulationCompleted += (_, _) => { Viewport.GestureActive = false; CommitViewport(); };
        scroll.ValueChanged += ScrollChanged;
        KeyDown += HandleKeyDown; KeyUp += HandleKeyUp;
    }

    public void SetDocument(double durationMs, IReadOnlyList<LyricSegment> values)
    {
        segments = values; Viewport.SetDocument(durationMs); SelectedSegmentId = null; activeId = null;
        CommitViewport(); canvas.Invalidate();
    }

    public void SetWaveform(WaveformData value) { waveform = value; canvas.Invalidate(); }
    public void SetSegments(IReadOnlyList<LyricSegment> values) { segments = values; canvas.Invalidate(); }
    public void SetLaneLabels(string waveformLabel, string bandLabel, string lyricsLabel)
    {
        WaveformLabel = waveformLabel;
        BandLabel = bandLabel;
        LyricsLaneLabel = lyricsLabel;
        canvas.Invalidate();
    }
    public void SetFollow(bool enabled)
    {
        Viewport.FollowEnabled = enabled;
        if (enabled && !Viewport.GestureActive) { Viewport.Follow(PlayheadMs); CommitViewport(); }
    }

    public void SetZoom(double zoom)
    {
        Viewport.SetZoom(zoom, PlayheadMs); CommitViewport();
    }

    public void Tick(double playheadMs)
    {
        PlayheadMs = Math.Clamp(playheadMs, 0, Viewport.DurationMs);
        var nextActive = SegmentAt(PlayheadMs)?.Id;
        if (nextActive != activeId) { activeId = nextActive; ActiveSegmentChanged?.Invoke(activeId); }
        Viewport.Follow(PlayheadMs); CommitViewport(invalidate: true);
    }

    public void Select(ulong? id)
    {
        SelectedSegmentId = id; SelectedSegmentChanged?.Invoke(id); canvas.Invalidate();
    }

    public void SelectCurrent() => Select(activeId);

    public void SelectRelativeToPlayhead(int offset)
    {
        if (segments.Count == 0) return;
        var playhead = activeId ?? SelectedSegmentId;
        var current = -1;
        if (playhead is ulong id) {
            for (var index = 0; index < segments.Count; index++) {
                if (segments[index].Id == id) { current = index; break; }
            }
        }
        if (current < 0) current = offset > 0 ? -1 : segments.Count;
        Select(segments[Math.Clamp(current + offset, 0, segments.Count - 1)].Id);
    }

    private void Draw(CanvasControl sender, CanvasDrawEventArgs args)
    {
        var ds = args.DrawingSession; var width = (float)sender.ActualWidth; var height = (float)sender.ActualHeight;
        var layout = TimelineViewport.Layout(height); var lyricTop = (float)(layout.Ruler + layout.Waveform + layout.Bands); var trackHeight = (float)layout.Waveform;
        ds.Clear(ColorHelper.FromArgb(0, 0, 0, 0));
        if (LoopStartMs is double loopStart && LoopEndMs is double loopEnd && loopEnd > loopStart) {
            var loopX0 = (float)Viewport.XAt(loopStart, width); var loopX1 = (float)Viewport.XAt(loopEnd, width);
            ds.FillRectangle(loopX0, 24, loopX1 - loopX0, height - 24, ColorHelper.FromArgb(26, 86, 138, 115));
            ds.DrawLine(loopX0, 24, loopX0, height, Colors.MediumSeaGreen, 2); ds.DrawLine(loopX1, 24, loopX1, height, Colors.Orange, 2);
        }
        DrawRuler(ds, width); DrawWaveform(ds, width, 24, trackHeight); DrawBands(ds, width, 24 + trackHeight, trackHeight);
        DrawLyrics(ds, width, lyricTop, height - lyricTop);
        ds.DrawLine(0, 24, width, 24, Colors.Gray, 1); ds.DrawLine(0, 24 + trackHeight, width, 24 + trackHeight, Colors.Gray, 1);
        ds.DrawLine(0, lyricTop, width, lyricTop, Colors.Gray, 1);
        if (Viewport.Selection is { } selection) {
            var x0 = (float)Viewport.XAt(selection.Start, width); var x1 = (float)Viewport.XAt(selection.End, width);
            ds.FillRectangle(x0, 24, x1 - x0, lyricTop - 24, ColorHelper.FromArgb(55, 50, 127, 159));
            ds.DrawRectangle(x0, 24, x1 - x0, lyricTop - 24, Colors.DodgerBlue, 1);
        }
        var playheadX = (float)Viewport.XAt(PlayheadMs, width);
        if (playheadX >= 0 && playheadX <= width) ds.DrawLine(playheadX, 0, playheadX, height, Colors.White, 1.5f);
    }

    private void DrawRuler(Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float width)
    {
        var raw = Viewport.VisibleDurationMs / Math.Max(2, width / 90); var magnitude = Math.Pow(10, Math.Floor(Math.Log10(raw)));
        var normalized = raw / magnitude; var interval = (normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10) * magnitude;
        var first = Math.Ceiling(Viewport.VisibleStartMs / interval) * interval;
        for (var time = first; time <= Viewport.VisibleEndMs; time += interval) {
            var x = (float)Viewport.XAt(time, width); ds.DrawLine(x, 17, x, 24, Colors.Gray, 1);
            ds.DrawText(FormatTime(time), x + 3, 2, Colors.Gray);
        }
    }

    private void DrawWaveform(Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float width, float top, float height)
    {
        ds.DrawText(WaveformLabel, 8, top + 5, Colors.Gray);
        if (waveform.Peak.Length == 0 || height <= 0) return;
        var center = top + height / 2; var start = VisibleBin(waveform.Peak.Length, Viewport.VisibleStartMs); var end = VisibleBin(waveform.Peak.Length, Viewport.VisibleEndMs) + 1;
        for (var index = start; index < Math.Min(end, waveform.Peak.Length); index++) {
            var time = index * Viewport.DurationMs / waveform.Peak.Length; var x = (float)Viewport.XAt(time, width);
            var amplitude = waveform.Peak[index] * height * .43f; ds.DrawLine(x, center - amplitude, x, center + amplitude, Colors.DeepSkyBlue, 1);
        }
    }

    private void DrawBands(Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float width, float top, float height)
    {
        ds.DrawText(BandLabel, 8, top + 5, Colors.Gray);
        DrawBand(ds, waveform.Low, width, top, height, Colors.MediumSeaGreen);
        DrawBand(ds, waveform.Mid, width, top, height, Colors.Goldenrod);
        DrawBand(ds, waveform.High, width, top, height, Colors.OrangeRed);
    }

    private void DrawBand(Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float[] values, float width, float top, float height, Windows.UI.Color color)
    {
        if (values.Length == 0 || height <= 0) return;
        var start = VisibleBin(values.Length, Viewport.VisibleStartMs); var end = Math.Min(values.Length, VisibleBin(values.Length, Viewport.VisibleEndMs) + 2);
        Vector2? previous = null;
        for (var index = start; index < end; index++) {
            var point = new Vector2((float)Viewport.XAt(index * Viewport.DurationMs / values.Length, width), top + height - 5 - values[index] * (height - 20));
            if (previous is { } p) ds.DrawLine(p, point, color, 1.2f); previous = point;
        }
    }

    private void DrawLyrics(Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float width, float top, float height)
    {
        ds.DrawText(LyricsLaneLabel, 8, top + 5, Colors.Gray);
        var timed = TimedSegments();
        for (var index = 0; index < timed.Count; index++) {
            var (segment, start) = timed[index]; var end = index + 1 < timed.Count ? timed[index + 1].Time : Viewport.DurationMs;
            if (end < Viewport.VisibleStartMs || start > Viewport.VisibleEndMs) continue;
            var x0 = (float)Viewport.XAt(start, width); var x1 = (float)Viewport.XAt(end, width);
            var color = segment.Id == SelectedSegmentId ? ColorHelper.FromArgb(120, 50, 127, 159)
                : segment.Id == activeId ? ColorHelper.FromArgb(70, 50, 127, 159)
                : segment.Timing.Final is not null ? ColorHelper.FromArgb(45, 50, 127, 159) : ColorHelper.FromArgb(20, 128, 128, 128);
            ds.FillRectangle(x0, top + 22, Math.Max(1, x1 - x0), height - 24, color);
            if (x1 - x0 > 42) ds.DrawText(segment.Text, x0 + 4, top + 29, Colors.White);
            if (segment.Timing.Gemini is { } gemini) {
                var markerX = (float)Viewport.XAt(gemini.TimeMs, width); ds.DrawLine(markerX, top + 18, markerX, top + 29, Colors.Goldenrod, 2);
            }
        }
    }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        Focus(FocusState.Pointer); var point = e.GetCurrentPoint(canvas); pointerId = e.Pointer.PointerId;
        pressedX = point.Position.X; dragging = false; Viewport.GestureActive = true; canvas.CapturePointer(e.Pointer); e.Handled = true;
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (pointerId != e.Pointer.PointerId) return; var x = e.GetCurrentPoint(canvas).Position.X;
        if (TimelineViewport.IsSelection(pressedX, x)) dragging = true;
        if (dragging) { Viewport.Selection = (Viewport.TimeAt(pressedX, canvas.ActualWidth), Viewport.TimeAt(x, canvas.ActualWidth)); canvas.Invalidate(); }
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (pointerId != e.Pointer.PointerId) return; var x = e.GetCurrentPoint(canvas).Position.X;
        canvas.ReleasePointerCapture(e.Pointer); pointerId = null; Viewport.GestureActive = false;
        if (dragging) Viewport.ZoomSelection(pressedX, x, canvas.ActualWidth); else SeekRequested?.Invoke(Viewport.TimeAt(x, canvas.ActualWidth));
        dragging = false; Viewport.Selection = null; CommitViewport(); e.Handled = true;
    }

    private void OnPointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        pointerId = null; dragging = false; Viewport.Selection = null; Viewport.GestureActive = false; canvas.Invalidate();
    }

    private void PointerWheel(object sender, PointerRoutedEventArgs e)
    {
        var point = e.GetCurrentPoint(canvas); var delta = point.Properties.MouseWheelDelta;
        Viewport.NoteUserInteraction();
        if (e.KeyModifiers.HasFlag(VirtualKeyModifiers.Control)) Viewport.ZoomAt(Math.Pow(1.0015, delta), Viewport.TimeAt(point.Position.X, canvas.ActualWidth));
        else Viewport.Pan(-delta / 120d * Viewport.VisibleDurationMs * .1);
        CommitViewport(); e.Handled = true;
    }

    private void OnManipulationDelta(object sender, ManipulationDeltaRoutedEventArgs e)
    {
        Viewport.ZoomAt(e.Delta.Scale, Viewport.TimeAt(e.Position.X, canvas.ActualWidth)); CommitViewport(); e.Handled = true;
    }

    private void HandleKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key is VirtualKey.Number1 or VirtualKey.Number2 or VirtualKey.Number3) { heldStep = e.Key == VirtualKey.Number1 ? 1 : e.Key == VirtualKey.Number2 ? 10 : 50; return; }
        if (e.Key is VirtualKey.Left or VirtualKey.Right) {
            var right = e.Key == VirtualKey.Right;
            if (heldStep > 0) NudgeRequested?.Invoke(TimelineViewport.NudgeDelta(heldStep, right));
            else SeekRequested?.Invoke(PlayheadMs + (right ? 1 : -1) * Viewport.SeekStep);
            e.Handled = true; return;
        }
        if (e.Key == VirtualKey.Tab) {
            var shift = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift).HasFlag(CoreVirtualKeyStates.Down);
            CommandRequested?.Invoke(shift ? "select_previous_playing" : "select_next_playing");
            e.Handled = true; return;
        }
        if (e.Key == VirtualKey.Home) { SeekRequested?.Invoke(0); e.Handled = true; return; }
        if (e.Key == VirtualKey.End) { SeekRequested?.Invoke(Viewport.DurationMs); e.Handled = true; return; }
        if ((int)e.Key is 188) { NudgeRequested?.Invoke(-1); e.Handled = true; return; }
        if ((int)e.Key is 190) { NudgeRequested?.Invoke(1); e.Handled = true; return; }
        var control = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down);
        var plus = e.Key is VirtualKey.Add || (int)e.Key == 187;
        var minus = e.Key is VirtualKey.Subtract || (int)e.Key == 189;
        if (plus || minus)
        {
            if (control)
            {
                Viewport.SetZoom(Viewport.Zoom * (plus ? 1.25 : .8), PlayheadMs);
                CommitViewport();
            }
            else CommandRequested?.Invoke(plus ? "rate_up" : "rate_down");
            e.Handled = true; return;
        }
        var command = e.Key switch {
            VirtualKey.Enter => "select_current", VirtualKey.Space => "play",
            VirtualKey.A => "loop_a", VirtualKey.B => "loop_b", VirtualKey.Escape => "loop_clear",
            VirtualKey.Down => "next", VirtualKey.Up => "previous",
            VirtualKey.M => "mark", VirtualKey.Delete or VirtualKey.Back => "clear_final",
            _ => null
        };
        if (command is not null) { CommandRequested?.Invoke(command); e.Handled = true; }
    }

    private void HandleKeyUp(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key is VirtualKey.Number1 or VirtualKey.Number2 or VirtualKey.Number3) heldStep = 0;
    }

    private void ScrollChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (changingScroll) return;
        Viewport.NoteUserInteraction();
        Viewport.SetStart(e.NewValue);
        canvas.Invalidate();
    }

    private void CommitViewport(bool invalidate = true)
    {
        changingScroll = true; scroll.Maximum = Math.Max(0, Viewport.DurationMs - Viewport.VisibleDurationMs);
        scroll.ViewportSize = Viewport.VisibleDurationMs; scroll.SmallChange = Viewport.VisibleDurationMs * .02;
        scroll.LargeChange = Viewport.VisibleDurationMs * .8; scroll.Value = Viewport.VisibleStartMs; changingScroll = false;
        ZoomChanged?.Invoke(Viewport.Zoom); if (invalidate) canvas.Invalidate();
    }

    private LyricSegment? SegmentAt(double timeMs)
    {
        LyricSegment? active = null;
        foreach (var (segment, time) in TimedSegments()) { if (time > timeMs) break; active = segment; }
        return active;
    }

    private List<(LyricSegment Segment, double Time)> TimedSegments() => segments
        .Select(s => (Segment: s, Point: s.Timing.Final ?? s.Timing.Gemini))
        .Where(value => value.Point is not null).Select(value => (value.Segment, (double)value.Point!.TimeMs))
        .OrderBy(value => value.Item2).ToList();
    private int VisibleBin(int count, double time) => (int)Math.Clamp(time / Viewport.DurationMs * count, 0, count - 1);
    private static string FormatTime(double ms) => $"{(long)ms / 60000:00}:{(long)ms / 1000 % 60:00}.{(long)ms % 1000:000}";
}
