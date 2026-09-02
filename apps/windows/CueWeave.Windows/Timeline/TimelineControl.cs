using System.Numerics;
using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;
using Microsoft.Graphics.Canvas.Text;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.System;
using Windows.UI.Core;

namespace CueWeave.WinUI.Timeline;

public sealed partial class TimelineControl : UserControl
{
    private CanvasControl? canvas;
    private readonly ScrollBar scroll = new() { Orientation = Orientation.Horizontal, Height = 12, VerticalAlignment = VerticalAlignment.Bottom };
    private IReadOnlyList<LyricSegment> segments = [];
    private IReadOnlyList<(ulong Id, ulong TimeMs, string Text)> credits = [];
    private WaveformData waveform = WaveformData.Empty;
    private bool changingScroll;
    private uint? pointerId;
    private double pressedX;
    private bool dragging;
    private ulong? creditDragId;
    private bool creditDidMove;
    private int heldStep;
    private ulong? activeId;

    private readonly ComboBox upperLanePicker = MakeLanePicker();
    private readonly ComboBox lowerLanePicker = MakeLanePicker();
    private readonly TextBlock timeLaneLabel = new() { FontSize = 10, Padding = new Thickness(8, 6, 0, 0), FontFamily = new FontFamily("Consolas") };
    private readonly TextBlock lyricsLaneTitle = new() { FontSize = 10, FontWeight = FontWeights.SemiBold, FontFamily = new FontFamily("Consolas") };
    private readonly TextBlock lyricsLaneDetail = new() { FontSize = 10, Opacity = .55, FontFamily = new FontFamily("Consolas") };
    private readonly StackPanel lyricsLaneCaption = new() { Padding = new Thickness(8, 8, 0, 0), Spacing = 3 };

    public TimelineViewport Viewport { get; } = new();
    public double PlayheadMs { get; private set; }
    public ulong? ActiveSegmentId => activeId;
    public ulong? SelectedSegmentId { get; private set; }
    public ulong? SelectedCreditId { get; private set; }
    public string UpperLane { get; private set; } = "peak";
    public string LowerLane { get; private set; } = "bands";
    public string[] NeededScales =>
        new[] { ScaleOf(UpperLane), ScaleOf(LowerLane) }.OfType<string>().Distinct().ToArray();
    public bool NeedsSpectrogram => NeededScales.Length > 0;
    public double? LoopStartMs { get; set; }
    public double? LoopEndMs { get; set; }

    public event Action<double>? SeekRequested;
    public event Action<long>? NudgeRequested;
    public event Action<string>? CommandRequested;
    public event Action<ulong?>? ActiveSegmentChanged;
    public event Action<ulong?>? SelectedSegmentChanged;
    public event Action<double>? ZoomChanged;
    public event Action? VisualizationChanged;
    public event Action? CreditDragStarted;
    public event Action<ulong, double>? CreditMoved;
    public event Action? CreditDragEnded;

    public TimelineControl()
    {
        IsTabStop = true;
        var labels = new Grid();
        labels.RowDefinitions.Add(new RowDefinition { Height = new GridLength(24) });
        labels.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        labels.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        labels.RowDefinitions.Add(new RowDefinition { Height = new GridLength(72) });
        labels.RowDefinitions.Add(new RowDefinition { Height = new GridLength(12) });
        lyricsLaneCaption.Children.Add(lyricsLaneTitle); lyricsLaneCaption.Children.Add(lyricsLaneDetail);
        Grid.SetRow(timeLaneLabel, 0); Grid.SetRow(upperLanePicker, 1);
        Grid.SetRow(lowerLanePicker, 2); Grid.SetRow(lyricsLaneCaption, 3);
        labels.Children.Add(timeLaneLabel); labels.Children.Add(upperLanePicker);
        labels.Children.Add(lowerLanePicker); labels.Children.Add(lyricsLaneCaption);
        var plot = new Grid();
        plot.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        plot.RowDefinitions.Add(new RowDefinition { Height = new GridLength(12) });
        Grid.SetRow(scroll, 1); plot.Children.Add(scroll);
        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(108) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(labels); Grid.SetColumn(plot, 1); root.Children.Add(plot);
        Content = root;
        upperLanePicker.SelectedIndex = 0; lowerLanePicker.SelectedIndex = 3;
        upperLanePicker.SelectionChanged += LaneChanged; lowerLanePicker.SelectionChanged += LaneChanged;
        scroll.ValueChanged += ScrollChanged;
        KeyDown += HandleKeyDown; KeyUp += HandleKeyUp;
        Loaded += (_, _) => AttachCanvas(plot);
    }

    private void AttachCanvas(Grid plot)
    {
        if (canvas is not null) return;
        var view = new CanvasControl { ManipulationMode = ManipulationModes.Scale };
        view.Draw += Draw;
        view.PointerPressed += OnPointerPressed; view.PointerMoved += OnPointerMoved;
        view.PointerReleased += OnPointerReleased; view.PointerCaptureLost += OnPointerCaptureLost;
        view.PointerWheelChanged += PointerWheel;
        view.ManipulationStarted += (_, _) => Viewport.GestureActive = true;
        view.ManipulationDelta += OnManipulationDelta;
        view.ManipulationCompleted += (_, _) => { Viewport.GestureActive = false; CommitViewport(); };
        Grid.SetRow(view, 0); plot.Children.Insert(0, view);
        canvas = view;
        CommitViewport();
    }

    public void SetDocument(double durationMs, IReadOnlyList<LyricSegment> values)
    {
        segments = values; Viewport.SetDocument(durationMs); SelectedSegmentId = null; activeId = null;
        CommitViewport(); canvas?.Invalidate();
    }

    public WaveformData CurrentWaveform => waveform;

    public void SetWaveform(WaveformData value) { waveform = value; canvas?.Invalidate(); }
    public void SetSegments(IReadOnlyList<LyricSegment> values) { segments = values; canvas?.Invalidate(); }
    public void LocalizeLanes(Func<string, string> text)
    {
        timeLaneLabel.Text = text("lane.time");
        lyricsLaneTitle.Text = text("lane.lyrics");
        lyricsLaneDetail.Text = text("lane.timestamps");
        foreach (var box in new[] { upperLanePicker, lowerLanePicker })
            foreach (ComboBoxItem item in box.Items)
                if (item.Tag is string tag) item.Content = text("audio." + tag);
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

    public void SetCredits(IReadOnlyList<(ulong Id, ulong TimeMs, string Text)> values)
    {
        credits = values;
        canvas?.Invalidate();
    }

    public void Select(ulong? id)
    {
        SelectedSegmentId = id; SelectedCreditId = null; SelectedSegmentChanged?.Invoke(id); canvas?.Invalidate();
    }

    public void SelectCredit(ulong? id)
    {
        SelectedCreditId = id; SelectedSegmentId = null; SelectedSegmentChanged?.Invoke(null); canvas?.Invalidate();
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
        DrawRuler(ds, width);
        DrawLane(UpperLane, ds, width, 24, trackHeight);
        DrawLane(LowerLane, ds, width, 24 + trackHeight, trackHeight);
        DrawLyricLane(ds, width, lyricTop, (float)layout.Lyrics);
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

    private void DrawLane(string kind, Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float width, float top, float height)
    {
        if (AudioVizCatalog.Find(kind) is not { } adapter) return;
        switch (adapter.Surface)
        {
            case "waveform":
                DrawWaveform(ds, width, top, height, adapter.Series);
                break;
            case "bands":
                DrawBands(ds, width, top, height);
                break;
            case "spectrogram":
                if (adapter.Scale is string scale) DrawSpectrogram(ds, width, top, height, scale);
                break;
        }
    }

    private void DrawWaveform(Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float width, float top, float height, string[] series)
    {
        var peak = series.Contains("peak");
        var rms = series.Contains("rms");
        if (!peak && !rms) return;
        var mode = peak && rms ? "peakRms" : rms ? "rms" : "peak";
        if (waveform.Peak.Length == 0 || height <= 0) return;
        var center = top + height / 2; var start = VisibleBin(waveform.Peak.Length, Viewport.VisibleStartMs); var end = VisibleBin(waveform.Peak.Length, Viewport.VisibleEndMs) + 1;
        for (var index = start; index < Math.Min(end, waveform.Peak.Length); index++) {
            var time = index * Viewport.DurationMs / waveform.Peak.Length; var x = (float)Viewport.XAt(time, width);
            var amplitude = (mode is "rms" && waveform.Rms.Length > index ? waveform.Rms[index] : waveform.Peak[index]) * height * .43f;
            ds.DrawLine(x, center - amplitude, x, center + amplitude, Colors.DeepSkyBlue, 1);
            if (mode is "peakRms" && waveform.Rms.Length > index) {
                var rmsAmp = waveform.Rms[index] * height * .43f;
                ds.DrawLine(x, center - rmsAmp, x, center + rmsAmp, Colors.White, 1);
            }
        }
    }

    private void DrawBands(Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float width, float top, float height)
    {
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

    private void DrawLyricLane(Microsoft.Graphics.Canvas.CanvasDrawingSession ds, float width, float top, float height)
    {
        if (height <= 0 || width <= 0) return;
        ds.FillRectangle(0, top, width, height, ColorHelper.FromArgb(22, 255, 255, 255));
        using var layer = ds.CreateLayer(1, new Rect(0, top, width, height));
        using var idFormat = new CanvasTextFormat { FontSize = 11, FontFamily = "Consolas", WordWrapping = CanvasWordWrapping.NoWrap };
        using var markFormat = new CanvasTextFormat { FontSize = 10, FontFamily = "Consolas", FontWeight = FontWeights.SemiBold };
        var timed = TimedSegments();
        for (var index = 0; index < timed.Count; index++) {
            var (segment, start) = timed[index]; var end = index + 1 < timed.Count ? timed[index + 1].Time : Viewport.DurationMs;
            if (end < Viewport.VisibleStartMs || start > Viewport.VisibleEndMs) continue;
            var x0 = (float)Viewport.XAt(start, width); var x1 = (float)Viewport.XAt(end, width);
            var span = Math.Max(2, x1 - x0);
            var fill = segment.Id == SelectedSegmentId ? ColorHelper.FromArgb(120, 50, 127, 159)
                : segment.Id == activeId ? ColorHelper.FromArgb(70, 50, 127, 159)
                : segment.Timing.Final is not null ? ColorHelper.FromArgb(28, 212, 168, 83) : ColorHelper.FromArgb(18, 128, 128, 128);
            var stroke = segment.Id == SelectedSegmentId ? ColorHelper.FromArgb(180, 50, 127, 159)
                : segment.Id == activeId ? ColorHelper.FromArgb(120, 50, 127, 159)
                : ColorHelper.FromArgb(40, 128, 128, 128);
            ds.FillRectangle(x0, top, span, height, fill);
            ds.DrawRectangle(x0, top, span, height, stroke, 1);
            if (span > 42) ds.DrawText($"{segment.Id:D4}", new Rect(x0 + 4, top + 4, span - 8, 16), Colors.White, idFormat);
            if (segment.Timing.Gemini is { } gemini) {
                var gx = (float)Viewport.XAt(gemini.TimeMs, width);
                ds.DrawText("G", gx - 5, top + 2, Colors.Goldenrod, markFormat);
                ds.DrawLine(gx, top + 14, gx, top + 28, Colors.Goldenrod, 1);
            }
        }
        foreach (var credit in credits)
        {
            var x = (float)Viewport.XAt(credit.TimeMs, width);
            var color = credit.Id == SelectedCreditId ? Colors.DeepSkyBlue : ColorHelper.FromArgb(180, 50, 127, 159);
            ds.DrawText("C", x + 6, top + 2, color, markFormat);
            ds.FillCircle(x, top + 22, 4.5f, color);
            ds.DrawLine(x, top + 28, x, top + height - 6, color, 1);
        }
    }

    private void OnPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (canvas is null) return;
        Focus(FocusState.Pointer); var point = e.GetCurrentPoint(canvas); pointerId = e.Pointer.PointerId;
        pressedX = point.Position.X; dragging = false; creditDidMove = false;
        creditDragId = HitCreditAt(point.Position.X, point.Position.Y, canvas.ActualWidth, canvas.ActualHeight);
        if (creditDragId is ulong creditId) SelectCredit(creditId);
        Viewport.GestureActive = true; canvas.CapturePointer(e.Pointer); e.Handled = true;
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (canvas is null || pointerId != e.Pointer.PointerId) return; var x = e.GetCurrentPoint(canvas).Position.X;
        if (creditDragId is ulong creditId)
        {
            if (!creditDidMove && TimelineViewport.IsSelection(pressedX, x))
            {
                creditDidMove = true;
                CreditDragStarted?.Invoke();
            }
            if (creditDidMove)
            {
                var time = Math.Max(0, Viewport.TimeAt(x, canvas.ActualWidth));
                PreviewCreditTime(creditId, (ulong)Math.Round(time));
                CreditMoved?.Invoke(creditId, time);
                canvas.Invalidate();
            }
            return;
        }
        if (TimelineViewport.IsSelection(pressedX, x)) dragging = true;
        if (dragging) { Viewport.Selection = (Viewport.TimeAt(pressedX, canvas.ActualWidth), Viewport.TimeAt(x, canvas.ActualWidth)); canvas?.Invalidate(); }
    }

    private void OnPointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (canvas is null || pointerId != e.Pointer.PointerId) return; var x = e.GetCurrentPoint(canvas).Position.X;
        canvas.ReleasePointerCapture(e.Pointer); pointerId = null; Viewport.GestureActive = false;
        if (creditDragId is ulong creditId)
        {
            if (creditDidMove)
            {
                CreditMoved?.Invoke(creditId, Viewport.TimeAt(x, canvas.ActualWidth));
                CreditDragEnded?.Invoke();
            }
            creditDragId = null; creditDidMove = false; dragging = false; Viewport.Selection = null;
            CommitViewport(); e.Handled = true; return;
        }
        if (dragging) Viewport.ZoomSelection(pressedX, x, canvas.ActualWidth);
        else if (HitCredit(Viewport.TimeAt(x, canvas.ActualWidth)) is ulong hit) SelectCredit(hit);
        else { SelectCredit(null); SeekRequested?.Invoke(Viewport.TimeAt(x, canvas.ActualWidth)); }
        dragging = false; Viewport.Selection = null; CommitViewport(); e.Handled = true;
    }

    private void OnPointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        if (creditDidMove) CreditDragEnded?.Invoke();
        pointerId = null; dragging = false; creditDragId = null; creditDidMove = false;
        Viewport.Selection = null; Viewport.GestureActive = false; canvas?.Invalidate();
    }

    private void PointerWheel(object sender, PointerRoutedEventArgs e)
    {
        if (canvas is null) return;
        var point = e.GetCurrentPoint(canvas); var delta = point.Properties.MouseWheelDelta;
        Viewport.NoteUserInteraction();
        if (e.KeyModifiers.HasFlag(VirtualKeyModifiers.Control)) Viewport.ZoomAt(Math.Pow(1.0015, delta), Viewport.TimeAt(point.Position.X, canvas.ActualWidth));
        else Viewport.Pan(-delta / 120d * Viewport.VisibleDurationMs * .1);
        CommitViewport(); e.Handled = true;
    }

    private void OnManipulationDelta(object sender, ManipulationDeltaRoutedEventArgs e)
    {
        if (canvas is null) return;
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
            VirtualKey.Enter => "select_current",
            VirtualKey.A => "loop_a", VirtualKey.B => "loop_b", VirtualKey.Escape => "loop_clear",
            VirtualKey.Down => "next", VirtualKey.Up => "previous",
            VirtualKey.M => "mark", VirtualKey.N when !control => "toggle_follow_next",
            VirtualKey.Delete or VirtualKey.Back => "clear_final",
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
        canvas?.Invalidate();
    }

    private void CommitViewport(bool invalidate = true)
    {
        changingScroll = true; scroll.Maximum = Math.Max(0, Viewport.DurationMs - Viewport.VisibleDurationMs);
        scroll.ViewportSize = Viewport.VisibleDurationMs; scroll.SmallChange = Viewport.VisibleDurationMs * .02;
        scroll.LargeChange = Viewport.VisibleDurationMs * .8; scroll.Value = Viewport.VisibleStartMs; changingScroll = false;
        ZoomChanged?.Invoke(Viewport.Zoom); if (invalidate) canvas?.Invalidate();
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

    private void DrawSpectrogram(
        Microsoft.Graphics.Canvas.CanvasDrawingSession ds,
        float width,
        float top,
        float height,
        string scale)
    {
        if (!waveform.Spectrograms.TryGetValue(scale, out var frame)
            || frame.Values.Length == 0 || frame.TimeBins == 0 || frame.FrequencyBins == 0) return;
        var start = (double)frame.StartMs;
        var end = frame.EndMs > frame.StartMs ? frame.EndMs : Viewport.DurationMs;
        var span = Math.Max(1, end - start);
        var timeStride = Math.Max(1, frame.TimeBins / Math.Max(1, (int)width));
        var freqStride = Math.Max(1, frame.FrequencyBins / Math.Max(1, (int)height));
        for (var time = 0; time < frame.TimeBins; time += timeStride)
        {
            var x = (float)Viewport.XAt(start + span * time / frame.TimeBins, width);
            var next = (float)Viewport.XAt(start + span * Math.Min(frame.TimeBins, time + timeStride) / frame.TimeBins, width);
            var cellW = Math.Max(1, next - x);
            if (x + cellW < 0 || x > width) continue;
            for (var freq = 0; freq < frame.FrequencyBins; freq += freqStride)
            {
                var index = time * frame.FrequencyBins + freq;
                if (index >= frame.Values.Length) continue;
                var value = frame.Values[index];
                if (value < 12) continue;
                var y = top + (frame.FrequencyBins - 1 - freq) * height / frame.FrequencyBins;
                var cellH = Math.Max(1, height * freqStride / frame.FrequencyBins);
                ds.FillRectangle(x, y, cellW, cellH, ColorHelper.FromArgb((byte)(40 + value * 180 / 255), 50, 127, 159));
            }
        }
    }

    private void LaneChanged(object sender, SelectionChangedEventArgs e)
    {
        UpperLane = TagOf(upperLanePicker) ?? "peak";
        LowerLane = TagOf(lowerLanePicker) ?? "bands";
        VisualizationChanged?.Invoke();
        canvas?.Invalidate();
    }

    private static ComboBox MakeLanePicker()
    {
        var box = new ComboBox { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 6, 0), FontSize = 11 };
        foreach (var adapter in AudioVizCatalog.All)
            box.Items.Add(new ComboBoxItem { Content = adapter.Id, Tag = adapter.Id });
        return box;
    }

    private static string? TagOf(ComboBox box) => (box.SelectedItem as ComboBoxItem)?.Tag as string;
    private static string? ScaleOf(string kind) => AudioVizCatalog.Find(kind)?.Scale;
    private int VisibleBin(int count, double timeMs)
    {
        if (count <= 0 || Viewport.DurationMs <= 0) return 0;
        return (int)Math.Clamp(Math.Floor(timeMs / Viewport.DurationMs * count), 0, count - 1);
    }
    private ulong? HitCredit(double timeMs)
    {
        if (credits.Count == 0) return null;
        var nearest = credits.MinBy(credit => Math.Abs((double)credit.TimeMs - timeMs));
        return Math.Abs((double)nearest.TimeMs - timeMs) <= 120 ? nearest.Id : null;
    }

    private void PreviewCreditTime(ulong id, ulong timeMs)
    {
        credits = [.. credits.Select(credit => credit.Id == id ? (credit.Id, timeMs, credit.Text) : credit)];
    }

    private ulong? HitCreditAt(double x, double y, double width, double height)
    {
        if (credits.Count == 0 || width <= 0 || height <= 0) return null;
        var layout = TimelineViewport.Layout(height);
        if (y < layout.Ruler + layout.Waveform + layout.Bands - 6) return null;
        ulong? best = null;
        var bestDist = 14.0;
        foreach (var credit in credits)
        {
            var dist = Math.Abs(Viewport.XAt(credit.TimeMs, width) - x);
            if (dist < bestDist) { bestDist = dist; best = credit.Id; }
        }
        return best;
    }
    private static string FormatTime(double ms) => $"{(long)ms / 60000:00}:{(long)ms / 1000 % 60:00}.{(long)ms % 1000:000}";
}
