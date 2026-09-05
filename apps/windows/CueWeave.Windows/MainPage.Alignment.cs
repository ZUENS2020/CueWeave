using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using System.Globalization;
using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;
using CueWeave.WinUI.Timeline;

namespace CueWeave.WinUI;

public sealed class SegmentRow
{
    public ulong Id { get; set; }
    public string IdText { get; set; } = "";
    public string Text { get; set; } = "";
    public string Time { get; set; } = "";
    public bool Included { get; set; }
}

public sealed partial class MainPage
{
    private async void Align_Click(object sender, RoutedEventArgs e)
    {
        var provider = settings.AlignmentProvider;
        var key = provider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        var model = provider == "openrouter" ? settings.OpenRouterModel : settings.AiStudioModel;
        if (string.IsNullOrWhiteSpace(key)) { await ShowErrorAsync(L10n.T("error.needApiKey")); return; }
        await RunAsync(L10n.T("activity.aligningAll"), token => session.RunProjectCommandAsync("align", new System.Text.Json.Nodes.JsonObject {
            ["provider"] = provider, ["api_key"] = key, ["model"] = model, ["segment_ids"] = new System.Text.Json.Nodes.JsonArray()
        }, token));
    }

    private async void RestoreGemini_Click(object sender, RoutedEventArgs e) =>
        await RunAsync(L10n.T("activity.restoringGemini"), token => session.RunProjectCommandAsync("restore_gemini", null, token));

    private void BindAlignment(ProjectDocument project)
    {
        var segments = project.Segments;
        AlignmentEmpty.Visibility = VisibleIf(segments.Count == 0);
        AlignmentBody.Visibility = VisibleIf(segments.Count > 0);
        SegmentCount.Text = segments.Count.ToString();
        batchIds.IntersectWith(segments.Select(segment => segment.Id));
        AlignmentList.ItemsSource = segments.Select(segment => new SegmentRow
        {
            Id = segment.Id,
            IdText = segment.Id.ToString("0000"),
            Text = segment.Text,
            Time = FormatTime((segment.Timing.Final ?? segment.Timing.Gemini)?.TimeMs),
            Included = batchIds.Contains(segment.Id)
        }).ToList();
        paintedActive = null;
        paintedSelected = null;
        CreditsSectionLabel.Visibility = VisibleIf(project.Lyrics.Credits.Count > 0);
        LyricsSectionLabel.Visibility = VisibleIf(project.Lyrics.Credits.Count > 0);
        var providerName = settings.AlignmentProvider == "openrouter" ? "OpenRouter" : "AI Studio";
        AlignButton.Content = $"{providerName} · {L10n.T("align.all")}";
        AlignButton.IsEnabled = segments.Count > 0 && (settings.AlignmentProvider == "openrouter"
            ? settings.OpenRouterApiKey.Length > 0
            : settings.AiStudioApiKey.Length > 0);
        RestoreButton.IsEnabled = segments.Exists(segment => segment.Timing.Gemini is not null);
        UpdateBatchChrome();
        UpdateQueueVisuals(Timeline.ActiveSegmentId);
    }

    private void Speed_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (SpeedPicker.SelectedItem is ComboBoxItem item && double.TryParse(item.Tag?.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var rate)) playback.SetRate(rate);
    }

    private void LoopA_Click(object sender, RoutedEventArgs e) { playback.MarkA(); SyncLoop(); }
    private void LoopB_Click(object sender, RoutedEventArgs e) { playback.MarkB(); SyncLoop(); }
    private void LoopClear_Click(object sender, RoutedEventArgs e) { playback.ClearLoop(); SyncLoop(); }
    private void Follow_Changed(object sender, RoutedEventArgs e) => Timeline.SetFollow(FollowButton.IsChecked == true);
    private void Next_Changed(object sender, RoutedEventArgs e)
    {
        if (NextButton.IsChecked == true)
        {
            if (CurrentButton.IsChecked == true) CurrentButton.IsChecked = false;
            FollowNextIfNeeded(Timeline.ActiveSegmentId);
        }
    }
    private void Current_Changed(object sender, RoutedEventArgs e)
    {
        if (CurrentButton.IsChecked == true)
        {
            if (NextButton.IsChecked == true) NextButton.IsChecked = false;
            FollowCurrentIfNeeded(Timeline.ActiveSegmentId);
        }
    }
    private void Zoom_Changed(object sender, RangeBaseValueChangedEventArgs e) { if (!changingZoom) Timeline.SetZoom(e.NewValue); }

    private void Mark_Click(object sender, RoutedEventArgs e)
    {
        if (Timeline.SelectedCreditId is ulong creditId)
        {
            session.SetCreditTime(creditId, (ulong)Math.Max(0, Math.Round(playback.PositionMs)));
            return;
        }
        if (Timeline.SelectedSegmentId is ulong id) session.SetFinal(id, (long)Math.Round(playback.PositionMs));
    }

    private void Nudge_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string tag } && long.TryParse(tag, out var delta)) NudgeSelected(delta);
    }

    private void NudgeSelected(long delta)
    {
        if (Timeline.SelectedCreditId is ulong creditId)
        {
            if (session.Project is null) return;
            var time = CreditTime(session.Project, creditId);
            session.SetCreditTime(creditId, (ulong)Math.Max(0, (long)time + delta));
            return;
        }
        if (Timeline.SelectedSegmentId is not ulong id) return;
        var segment = session.Project?.Segments.FirstOrDefault(value => value.Id == id);
        if (segment is null) return;
        var baseline = (long)(segment.Timing.Final?.TimeMs
            ?? segment.Timing.Gemini?.TimeMs
            ?? (ulong)Math.Max(0, Math.Round(playback.PositionMs)));
        session.SetFinal(id, baseline + delta);
    }

    private void PlayAround_Click(object sender, RoutedEventArgs e)
    {
        var time = SelectedSegment()?.Timing.Final?.TimeMs ?? SelectedSegment()?.Timing.Gemini?.TimeMs;
        if (time is null) return;
        playback.Seek(Math.Max(0, (long)time - 2_000)); if (!playback.IsTransportActive) playback.Play(); playRequested = true; UpdateRendering();
    }

    private void UseGemini_Click(object sender, RoutedEventArgs e) { if (Timeline.SelectedSegmentId is ulong id) session.UseGemini(id); }
    private void ClearFinal_Click(object sender, RoutedEventArgs e) { if (Timeline.SelectedSegmentId is ulong id) session.ClearFinal(id); }

    private void AlignmentList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is SegmentRow row)
        {
            ClearFollowSelection();
            Timeline.Select(row.Id);
        }
    }

    private void SegmentInclude_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox { DataContext: SegmentRow row } box) return;
        if (box.IsChecked == true) batchIds.Add(row.Id);
        else batchIds.Remove(row.Id);
        row.Included = box.IsChecked == true;
        UpdateBatchChrome();
    }

    private void AlignmentList_ContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue) { args.ItemContainer.Background = null; return; }
        if (args.Item is not SegmentRow row) return;
        if (FirstCheckBox(args.ItemContainer) is CheckBox box) box.IsChecked = row.Included;
        args.ItemContainer.Background = row.Id == Timeline.SelectedSegmentId ? selectedFill
            : row.Id == Timeline.ActiveSegmentId ? playingFill : null;
    }

    private static CheckBox? FirstCheckBox(DependencyObject root)
    {
        if (root is CheckBox box) return box;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
            if (FirstCheckBox(VisualTreeHelper.GetChild(root, index)) is CheckBox found) return found;
        return null;
    }

    private void BatchAll_Click(object sender, RoutedEventArgs e)
    {
        if (session.Project is null) return;
        batchIds.UnionWith(session.Project.Segments.Select(segment => segment.Id));
        BindAlignment(session.Project);
    }

    private void BatchClear_Click(object sender, RoutedEventArgs e)
    {
        batchIds.Clear();
        if (session.Project is not null) BindAlignment(session.Project);
    }

    private void BatchClearFinal_Click(object sender, RoutedEventArgs e) => session.ClearFinals(batchIds);

    private void UpdateBatchChrome()
    {
        BatchSelectedText.Text = L10n.T("align.selected", batchIds.Count.ToString());
        BatchClearButton.IsEnabled = batchIds.Count > 0;
        BatchClearFinalButton.IsEnabled = batchIds.Count > 0;
    }

    private void HandleTimelineCommand(string command)
    {
        switch (command)
        {
            case "select_current": ClearFollowSelection(); Timeline.SelectCurrent(); break;
            case "select_next_playing":
                if (CurrentButton.IsChecked == true) SetFollowCurrentSelection(false);
                if (!TimelineViewport.KeepsFollowSelection(1)) SetFollowSelection(false);
                Timeline.SelectRelativeToPlayhead(1); break;
            case "select_previous_playing": ClearFollowSelection(); Timeline.SelectRelativeToPlayhead(-1); break;
            case "play": Play_Click(this, new RoutedEventArgs()); break;
            case "loop_a": playback.MarkA(); SyncLoop(); break;
            case "loop_b": playback.MarkB(); SyncLoop(); break;
            case "loop_clear": playback.ClearLoop(); SyncLoop(); break;
            case "next": ClearFollowSelection(); NavigateSegment(1); break;
            case "previous": ClearFollowSelection(); NavigateSegment(-1); break;
            case "mark": Mark_Click(this, new RoutedEventArgs()); break;
            case "toggle_follow_next": SetFollowSelection(NextButton.IsChecked != true); break;
            case "toggle_follow_current": SetFollowCurrentSelection(CurrentButton.IsChecked != true); break;
            case "clear_final": ClearFinal_Click(this, new RoutedEventArgs()); break;
            case "rate_up": AdjustRate(1); break;
            case "rate_down": AdjustRate(-1); break;
        }
    }

    private void NavigateSegment(int delta)
    {
        var segments = session.Project?.Segments; if (segments is null || segments.Count == 0) return;
        var current = Timeline.SelectedSegmentId ?? Timeline.ActiveSegmentId;
        var index = current is null ? (delta > 0 ? -1 : segments.Count) : segments.FindIndex(segment => segment.Id == current);
        Timeline.Select(segments[Math.Clamp(index + delta, 0, segments.Count - 1)].Id);
    }

    private void SyncLoop()
    {
        Timeline.LoopStartMs = playback.LoopStartMs; Timeline.LoopEndMs = playback.LoopEndMs; Timeline.Tick(playback.PositionMs);
        UpdatePlaybackFrame();
    }

    private void RefreshInspector()
    {
        var creditId = Timeline.SelectedCreditId;
        var segment = SelectedSegment();
        InspectorEmpty.Visibility = VisibleIf(creditId is null && segment is null);
        InspectorCredit.Visibility = VisibleIf(creditId is not null);
        InspectorSegment.Visibility = VisibleIf(segment is not null);
        if (creditId is ulong id && session.Project is { } project)
        {
            var credit = project.Lyrics.Credits.FirstOrDefault(value => value.Id == id);
            CreditInspectorText.Text = credit?.DisplayText ?? "";
            CreditInspectorTime.Text = FormatTime(CreditTime(project, id));
            return;
        }
        InspectorLabel.Text = segment is null ? L10n.T("inspect.emptyTitle") : L10n.T("inspect.segment", segment.Id.ToString("0000"));
        InspectorText.Text = segment?.Text ?? "";
        var line = segment is null ? null : session.Project?.Lyrics.Lines.FirstOrDefault(value => value.Segments.Any(item => item.Id == segment.Id));
        InspectorTranslation.Text = line?.Translation ?? "";
        InspectorTranslation.Visibility = VisibleIf(!string.IsNullOrWhiteSpace(line?.Translation));
        GeminiTime.Text = FormatTime(segment?.Timing.Gemini?.TimeMs);
        FinalTime.Text = FormatTime(segment?.Timing.Final?.TimeMs);
        GeminiConfidence.Text = FormatConfidence(segment?.Timing.Gemini?.Confidence);
        FinalConfidence.Text = FormatConfidence(segment?.Timing.Final?.Confidence);
        SetDraft(InspectorLyricBox, line?.Original ?? "");
        UseGeminiButton.IsEnabled = segment?.Timing.Gemini is not null;
        InspectorClearFinal.IsEnabled = segment?.Timing.Final is not null;
    }

    private void InspectorLyric_LostFocus(object sender, RoutedEventArgs e)
    {
        if (refreshing || Timeline.SelectedSegmentId is not ulong segmentId) return;
        var line = session.Project?.Lyrics.Lines.FirstOrDefault(value => value.Segments.Any(item => item.Id == segmentId));
        if (line is not null) session.SetLineOriginal(line.Id, InspectorLyricBox.Text);
    }

    private LyricSegment? SelectedSegment() => Timeline.SelectedSegmentId is ulong id
        ? session.Project?.Segments.FirstOrDefault(segment => segment.Id == id) : null;

    private Brush? selectedFill;
    private Brush? playingFill;
    private ulong? paintedActive;
    private ulong? paintedSelected;

    private void UpdateQueueVisuals(ulong? active)
    {
        if (AlignmentList.ItemsSource is not IList<SegmentRow> rows) return;
        selectedFill ??= new SolidColorBrush(Microsoft.UI.ColorHelper.FromArgb(70, 56, 110, 140));
        playingFill ??= new SolidColorBrush(Microsoft.UI.ColorHelper.FromArgb(36, 56, 110, 140));
        var selected = Timeline.SelectedSegmentId;
        if (paintedActive == active && paintedSelected == selected) return;
        PaintRow(rows, paintedActive, null, null);
        if (paintedSelected != paintedActive) PaintRow(rows, paintedSelected, null, null);
        paintedActive = active;
        paintedSelected = selected;
        PaintRow(rows, active, selected, active);
        if (selected != active) PaintRow(rows, selected, selected, active);
    }

    private void PaintRow(IList<SegmentRow> rows, ulong? id, ulong? selected, ulong? active)
    {
        if (id is not ulong value) return;
        for (var index = 0; index < rows.Count; index++)
        {
            if (rows[index].Id != value) continue;
            if (AlignmentList.ContainerFromIndex(index) is not ListViewItem item) return;
            item.Background = value == selected ? selectedFill : value == active ? playingFill : null;
            return;
        }
    }

    private void AdjustRate(int direction)
    {
        var rate = TimelineViewport.SteppedRate(playback.Rate, direction);
        playback.SetRate(rate);
        for (var index = 0; index < SpeedPicker.Items.Count; index++)
        {
            if (SpeedPicker.Items[index] is ComboBoxItem item &&
                double.TryParse(item.Tag?.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var value) &&
                Math.Abs(value - rate) < 0.01)
            {
                SpeedPicker.SelectedIndex = index;
                return;
            }
        }
    }

    private void FollowNextIfNeeded(ulong? activeId)
    {
        if (NextButton.IsChecked != true || session.Project is null) return;
        var follow = TimelineViewport.FollowingSegmentId(activeId, session.Project.Segments.Select(segment => segment.Id).ToList());
        if (follow is ulong next && Timeline.SelectedSegmentId != next) Timeline.Select(next);
    }

    private void SetFollowSelection(bool on)
    {
        if (on && CurrentButton.IsChecked == true) CurrentButton.IsChecked = false;
        if (NextButton.IsChecked != on) NextButton.IsChecked = on;
    }

    private void FollowCurrentIfNeeded(ulong? activeId)
    {
        if (CurrentButton.IsChecked != true) return;
        if (Timeline.SelectedSegmentId != activeId || Timeline.SelectedCreditId is not null) Timeline.Select(activeId);
    }

    private void SetFollowCurrentSelection(bool on)
    {
        if (on && NextButton.IsChecked == true) NextButton.IsChecked = false;
        if (CurrentButton.IsChecked != on) CurrentButton.IsChecked = on;
    }

    private void ClearFollowSelection()
    {
        SetFollowSelection(false);
        SetFollowCurrentSelection(false);
    }

    private void ScrollToSegment(ulong id)
    {
        if (AlignmentList.ItemsSource is not IList<SegmentRow> rows) return;
        var index = -1;
        for (var i = 0; i < rows.Count; i++) if (rows[i].Id == id) { index = i; break; }
        if (index < 0) return;
        // ScrollIntoView virtualizes safely; ContainerFromIndex is null for offscreen lyrics.
        AlignmentList.ScrollIntoView(rows[index], ScrollIntoViewAlignment.Default);
    }

    private static string FormatConfidence(float? value) => value is float number ? number.ToString("0.00") : "—";
}
