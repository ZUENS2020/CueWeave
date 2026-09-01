using System.Text.Json.Nodes;
using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;
using CueWeave.WinUI.Timeline;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace CueWeave.WinUI;

public sealed partial class MainPage : Page
{
    private readonly CoreProcess core = new();
    private readonly ProjectSession session;
    private LocalSettings settings = LocalSettingsStore.Load();
    private readonly PlaybackService playback = new();
    private CancellationTokenSource? operationCancellation;
    private CancellationTokenSource? waveformCancellation;
    private bool refreshing;
    private bool rendering;
    private bool changingZoom;
    private string? audioPath;
    private double timelineDuration;

    public MainPage()
    {
        session = new ProjectSession(core);
        InitializeComponent();
        session.PropertyChanged += (_, _) => Refresh();
        Timeline.SeekRequested += time => { playback.Seek(time); UpdatePlaybackFrame(); };
        Timeline.NudgeRequested += NudgeSelected;
        Timeline.CommandRequested += HandleTimelineCommand;
        Timeline.ActiveSegmentChanged += id =>
        {
            UpdateQueueVisuals(id);
            if (id is ulong value) ScrollToSegment(value);
            FollowNextIfNeeded(id);
        };
        Timeline.SelectedSegmentChanged += _ => { RefreshInspector(); UpdateQueueVisuals(Timeline.ActiveSegmentId); };
        Timeline.ZoomChanged += zoom => { changingZoom = true; ZoomSlider.Value = zoom; ZoomText.Text = $"{zoom:0.0}×"; changingZoom = false; };
        Unloaded += (_, _) => { StopRendering(); waveformCancellation?.Cancel(); };
        Navigation.SelectedItem = Navigation.MenuItems[0];
        Refresh();
    }

    private async void NewProject_Click(object sender, RoutedEventArgs e)
    {
        var source = await PickOpenAsync("Choose the original NCM", ".ncm");
        if (source is null) return;
        var target = await PickOpenAsync("Choose the target MP3", ".mp3");
        if (target is null) return;
        var output = await PickSaveAsync("CueWeave project", ".cueweave", Path.GetFileNameWithoutExtension(target.Name));
        if (output is null) return;
        await RunAsync("Creating project", token => session.CreateAsync(output.Path, source.Path, target.Path, token));
    }

    private async void OpenProject_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync("Open CueWeave project", ".cueweave");
        if (file is not null) await RunAsync("Opening project", token => session.LoadAsync(file.Path, token));
    }

    private async void Save_Click(object sender, RoutedEventArgs e) => await RunAsync("Saving", session.SaveAsync);
    private async void Revert_Click(object sender, RoutedEventArgs e)
    {
        if (session.ProjectPath is not null) await RunAsync("Reverting", token => session.LoadAsync(session.ProjectPath, token));
    }
    private void Undo_Click(object sender, RoutedEventArgs e) => session.Undo();
    private void Redo_Click(object sender, RoutedEventArgs e) => session.Redo();

    private async void ReplaceTarget_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync("Choose the replacement target MP3", ".mp3");
        if (file is not null) await RunAsync("Replacing target", token => session.RunProjectCommandAsync("retarget", new JsonObject { ["target_path"] = file.Path }, token));
    }

    private async void ImportLyrics_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync("Import lyric text", ".txt", ".lrc", ".yrc");
        if (file is null) return;
        var text = await FileIO.ReadTextAsync(file);
        await RunAsync("Applying lyrics", token => session.RunProjectCommandAsync("replace_lyrics", new JsonObject { ["original"] = text, ["translation"] = "" }, token));
    }

    private async void FetchLyrics_Click(object sender, RoutedEventArgs e) =>
        await RunAsync("Fetching NetEase lyrics", token => session.RunProjectCommandAsync("fetch_lyrics", null, token));

    private async void Align_Click(object sender, RoutedEventArgs e)
    {
        var provider = settings.AlignmentProvider;
        var key = provider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        var model = provider == "openrouter" ? settings.OpenRouterModel : settings.AiStudioModel;
        if (string.IsNullOrWhiteSpace(key)) { await ShowErrorAsync("Add the selected provider API key in Settings first."); return; }
        await RunAsync("Aligning complete lyric block with Gemini", token => session.RunProjectCommandAsync("align", new JsonObject {
            ["provider"] = provider, ["api_key"] = key, ["model"] = model, ["segment_ids"] = new JsonArray()
        }, token));
    }

    private async void RestoreGemini_Click(object sender, RoutedEventArgs e) =>
        await RunAsync("Restoring Gemini alignment", token => session.RunProjectCommandAsync("restore_gemini", null, token));

    private async void Translate_Click(object sender, RoutedEventArgs e)
    {
        var provider = settings.AlignmentProvider;
        var key = provider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        var model = provider == "openrouter" ? settings.OpenRouterModel : settings.AiStudioModel;
        if (string.IsNullOrWhiteSpace(key)) { await ShowErrorAsync("Add the selected provider API key in Settings first."); return; }
        await RunAsync("Translating through Gemini", token => session.RunProjectCommandAsync("translate", new JsonObject {
            ["provider"] = provider, ["api_key"] = key, ["model"] = model, ["target_language"] = TargetLanguageBox.Text
        }, token));
    }

    private async void ImportTranslations_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync("Import translation text", ".txt", ".lrc");
        if (file is null) return;
        var text = await FileIO.ReadTextAsync(file);
        await RunAsync("Applying translations", token => session.RunProjectCommandAsync("replace_translations", new JsonObject { ["translation"] = text }, token));
    }

    private void ClearTranslations_Click(object sender, RoutedEventArgs e) => session.ClearTranslations();

    private void Translation_LostFocus(object sender, RoutedEventArgs e)
    {
        if (refreshing || sender is not TextBox { DataContext: LyricLine line } box) return;
        session.SetLineTranslation(line.Id, box.Text);
    }

    private async void ExportCueSheet_Click(object sender, RoutedEventArgs e)
    {
        var output = await PickSaveAsync("Cue Sheet JSON", ".json", $"{session.Title}.cuesheet");
        if (output is not null) await RunAsync("Writing cue sheet", token => session.ExportCueSheetAsync(output.Path, token));
    }

    private void ExportOption_Changed(object sender, RoutedEventArgs e) => ApplyExportOptions();
    private void Bilingual_Changed(object sender, SelectionChangedEventArgs e) => ApplyExportOptions();

    private void ApplyExportOptions()
    {
        if (refreshing || session.Project is null) return;
        session.Mutate(project => {
            project.ExportProfile.Formats = new[] {
                LrcCheck.IsChecked == true ? "lrc" : null,
                UsltCheck.IsChecked == true ? "uslt" : null,
                SyltCheck.IsChecked == true ? "sylt" : null
            }.OfType<string>().ToList();
            if (BilingualPicker.SelectedItem is ComboBoxItem { Tag: string bilingual }) project.ExportProfile.Bilingual = bilingual;
        });
    }

    private void Offset_Changed(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (refreshing || session.Project is null || double.IsNaN(sender.Value)) return;
        session.Mutate(project => project.ExportProfile.OffsetMs = (long)Math.Round(sender.Value));
    }

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        var output = await PickSaveAsync("Export final MP3", ".mp3", $"{session.Title} [CueWeave]");
        if (output is not null) await RunAsync("Exporting without re-encoding", token => session.ExportAsync(output.Path, token));
    }

    private void Metadata_LostFocus(object sender, RoutedEventArgs e)
    {
        if (refreshing || session.Project is null) return;
        session.Mutate(project => {
            project.Metadata.Draft.Title = EmptyToNull(DraftTitle.Text);
            project.Metadata.Draft.Artists = DraftArtist.Text.Split('/', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).ToList();
            project.Metadata.Draft.Album = EmptyToNull(DraftAlbum.Text);
            project.Metadata.Draft.AlbumArtist = EmptyToNull(DraftAlbumArtist.Text);
            project.Metadata.Draft.Date = EmptyToNull(DraftDate.Text);
        });
    }

    private async void Settings_Click(object sender, RoutedEventArgs e)
    {
        var provider = new ComboBox { ItemsSource = new[] { "OpenRouter", "AI Studio" }, SelectedIndex = settings.AlignmentProvider == "ai_studio" ? 1 : 0 };
        var openRouterKey = new PasswordBox { Password = settings.OpenRouterApiKey, PlaceholderText = "OpenRouter API key" };
        var aiStudioKey = new PasswordBox { Password = settings.AiStudioApiKey, PlaceholderText = "AI Studio API key" };
        var openRouterModel = new TextBox { Text = settings.OpenRouterModel, Header = "OpenRouter model" };
        var aiStudioModel = new TextBox { Text = settings.AiStudioModel, Header = "AI Studio model" };
        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(new TextBlock { Text = "Provider", FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas") });
        content.Children.Add(provider); content.Children.Add(openRouterKey); content.Children.Add(openRouterModel);
        content.Children.Add(aiStudioKey); content.Children.Add(aiStudioModel);
        content.Children.Add(new TextBlock { Text = $"Stored locally as plain JSON:\n{LocalSettingsStore.ConfigPath}", TextWrapping = TextWrapping.Wrap, Opacity = .65 });
        var dialog = new ContentDialog { XamlRoot = XamlRoot, Title = "Alignment Settings", Content = content, PrimaryButtonText = "Save locally", CloseButtonText = "Cancel" };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        settings.AlignmentProvider = provider.SelectedIndex == 1 ? "ai_studio" : "openrouter";
        settings.OpenRouterApiKey = openRouterKey.Password;
        settings.AiStudioApiKey = aiStudioKey.Password;
        settings.OpenRouterModel = openRouterModel.Text.Trim();
        settings.AiStudioModel = aiStudioModel.Text.Trim();
        try { LocalSettingsStore.Save(settings); ActivityText.Text = "Provider settings saved locally"; }
        catch (Exception error) { await ShowErrorAsync(error.Message); }
        Refresh();
    }

    private void Navigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var tag = (args.SelectedItemContainer?.Tag as string) ?? "source";
        SourcePanel.Visibility = tag == "source" ? Visibility.Visible : Visibility.Collapsed;
        MetadataPanel.Visibility = tag == "metadata" ? Visibility.Visible : Visibility.Collapsed;
        LyricsPanel.Visibility = tag == "lyrics" ? Visibility.Visible : Visibility.Collapsed;
        TranslationPanel.Visibility = tag == "translation" ? Visibility.Visible : Visibility.Collapsed;
        AlignmentPanel.Visibility = tag == "alignment" ? Visibility.Visible : Visibility.Collapsed;
        ExportPanel.Visibility = tag == "export" ? Visibility.Visible : Visibility.Collapsed;
        if (tag == "alignment") Timeline.Focus(FocusState.Programmatic);
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) { operationCancellation?.Cancel(); core.Cancel(); }

    private async Task RunAsync(string label, Func<CancellationToken, Task> operation)
    {
        operationCancellation?.Dispose();
        operationCancellation = new CancellationTokenSource();
        SetBusy(true, label);
        try { await operation(operationCancellation.Token); ActivityText.Text = label + " complete"; }
        catch (OperationCanceledException) { ActivityText.Text = "Cancelled"; }
        catch (Exception error) { ActivityText.Text = "Failed"; await ShowErrorAsync(error.Message); }
        finally { SetBusy(false, ActivityText.Text); Refresh(); }
    }

    private void SetBusy(bool busy, string activity)
    {
        BusyBar.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        CancelButton.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        Navigation.IsEnabled = !busy;
        ActivityText.Text = activity;
    }

    private void Refresh()
    {
        refreshing = true;
        var project = session.Project;
        WelcomePanel.Visibility = project is null ? Visibility.Visible : Visibility.Collapsed;
        ProjectTitle.Text = project is null ? "Lyrics, aligned to your track." : session.Title;
        SaveStateText.Text = project is null ? "NO PROJECT" : session.IsDirty ? "EDITED" : "SAVED";
        SaveButton.IsEnabled = project is not null;
        RevertButton.IsEnabled = project is not null && session.ProjectPath is not null;
        UndoButton.IsEnabled = session.CanUndo; RedoButton.IsEnabled = session.CanRedo;
        FinalState.Text = project is null ? "FINAL 0" : $"FINAL {project.Segments.Count(s => s.Timing.Final is not null)}/{project.Segments.Count}";
        var activeKey = settings.AlignmentProvider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        ProviderState.Text = $"{(settings.AlignmentProvider == "openrouter" ? "OpenRouter" : "AI Studio")} · {(activeKey.Length == 0 ? "key missing" : "ready")}";
        if (project is not null) PopulateProject(project);
        refreshing = false;
    }

    private void PopulateProject(ProjectDocument project)
    {
        SourceName.Text = Path.GetFileName(project.Source?.Path ?? "Missing"); SourcePath.Text = project.Source?.Path ?? "Missing";
        SourceDetails.Text = $"FORMAT  {project.Source?.Format?.ToUpperInvariant() ?? "NCM"}\nMUSIC ID  {project.Source?.MusicId?.ToString() ?? "—"}";
        TargetName.Text = Path.GetFileName(project.Target?.Path ?? "Missing"); TargetPath.Text = project.Target?.Path ?? "Missing";
        TargetDetails.Text = $"FORMAT  MP3\nDURATION  {FormatTime(project.Target?.DurationMs)}";
        var source = project.Metadata.Source; var target = project.Metadata.Target; var draft = project.Metadata.Draft;
        SourceTitle.Text = source.Title ?? "—"; TargetTitle.Text = target.Title ?? "—"; DraftTitle.Text = draft.Title ?? "";
        SourceArtist.Text = Join(source.Artists); TargetArtist.Text = Join(target.Artists); DraftArtist.Text = Join(draft.Artists, " / ");
        SourceAlbum.Text = source.Album ?? "—"; TargetAlbum.Text = target.Album ?? "—"; DraftAlbum.Text = draft.Album ?? "";
        SourceAlbumArtist.Text = source.AlbumArtist ?? "—"; TargetAlbumArtist.Text = target.AlbumArtist ?? "—"; DraftAlbumArtist.Text = draft.AlbumArtist ?? "";
        SourceDate.Text = source.Date ?? "—"; TargetDate.Text = target.Date ?? "—"; DraftDate.Text = draft.Date ?? "";
        LyricsList.ItemsSource = project.Lyrics.Lines;
        TranslationList.ItemsSource = project.Lyrics.Lines;
        AlignmentList.ItemsSource = project.Segments;
        ConfigureTimeline(project);
        var aligned = project.Segments.Count(s => s.Timing.Final is not null);
        var translated = project.Lyrics.Lines.Count(line => !string.IsNullOrWhiteSpace(line.Translation));
        ExportSummary.Text = $"{project.Lyrics.Lines.Count} lines · {translated} translated · {aligned}/{project.Segments.Count} final";
        LrcCheck.IsChecked = project.ExportProfile.Formats.Contains("lrc");
        UsltCheck.IsChecked = project.ExportProfile.Formats.Contains("uslt");
        SyltCheck.IsChecked = project.ExportProfile.Formats.Contains("sylt");
        BilingualPicker.SelectedIndex = project.ExportProfile.Bilingual == "combined" ? 1 : 0;
        OffsetBox.Value = project.ExportProfile.OffsetMs;
        RefreshInspector(); UpdateQueueVisuals(Timeline.ActiveSegmentId);
    }

    private void ConfigureTimeline(ProjectDocument project)
    {
        var duration = (double)(project.Target?.DurationMs ?? 1);
        var path = project.Target?.Path;
        if (timelineDuration != duration || audioPath != path) {
            timelineDuration = duration; Timeline.SetDocument(duration, project.Segments);
        } else Timeline.SetSegments(project.Segments);
        if (!string.IsNullOrWhiteSpace(path) && audioPath != path) _ = LoadAudioAsync(path);
    }

    private async Task LoadAudioAsync(string path)
    {
        audioPath = path; waveformCancellation?.Cancel(); waveformCancellation?.Dispose();
        waveformCancellation = new CancellationTokenSource();
        try {
            await playback.LoadAsync(path); Timeline.Tick(0);
            var data = await WaveformAnalyzer.AnalyzeAsync(path, token: waveformCancellation.Token);
            if (audioPath == path) Timeline.SetWaveform(data);
        } catch (OperationCanceledException) { }
        catch (Exception error) { await ShowErrorAsync($"Audio analysis failed: {error.Message}"); }
    }

    private void Play_Click(object sender, RoutedEventArgs e)
    {
        playback.PlayPause(); UpdateRendering(); UpdatePlaybackFrame();
    }

    private void Speed_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (SpeedPicker.SelectedItem is ComboBoxItem item && double.TryParse(item.Tag?.ToString(), out var rate)) playback.SetRate(rate);
    }

    private void LoopA_Click(object sender, RoutedEventArgs e) { playback.MarkA(); SyncLoop(); }
    private void LoopB_Click(object sender, RoutedEventArgs e) { playback.MarkB(); SyncLoop(); }
    private void LoopClear_Click(object sender, RoutedEventArgs e) { playback.ClearLoop(); SyncLoop(); }
    private void Follow_Changed(object sender, RoutedEventArgs e) => Timeline.SetFollow(FollowButton.IsChecked == true);
    private void Next_Changed(object sender, RoutedEventArgs e)
    {
        if (NextButton.IsChecked == true) FollowNextIfNeeded(Timeline.ActiveSegmentId);
    }
    private void Zoom_Changed(object sender, RangeBaseValueChangedEventArgs e) { if (!changingZoom) Timeline.SetZoom(e.NewValue); }

    private void Mark_Click(object sender, RoutedEventArgs e)
    {
        if (Timeline.SelectedSegmentId is ulong id) session.SetFinal(id, (long)Math.Round(playback.PositionMs));
    }

    private void Nudge_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string tag } && long.TryParse(tag, out var delta)) NudgeSelected(delta);
    }

    private void NudgeSelected(long delta)
    {
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
        playback.Seek(Math.Max(0, (long)time - 2_000)); if (!playback.IsPlaying) playback.PlayPause(); UpdateRendering();
    }

    private void UseGemini_Click(object sender, RoutedEventArgs e) { if (Timeline.SelectedSegmentId is ulong id) session.UseGemini(id); }
    private void ClearFinal_Click(object sender, RoutedEventArgs e) { if (Timeline.SelectedSegmentId is ulong id) session.ClearFinal(id); }

    private void AlignmentList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is LyricSegment segment)
        {
            SetFollowSelection(false);
            Timeline.Select(segment.Id);
        }
    }

    private void HandleTimelineCommand(string command)
    {
        switch (command) {
        case "select_current": SetFollowSelection(false); Timeline.SelectCurrent(); break;
        case "select_next_playing":
            if (!TimelineViewport.KeepsFollowSelection(1)) SetFollowSelection(false);
            Timeline.SelectRelativeToPlayhead(1); break;
        case "select_previous_playing": SetFollowSelection(false); Timeline.SelectRelativeToPlayhead(-1); break;
        case "play": Play_Click(this, new RoutedEventArgs()); break;
        case "loop_a": playback.MarkA(); SyncLoop(); break;
        case "loop_b": playback.MarkB(); SyncLoop(); break;
        case "loop_clear": playback.ClearLoop(); SyncLoop(); break;
        case "next": SetFollowSelection(false); NavigateSegment(1); break;
        case "previous": SetFollowSelection(false); NavigateSegment(-1); break;
        case "mark": Mark_Click(this, new RoutedEventArgs()); break;
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

    private void UpdateRendering()
    {
        if (playback.IsPlaying && !rendering) { CompositionTarget.Rendering += RenderingFrame; rendering = true; }
        else if (!playback.IsPlaying) StopRendering();
        PlayButton.Icon = new SymbolIcon(playback.IsPlaying ? Symbol.Pause : Symbol.Play);
    }

    private void StopRendering()
    {
        if (!rendering) return; CompositionTarget.Rendering -= RenderingFrame; rendering = false;
    }

    private void RenderingFrame(object? sender, object e)
    {
        UpdatePlaybackFrame(); if (!playback.IsPlaying) UpdateRendering();
    }

    private void UpdatePlaybackFrame()
    {
        var position = playback.Tick(); Timeline.LoopStartMs = playback.LoopStartMs; Timeline.LoopEndMs = playback.LoopEndMs;
        Timeline.Tick(position); PlaybackTime.Text = FormatTime((ulong)Math.Max(0, position));
    }

    private void SyncLoop()
    {
        Timeline.LoopStartMs = playback.LoopStartMs; Timeline.LoopEndMs = playback.LoopEndMs; Timeline.Tick(playback.PositionMs);
    }

    private void RefreshInspector()
    {
        var segment = SelectedSegment();
        InspectorLabel.Text = segment is null ? "NO SEGMENT SELECTED" : $"SEGMENT {segment.Id:0000}";
        InspectorText.Text = segment?.Text ?? "Press Enter to select the lyric at the playhead.";
        var line = segment is null ? null : session.Project?.Lyrics.Lines.FirstOrDefault(value => value.Segments.Any(item => item.Id == segment.Id));
        InspectorTranslation.Text = string.IsNullOrWhiteSpace(line?.Translation)
            ? "Translation is edited on the Translation page."
            : line!.Translation;
        GeminiTime.Text = "GEMINI " + FormatTime(segment?.Timing.Gemini?.TimeMs);
        FinalTime.Text = "FINAL " + FormatTime(segment?.Timing.Final?.TimeMs);
    }

    private LyricSegment? SelectedSegment() => Timeline.SelectedSegmentId is ulong id
        ? session.Project?.Segments.FirstOrDefault(segment => segment.Id == id) : null;

    private void UpdateQueueVisuals(ulong? active)
    {
        DispatcherQueue.TryEnqueue(() => {
            if (session.Project is null) return;
            for (var index = 0; index < session.Project.Segments.Count; index++) {
                if (AlignmentList.ContainerFromIndex(index) is not ListViewItem item) continue;
                var id = session.Project.Segments[index].Id;
                item.Background = new SolidColorBrush(id == Timeline.SelectedSegmentId
                    ? Microsoft.UI.ColorHelper.FromArgb(115, 50, 127, 159)
                    : id == active ? Microsoft.UI.ColorHelper.FromArgb(55, 50, 127, 159)
                    : Microsoft.UI.Colors.Transparent);
            }
        });
    }

    private void AdjustRate(int direction)
    {
        var rate = TimelineViewport.SteppedRate(playback.Rate, direction);
        playback.SetRate(rate);
        for (var index = 0; index < SpeedPicker.Items.Count; index++)
        {
            if (SpeedPicker.Items[index] is ComboBoxItem item &&
                double.TryParse(item.Tag?.ToString(), out var value) &&
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
        if (NextButton.IsChecked != on) NextButton.IsChecked = on;
    }

    private void ScrollToSegment(ulong id)
    {
        var segment = session.Project?.Segments.FirstOrDefault(value => value.Id == id);
        if (segment is not null) AlignmentList.ScrollIntoView(segment);
    }

    private async Task<StorageFile?> PickOpenAsync(string title, params string[] extensions)
    {
        var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.MusicLibrary, ViewMode = PickerViewMode.List, CommitButtonText = title };
        foreach (var extension in extensions) picker.FileTypeFilter.Add(extension);
        Initialize(picker); return await picker.PickSingleFileAsync();
    }

    private async Task<StorageFile?> PickSaveAsync(string title, string extension, string name)
    {
        var picker = new FileSavePicker { SuggestedStartLocation = PickerLocationId.MusicLibrary, SuggestedFileName = name, CommitButtonText = title };
        picker.FileTypeChoices.Add(title, new[] { extension }); Initialize(picker); return await picker.PickSaveFileAsync();
    }

    private static void Initialize(object picker) => WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(App.MainWindow));
    private async Task ShowErrorAsync(string message) => await new ContentDialog { XamlRoot = XamlRoot, Title = "CueWeave", Content = message, CloseButtonText = "OK" }.ShowAsync();
    private static string? EmptyToNull(string value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static string Join(IEnumerable<string> values, string separator = ", ") => string.Join(separator, values.DefaultIfEmpty("—"));
    private static string FormatTime(ulong? milliseconds) => milliseconds is null ? "—" : $"{milliseconds / 60000:00}:{milliseconds / 1000 % 60:00}.{milliseconds % 1000:000}";
}
