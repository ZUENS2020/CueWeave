using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;
using CueWeave.WinUI.Timeline;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Storage;
using Windows.System;

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
    private readonly HashSet<ulong> batchIds = [];
    private bool playRequested;
    private long lastSpaceToggle;

    public MainPage()
    {
        session = new ProjectSession(core);
        L10n.Apply(settings.UiLanguage);
        InitializeComponent();
        FollowButton.IsChecked = true;
        NextButton.IsChecked = false;
        OverwriteCheck.IsChecked = true;
        OffsetBox.Minimum = -2000;
        OffsetBox.Maximum = 2000;
        OffsetBox.SmallChange = 10;
        ZoomSlider.Minimum = 1;
        ZoomSlider.Maximum = 64;
        ZoomSlider.StepFrequency = .5;
        ZoomSlider.Value = 2;
        PlayButton.Content = new SymbolIcon(Symbol.Play);
        StatusPlayButton.Content = new SymbolIcon(Symbol.Play);
        var save = new KeyboardAccelerator { Key = VirtualKey.S, Modifiers = VirtualKeyModifiers.Control };
        save.Invoked += (_, args) => { args.Handled = true; Save_Click(this, new RoutedEventArgs()); };
        KeyboardAccelerators.Add(save);
        var space = new KeyboardAccelerator { Key = VirtualKey.Space };
        space.Invoked += (_, args) =>
        {
            if (!TryHandleSpacePlay()) return;
            args.Handled = true;
        };
        KeyboardAccelerators.Add(space);
        Loaded += (_, _) => AddHandler(KeyDownEvent, new KeyEventHandler(GlobalKeyDown), true);
        playback.StateChanged += () => DispatcherQueue.TryEnqueue(() =>
        {
            if (playback.IsPlaying || !playback.IsTransportActive) playRequested = false;
            UpdateRendering();
            UpdatePlaybackFrame();
        });
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
        Timeline.ZoomChanged += zoom =>
        {
            changingZoom = true;
            ZoomSlider.Value = Math.Clamp(zoom, ZoomSlider.Minimum, ZoomSlider.Maximum);
            ZoomText.Text = $"{zoom:0.0}×";
            changingZoom = false;
        };
        Timeline.CreditDragStarted += () => session.BeginCreditDrag();
        Timeline.CreditMoved += (id, ms) => session.SetCreditTimeLive(id, (ulong)Math.Max(0, Math.Round(ms)));
        Timeline.CreditDragEnded += () => session.EndCreditDrag();
        Timeline.SetFollow(true);
        Timeline.SetZoom(2);
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
    private void Undo_Click(object sender, RoutedEventArgs e) => session.Undo();
    private void Redo_Click(object sender, RoutedEventArgs e) => session.Redo();

    private void Navigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var tag = (args.SelectedItemContainer?.Tag as string) ?? "source";
        SourcePanel.Visibility = VisibleIf(tag == "source");
        MetadataPanel.Visibility = VisibleIf(tag == "metadata");
        LyricsPanel.Visibility = VisibleIf(tag == "lyrics");
        TranslationPanel.Visibility = VisibleIf(tag == "translation");
        AlignmentPanel.Visibility = VisibleIf(tag == "alignment");
        ExportPanel.Visibility = VisibleIf(tag == "export");
        BindPageChrome(tag);
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
        BusyBar.Visibility = VisibleIf(busy);
        CancelButton.Visibility = VisibleIf(busy);
        Navigation.IsEnabled = !busy;
        ActivityText.Text = activity;
    }

    private void Refresh()
    {
        refreshing = true;
        BindChrome();
        var project = session.Project;
        WelcomePanel.Visibility = VisibleIf(project is null);
        Navigation.Visibility = VisibleIf(project is not null);
        StatusPlayback.Visibility = VisibleIf(project is not null);
        if (project is not null && Navigation.SelectedItem is null)
            Navigation.SelectedItem = Navigation.MenuItems[0];
        PaneProjectTitle.Text = project is null ? "CueWeave" : session.Title;
        PaneProjectPath.Text = session.ProjectPath ?? "";
        SaveStateText.Text = project is null ? L10n.T("status.noProject") : session.IsDirty ? L10n.T("status.edited") : L10n.T("status.saved");
        UndoButton.IsEnabled = session.CanUndo;
        RedoButton.IsEnabled = session.CanRedo;
        AlignUndoButton.IsEnabled = session.CanUndo;
        AlignRedoButton.IsEnabled = session.CanRedo;
        var activeKey = settings.AlignmentProvider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        var providerName = settings.AlignmentProvider == "openrouter" ? "OpenRouter" : "AI Studio";
        ProviderState.Text = activeKey.Length == 0 ? L10n.T("chrome.providerMissing", providerName) : L10n.T("chrome.providerReady", providerName);
        BindPageChrome(CurrentPageTag());
        if (project is not null) PopulateProject(project);
        else
        {
            ExportFinalButton.IsEnabled = false;
            SaveCueSheetButton.IsEnabled = false;
            if (BusyBar.Visibility != Visibility.Visible) ActivityText.Text = L10n.T("activity.none");
        }
        refreshing = false;
    }

    private void PopulateProject(ProjectDocument project)
    {
        BindSource(project);
        BindMetadata(project);
        BindLyrics(project);
        BindTranslation(project);
        BindAlignment(project);
        BindExport(project);
        BindCredits(project);
        ConfigureTimeline(project);
        RefreshInspector();
        UpdateQueueVisuals(Timeline.ActiveSegmentId);
    }

    private void ConfigureTimeline(ProjectDocument project)
    {
        var duration = (double)(project.Target?.DurationMs ?? 1);
        var path = project.Target?.Path;
        if (timelineDuration != duration || audioPath != path)
        {
            timelineDuration = duration;
            Timeline.SetDocument(duration, project.Segments);
            Timeline.SetZoom(2);
            changingZoom = true;
            ZoomSlider.Value = 2;
            ZoomText.Text = "2.0×";
            changingZoom = false;
        }
        else Timeline.SetSegments(project.Segments);
        if (!string.IsNullOrWhiteSpace(path) && audioPath != path) _ = LoadAudioAsync(path);
    }

    private async Task LoadAudioAsync(string path)
    {
        audioPath = path; waveformCancellation?.Cancel(); waveformCancellation?.Dispose();
        waveformCancellation = new CancellationTokenSource();
        try
        {
            var sha = session.Project?.Target?.Fingerprint?.Sha256;
            localAudioPath = WinPaths.Materialize(path, sha);
            BootLog.Append($"audio {path.Length} {path} => {localAudioPath.Length} {localAudioPath}");
            await playback.LoadAsync(localAudioPath); Timeline.Tick(0);
            BootLog.Append("audio playback ok");
            var data = await WaveformAnalyzer.AnalyzeAsync(localAudioPath, token: waveformCancellation.Token);
            BootLog.Append($"audio analyze ok bins={data.Peak.Length}");
            if (audioPath == path)
            {
                data = await AudioVizClient.EnrichAsync(core, localAudioPath, sha, data, Timeline.NeededScales, waveformCancellation.Token);
                Timeline.SetWaveform(data);
            }
        }
        catch (OperationCanceledException) { }
        catch (FileNotFoundException) { await ShowErrorAsync(L10n.T("error.audioMissing", path)); }
        catch (Exception error)
        {
            BootLog.Append($"audio fail hr=0x{error.HResult:X8} {error.GetType().FullName}: {error}");
            await ShowErrorAsync(L10n.T("error.audioLoad", path, error.Message));
        }
    }

    private void Play_Click(object sender, RoutedEventArgs e) => TogglePlay();

    private void GlobalKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Space || !TryHandleSpacePlay()) return;
        e.Handled = true;
    }

    private bool TryHandleSpacePlay()
    {
        if (session.Project is null) return false;
        if (FocusManager.GetFocusedElement(XamlRoot) is TextBox or PasswordBox) return false;
        var now = Environment.TickCount64;
        if (now - lastSpaceToggle < 80) return true;
        lastSpaceToggle = now;
        TogglePlay();
        return true;
    }

    private void TogglePlay()
    {
        var pausing = playback.IsTransportActive || playRequested;
        playRequested = !pausing;
        if (pausing) playback.Pause(); else playback.Play();
        UpdateRendering();
        UpdatePlaybackFrame();
    }

    private bool chromePlaying;

    private void UpdateRendering()
    {
        var playing = playback.IsTransportActive || playRequested;
        if (playing && !rendering) { CompositionTarget.Rendering += RenderingFrame; rendering = true; }
        else if (!playing) StopRendering();
        if (chromePlaying == playing) return;
        chromePlaying = playing;
        var icon = new SymbolIcon(playing ? Symbol.Pause : Symbol.Play);
        PlayButton.Content = icon;
        StatusPlayButton.Content = new SymbolIcon(playing ? Symbol.Pause : Symbol.Play);
    }

    private void StopRendering()
    {
        if (!rendering) return; CompositionTarget.Rendering -= RenderingFrame; rendering = false;
    }

    private void RenderingFrame(object? sender, object e)
    {
        UpdatePlaybackFrame(); if (!playback.IsTransportActive && !playRequested) UpdateRendering();
    }

    private void UpdatePlaybackFrame()
    {
        var position = playback.Tick();
        Timeline.LoopStartMs = playback.LoopStartMs;
        Timeline.LoopEndMs = playback.LoopEndMs;
        Timeline.Tick(position);
        PlaybackTime.Text = FormatTime((ulong)Math.Max(0, position));
        var duration = playback.DurationMs > 0 ? playback.DurationMs : timelineDuration;
        StatusTime.Text = $"{FormatTime((ulong)Math.Max(0, position))} / {FormatTime((ulong)Math.Max(0, duration))}";
        StatusLoop.Text = playback.LoopStartMs is double start && playback.LoopEndMs is double end && end > start
            ? L10n.T("loop.status", FormatTime((ulong)start), FormatTime((ulong)end)) : "";
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

    private async Task ShowErrorAsync(string message) =>
        await new ContentDialog { XamlRoot = XamlRoot, Title = "CueWeave", Content = L10n.WrapError(message), CloseButtonText = L10n.T("action.ok") }.ShowAsync();

    private string CurrentPageTag() => (Navigation.SelectedItem as NavigationViewItem)?.Tag as string ?? "source";
    private static Visibility VisibleIf(bool value) => value ? Visibility.Visible : Visibility.Collapsed;
    private static string? EmptyToNull(string value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static string Join(IEnumerable<string> values, string separator = ", ") => string.Join(separator, values.DefaultIfEmpty("—"));
    private static string FormatTime(ulong? milliseconds) => milliseconds is null ? "—" : $"{milliseconds / 60000:00}:{milliseconds / 1000 % 60:00}.{milliseconds % 1000:000}";
}
