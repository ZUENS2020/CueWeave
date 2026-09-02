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
    private string? localAudioPath;
    private double timelineDuration;

    public MainPage()
    {
        session = new ProjectSession(core);
        L10n.Apply(settings.UiLanguage);
        InitializeComponent();
        FollowButton.IsChecked = true;
        NextButton.IsChecked = false;
        OverwriteCheck.IsChecked = true;
        BindChrome();
        session.PropertyChanged += (_, _) => Refresh();
        Timeline.SeekRequested += time => { playback.Seek(time); UpdatePlaybackFrame(); };
        Timeline.NudgeRequested += NudgeSelected;
        Timeline.CommandRequested += HandleTimelineCommand;
        Timeline.VisualizationChanged += () => _ = ReloadSpectrogramAsync();
        Timeline.ActiveSegmentChanged += id =>
        {
            UpdateQueueVisuals(id);
            if (id is ulong value) ScrollToSegment(value);
            FollowNextIfNeeded(id);
        };
        Timeline.SelectedSegmentChanged += _ => { RefreshInspector(); UpdateQueueVisuals(Timeline.ActiveSegmentId); };
        Timeline.ZoomChanged += zoom => { changingZoom = true; ZoomSlider.Value = zoom; ZoomText.Text = $"{zoom:0.0}×"; changingZoom = false; };
        Unloaded += (_, _) => { StopRendering(); waveformCancellation?.Cancel(); };
        Refresh();
    }

    private async void NewProject_Click(object sender, RoutedEventArgs e)
    {
        var source = await PickOpenAsync(L10n.T("pick.ncm"), ".ncm");
        if (source is null) return;
        var target = await PickOpenAsync(L10n.T("pick.mp3"), ".mp3");
        if (target is null) return;
        var output = await PickSaveAsync(L10n.T("pick.project"), ".cueweave", Path.GetFileNameWithoutExtension(target.Name));
        if (output is null) return;
        await RunAsync(L10n.T("activity.creating"), token => session.CreateAsync(output.Path, source.Path, target.Path, token));
    }

    private async void OpenProject_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync(L10n.T("pick.openProject"), ".cueweave");
        if (file is not null) await RunAsync(L10n.T("activity.opening"), token => session.LoadAsync(file.Path, token));
    }

    private async void Save_Click(object sender, RoutedEventArgs e) => await RunAsync(L10n.T("activity.saving"), session.SaveAsync);
    private async void Revert_Click(object sender, RoutedEventArgs e)
    {
        if (session.ProjectPath is not null) await RunAsync(L10n.T("activity.reverting"), token => session.LoadAsync(session.ProjectPath, token));
    }
    private void Undo_Click(object sender, RoutedEventArgs e) => session.Undo();
    private void Redo_Click(object sender, RoutedEventArgs e) => session.Redo();

    private async void ReplaceTarget_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync(L10n.T("pick.replaceMp3"), ".mp3");
        if (file is not null) await RunAsync(L10n.T("activity.replacingTarget"), token => session.RunProjectCommandAsync("retarget", new JsonObject { ["target_path"] = file.Path }, token));
    }

    private async void ImportLyrics_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync(L10n.T("pick.importLyrics"), ".txt", ".lrc", ".yrc");
        if (file is null) return;
        var text = await FileIO.ReadTextAsync(file);
        await RunAsync(L10n.T("activity.applyingLyrics"), token => session.RunProjectCommandAsync("replace_lyrics", new JsonObject { ["original"] = text, ["translation"] = "" }, token));
    }

    private async void AddLyrics_Click(object sender, RoutedEventArgs e) =>
        await PromptInsertLyricsAsync(session.Project?.Lyrics.Lines.LastOrDefault()?.Id);

    private async void InsertAfter_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement element && element.DataContext is LyricLine line)
            await PromptInsertLyricsAsync(line.Id);
    }

    private async Task PromptInsertLyricsAsync(ulong? preferredAfter)
    {
        var lines = session.Project?.Lyrics.Lines ?? [];
        var box = new TextBox { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Height = 140, PlaceholderText = L10n.T("lyrics.insertPlaceholder") };
        var positions = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        positions.Items.Add(L10n.T("lyrics.insertAtStart"));
        foreach (var line in lines)
        {
            var preview = line.Original.Length > 40 ? line.Original[..40] + "…" : line.Original;
            positions.Items.Add(L10n.T("lyrics.insertAfter", preview));
        }
        var preferredIndex = preferredAfter is ulong id ? lines.FindIndex(line => line.Id == id) + 1 : 0;
        positions.SelectedIndex = preferredIndex > 0 ? preferredIndex : lines.Count;
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(positions);
        panel.Children.Add(box);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = L10n.T("lyrics.insertTitle"),
            Content = panel,
            PrimaryButtonText = L10n.T("lyrics.insertCommit"),
            CloseButtonText = L10n.T("action.cancel")
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (string.IsNullOrWhiteSpace(box.Text)) return;
        var extra = new JsonObject { ["text"] = box.Text };
        if (positions.SelectedIndex > 0)
            extra["after_line_id"] = JsonValue.Create(lines[positions.SelectedIndex - 1].Id);
        await RunAsync(L10n.T("activity.insertingLyrics"), token => session.RunProjectCommandAsync("insert_lyrics", extra, token));
    }

    private async void FetchLyrics_Click(object sender, RoutedEventArgs e) =>
        await RunAsync(L10n.T("activity.fetchingLyrics"), token => session.RunProjectCommandAsync("fetch_lyrics", null, token));

    private async void Align_Click(object sender, RoutedEventArgs e)
    {
        var provider = settings.AlignmentProvider;
        var key = provider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        var model = provider == "openrouter" ? settings.OpenRouterModel : settings.AiStudioModel;
        if (string.IsNullOrWhiteSpace(key)) { await ShowErrorAsync(L10n.T("error.needApiKey")); return; }
        await RunAsync(L10n.T("activity.aligningAll"), token => session.RunProjectCommandAsync("align", new JsonObject {
            ["provider"] = provider, ["api_key"] = key, ["model"] = model, ["segment_ids"] = new JsonArray()
        }, token));
    }

    private async void RestoreGemini_Click(object sender, RoutedEventArgs e) =>
        await RunAsync(L10n.T("activity.restoringGemini"), token => session.RunProjectCommandAsync("restore_gemini", null, token));

    private async void Translate_Click(object sender, RoutedEventArgs e)
    {
        var provider = settings.AlignmentProvider;
        var key = provider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        var model = provider == "openrouter" ? settings.OpenRouterModel : settings.AiStudioModel;
        if (string.IsNullOrWhiteSpace(key)) { await ShowErrorAsync(L10n.T("error.needApiKey")); return; }
        await RunAsync(L10n.T("activity.translating", "Gemini"), token => session.RunProjectCommandAsync("translate", new JsonObject {
            ["provider"] = provider, ["api_key"] = key, ["model"] = model, ["target_language"] = TargetLanguageBox.Text
        }, token));
    }

    private async void ImportTranslations_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync(L10n.T("pick.importTranslation"), ".txt", ".lrc");
        if (file is null) return;
        var text = await FileIO.ReadTextAsync(file);
        await RunAsync(L10n.T("activity.applyingTranslations"), token => session.RunProjectCommandAsync("replace_translations", new JsonObject { ["translation"] = text }, token));
    }

    private void ClearTranslations_Click(object sender, RoutedEventArgs e) => session.ClearTranslations();

    private void Translation_LostFocus(object sender, RoutedEventArgs e)
    {
        if (refreshing || sender is not TextBox { DataContext: LyricLine line } box) return;
        session.SetLineTranslation(line.Id, box.Text);
    }

    private async void ExportCueSheet_Click(object sender, RoutedEventArgs e)
    {
        if (session.Project is null) return;
        var output = await PickSaveAsync(L10n.T("pick.cueSheet"), ".json", $"{session.Title}.cuesheet");
        if (output is not null) await RunAsync(L10n.T("activity.writingCueSheet"), token => session.ExportCueSheetAsync(output.Path, token));
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
        if (session.Project is null) return;
        var output = await PickSaveAsync(L10n.T("pick.exportMp3"), ".mp3", $"{session.Title} [CueWeave]");
        if (output is null) return;
        if (await ResolveExportOverwriteAsync(output.Path) is not bool overwrite) return;
        await RunAsync(L10n.T("activity.exporting"), token => session.ExportAsync(output.Path, overwrite, token));
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
        var language = new ComboBox {
            ItemsSource = new[] { L10n.T("lang.system"), L10n.T("lang.en"), L10n.T("lang.zh") },
            SelectedIndex = settings.UiLanguage == "en" ? 1 : settings.UiLanguage == "zh" ? 2 : 0
        };
        var provider = new ComboBox { ItemsSource = new[] { "OpenRouter", "AI Studio" }, SelectedIndex = settings.AlignmentProvider == "ai_studio" ? 1 : 0 };
        var openRouterKey = new PasswordBox { Password = settings.OpenRouterApiKey, PlaceholderText = L10n.T("settings.openRouterKey") };
        var aiStudioKey = new PasswordBox { Password = settings.AiStudioApiKey, PlaceholderText = L10n.T("settings.aiStudioKey") };
        var openRouterModel = new TextBox { Text = settings.OpenRouterModel, Header = L10n.T("settings.openRouterModel") };
        var aiStudioModel = new TextBox { Text = settings.AiStudioModel, Header = L10n.T("settings.aiStudioModel") };
        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(new TextBlock { Text = L10n.T("settings.language"), FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas") });
        content.Children.Add(language);
        content.Children.Add(new TextBlock { Text = L10n.T("settings.provider"), FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas") });
        content.Children.Add(provider); content.Children.Add(openRouterKey); content.Children.Add(openRouterModel);
        content.Children.Add(aiStudioKey); content.Children.Add(aiStudioModel);
        content.Children.Add(new TextBlock { Text = L10n.T("settings.keysNote.win", LocalSettingsStore.ConfigPath), TextWrapping = TextWrapping.Wrap, Opacity = .65 });
        var dialog = new ContentDialog { XamlRoot = XamlRoot, Title = L10n.T("settings.title"), Content = content, PrimaryButtonText = L10n.T("settings.saveLocally"), CloseButtonText = L10n.T("action.cancel") };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        settings.UiLanguage = language.SelectedIndex == 1 ? "en" : language.SelectedIndex == 2 ? "zh" : "system";
        settings.AlignmentProvider = provider.SelectedIndex == 1 ? "ai_studio" : "openrouter";
        settings.OpenRouterApiKey = openRouterKey.Password;
        settings.AiStudioApiKey = aiStudioKey.Password;
        settings.OpenRouterModel = openRouterModel.Text.Trim();
        settings.AiStudioModel = aiStudioModel.Text.Trim();
        try { LocalSettingsStore.Save(settings); L10n.Apply(settings.UiLanguage); BindChrome(); ActivityText.Text = L10n.T("activity.settingsSaved"); }
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
        try { await operation(operationCancellation.Token); ActivityText.Text = L10n.T("activity.doneFmt", label); }
        catch (OperationCanceledException) { ActivityText.Text = L10n.T("activity.cancelled"); }
        catch (Exception error) { ActivityText.Text = L10n.T("activity.failed"); await ShowErrorAsync(error.Message); }
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
        BindChrome();
        var project = session.Project;
        WelcomePanel.Visibility = project is null ? Visibility.Visible : Visibility.Collapsed;
        Navigation.Visibility = project is null ? Visibility.Collapsed : Visibility.Visible;
        if (project is not null && Navigation.SelectedItem is null)
            Navigation.SelectedItem = Navigation.MenuItems[0];
        ProjectTitle.Text = project is null ? L10n.T("welcome.headline.one") : session.Title;
        SaveStateText.Text = project is null ? L10n.T("status.noProject") : session.IsDirty ? L10n.T("status.edited") : L10n.T("status.saved");
        SaveButton.IsEnabled = project is not null;
        RevertButton.IsEnabled = project is not null && session.ProjectPath is not null;
        UndoButton.IsEnabled = session.CanUndo; RedoButton.IsEnabled = session.CanRedo;
        var activeKey = settings.AlignmentProvider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        var providerName = settings.AlignmentProvider == "openrouter" ? "OpenRouter" : "AI Studio";
        ProviderState.Text = activeKey.Length == 0 ? L10n.T("chrome.providerMissing", providerName) : L10n.T("chrome.providerReady", providerName);
        if (project is not null) PopulateProject(project);
        else {
            ExportFinalButton.IsEnabled = false;
            SaveCueSheetButton.IsEnabled = false;
            if (BusyBar.Visibility != Visibility.Visible) ActivityText.Text = L10n.T("activity.none");
        }
        refreshing = false;
    }

    private void PopulateProject(ProjectDocument project)
    {
        SourceName.Text = Path.GetFileName(project.Source?.Path ?? L10n.T("file.missing")); SourcePath.Text = project.Source?.Path ?? L10n.T("file.missing");
        SourceDetails.Text = L10n.T("source.details", project.Source?.Format?.ToUpperInvariant() ?? "NCM", project.Source?.MusicId?.ToString() ?? "—");
        TargetName.Text = Path.GetFileName(project.Target?.Path ?? L10n.T("file.missing")); TargetPath.Text = project.Target?.Path ?? L10n.T("file.missing");
        TargetDetails.Text = L10n.T("source.targetDetails", FormatTime(project.Target?.DurationMs));
        var source = project.Metadata.Source; var target = project.Metadata.Target; var draft = project.Metadata.Draft;
        SourceTitle.Text = source.Title ?? "—"; TargetTitle.Text = target.Title ?? "—"; DraftTitle.Text = draft.Title ?? "";
        SourceArtist.Text = Join(source.Artists); TargetArtist.Text = Join(target.Artists); DraftArtist.Text = Join(draft.Artists, " / ");
        SourceAlbum.Text = source.Album ?? "—"; TargetAlbum.Text = target.Album ?? "—"; DraftAlbum.Text = draft.Album ?? "";
        SourceAlbumArtist.Text = source.AlbumArtist ?? "—"; TargetAlbumArtist.Text = target.AlbumArtist ?? "—"; DraftAlbumArtist.Text = draft.AlbumArtist ?? "";
        SourceDate.Text = source.Date ?? "—"; TargetDate.Text = target.Date ?? "—"; DraftDate.Text = draft.Date ?? "";
        LyricsList.ItemsSource = project.Lyrics.Lines;
        TranslationList.ItemsSource = project.Lyrics.Lines;
        AlignmentList.ItemsSource = project.Segments;
        BindCredits(project);
        ConfigureTimeline(project);
        SaveCueSheetButton.IsEnabled = true;
        ExportFinalButton.IsEnabled = true;
        LrcCheck.IsChecked = project.ExportProfile.Formats.Contains("lrc");
        UsltCheck.IsChecked = project.ExportProfile.Formats.Contains("uslt");
        SyltCheck.IsChecked = project.ExportProfile.Formats.Contains("sylt");
        BilingualPicker.SelectedIndex = project.ExportProfile.Bilingual is "bilingual" or "combined" ? 1 : 0;
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
            var sha = session.Project?.Target?.Fingerprint?.Sha256;
            localAudioPath = WinPaths.Materialize(path, sha);
            BootLog.Append($"audio {path.Length} {path} => {localAudioPath.Length} {localAudioPath}");
            await playback.LoadAsync(localAudioPath); Timeline.Tick(0);
            var data = await WaveformAnalyzer.AnalyzeAsync(localAudioPath, token: waveformCancellation.Token);
            if (audioPath == path) {
                data = await AudioVizClient.EnrichAsync(core, localAudioPath, sha, data, Timeline.NeededScales, waveformCancellation.Token);
                Timeline.SetWaveform(data);
            }
        } catch (OperationCanceledException) { }
        catch (FileNotFoundException) { await ShowErrorAsync(L10n.T("error.audioMissing", path)); }
        catch (Exception error) {
            BootLog.Append($"audio {path} {error}");
            await ShowErrorAsync(L10n.T("error.audioLoad", path, error.Message));
        }
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
        case "toggle_follow_next": SetFollowSelection(NextButton.IsChecked != true); break;
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
        InspectorLabel.Text = segment is null ? L10n.T("inspect.none") : L10n.T("inspect.segment", segment.Id.ToString("0000"));
        InspectorText.Text = segment?.Text ?? L10n.T("inspect.hint.win");
        var line = segment is null ? null : session.Project?.Lyrics.Lines.FirstOrDefault(value => value.Segments.Any(item => item.Id == segment.Id));
        InspectorTranslation.Text = string.IsNullOrWhiteSpace(line?.Translation)
            ? L10n.T("inspect.translationHint")
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
        try { return await FilePickers.OpenAsync(title, extensions); }
        catch (Exception error)
        {
            BootLog.Append($"picker open {error}");
            await ShowErrorAsync(error.Message);
            return null;
        }
    }

    private async Task<StorageFile?> PickSaveAsync(string title, string extension, string name)
    {
        try { return await FilePickers.SaveAsync(title, extension, name); }
        catch (Exception error)
        {
            BootLog.Append($"picker save {error}");
            await ShowErrorAsync(error.Message);
            return null;
        }
    }

    private async Task<bool?> ResolveExportOverwriteAsync(string path)
    {
        var exists = File.Exists(path);
        if (!exists && LrcCheck.IsChecked == true)
            exists = File.Exists(Path.ChangeExtension(path, ".lrc"));
        if (!exists) return OverwriteCheck.IsChecked == true;
        if (OverwriteCheck.IsChecked == true) return true;
        var dialog = new ContentDialog {
            XamlRoot = XamlRoot,
            Title = L10n.T("export.overwriteConfirmTitle"),
            Content = L10n.T("export.overwriteConfirmMessage", Path.GetFileName(path)),
            PrimaryButtonText = L10n.T("export.overwrite"),
            CloseButtonText = L10n.T("action.cancel")
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary ? true : null;
    }

    private async Task ShowErrorAsync(string message) => await new ContentDialog { XamlRoot = XamlRoot, Title = "CueWeave", Content = L10n.WrapError(message), CloseButtonText = L10n.T("action.ok") }.ShowAsync();
    private static string? EmptyToNull(string value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static string Join(IEnumerable<string> values, string separator = ", ") => string.Join(separator, values.DefaultIfEmpty("—"));
    private static string FormatTime(ulong? milliseconds) => milliseconds is null ? "—" : $"{milliseconds / 60000:00}:{milliseconds / 1000 % 60:00}.{milliseconds % 1000:000}";
}
