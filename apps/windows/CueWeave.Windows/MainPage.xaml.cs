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
    private bool refreshQueued;
    private bool rendering;
    private bool changingZoom;
    private string? audioPath;
    private string? localAudioPath;
    private double timelineDuration;
    private readonly HashSet<ulong> batchIds = [];
    private bool playRequested;
    private bool projectPickerActive;

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
        ZoomSlider.Maximum = TimelineViewport.MaximumZoom;
        ZoomSlider.StepFrequency = .5;
        ZoomSlider.Value = 2;
        PlayButton.Content = new SymbolIcon(Symbol.Play);
        StatusPlayButton.Content = new SymbolIcon(Symbol.Play);
        var save = new KeyboardAccelerator { Key = VirtualKey.S, Modifiers = VirtualKeyModifiers.Control };
        save.Invoked += (_, args) =>
        {
            if (session.Project is null || operationCancellation is not null || KeyOwner() == ShortcutOwner.Modal) return;
            args.Handled = true; Save_Click(this, new RoutedEventArgs());
        };
        KeyboardAccelerators.Add(save);
        PreviewKeyDown += GlobalKeyDown;
        PreviewKeyUp += Timeline.HandleKeyUp;
        LostFocus += (_, _) => Timeline.ResetHeldKeys();
        SpeedPicker.DropDownClosed += (_, _) => Timeline.Focus(FocusState.Programmatic);
        InspectorLyricBox.GotFocus += (_, _) => SetFollowSelection(false);
        IsTabStop = true;
        AddHandler(PointerPressedEvent, new PointerEventHandler(DismissEditor), true);
        playback.StateChanged += () => DispatcherQueue.TryEnqueue(() =>
        {
            if (playback.IsPlaying || !playback.IsTransportActive) playRequested = false;
            UpdateRendering();
            UpdatePlaybackFrame();
        });
        BindChrome();
        Loaded += (_, _) => { UpdateNavigationPane(); App.MainWindow.Activated += Window_Activated; };
        session.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName is nameof(ProjectSession.Project) or nameof(ProjectSession.ProjectPath))
            {
                if (refreshQueued) return;
                refreshQueued = true;
                DispatcherQueue.TryEnqueue(() => { refreshQueued = false; Refresh(); });
            }
            else RefreshState();
        };
        Timeline.SeekRequested += time => { playback.Seek(time); UpdatePlaybackFrame(); };
        Timeline.NudgeRequested += NudgeSelected;
        Timeline.CommandRequested += HandleTimelineCommand;
        Timeline.VisualizationChanged += () => _ = ReloadSpectrogramAsync();
        Timeline.ActiveSegmentChanged += id =>
        {
            UpdateQueueVisuals(id);
            if (NextButton.IsChecked == true) FollowNextIfNeeded(id);
            else if (id is ulong value) ScrollToSegment(value);
        };
        Timeline.SelectedSegmentChanged += id =>
        {
            RefreshInspector(); UpdateQueueVisuals(Timeline.ActiveSegmentId);
            if (id is ulong value) ScrollToSegment(value);
        };
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
        Unloaded += (_, _) =>
        {
            App.MainWindow.Activated -= Window_Activated;
            Timeline.ResetHeldKeys(); StopRendering(); waveformCancellation?.Cancel();
        };
        Refresh();
    }

    private async void NewProject_Click(object sender, RoutedEventArgs e)
    {
        if (projectPickerActive || operationCancellation is not null) return;
        projectPickerActive = true;
        try
        {
            var source = await PickOpenAsync(L10n.T("pick.ncm"), ".ncm");
            if (source is null) return;
            var target = await PickOpenAsync(L10n.T("pick.mp3"), ".mp3");
            if (target is null) return;
            var output = await PickSaveAsync(L10n.T("pick.project"), ".cueweave", Path.GetFileNameWithoutExtension(target.Name));
            if (output is null) return;
            await RunAsync(L10n.T("activity.creating"), async token =>
            {
                await session.SaveAsync(token);
                await session.CreateAsync(output.Path, source.Path, target.Path, token);
            });
        }
        finally { projectPickerActive = false; }
    }

    private async void OpenProject_Click(object sender, RoutedEventArgs e)
    {
        if (projectPickerActive || operationCancellation is not null) return;
        projectPickerActive = true;
        try
        {
            var file = await PickOpenAsync(L10n.T("pick.openProject"), ".cueweave");
            if (file is not null) await RunAsync(L10n.T("activity.opening"), async token =>
            {
                await session.SaveAsync(token);
                await session.LoadAsync(file.Path, token);
            });
        }
        finally { projectPickerActive = false; }
    }

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        Focus(FocusState.Programmatic); // Commit the focused editor before Ctrl+S.
        await RunAsync(L10n.T("activity.saving"), session.SaveAsync);
    }
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

    private void NavigationPane_Changed(NavigationView sender, object args) => UpdateNavigationPane();

    private void UpdateNavigationPane()
    {
        // Compact navigation has room for icons only, not clipped project/provider text.
        if (PaneHeading is null || PaneProvider is null) return;
        PaneHeading.Visibility = PaneProvider.Visibility = VisibleIf(Navigation.IsPaneOpen);
    }

    private void ExportColumns_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (ExportOptionsCard is null) return;
        var stacked = e.NewSize.Width < 840;
        ExportOptionsColumn.Width = new GridLength(stacked ? 0 : 320);
        ExportColumns.ColumnSpacing = stacked ? 0 : 18;
        Grid.SetColumn(ExportOptionsCard, stacked ? 0 : 1);
        Grid.SetRow(ExportOptionsCard, stacked ? 1 : 0);
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) { operationCancellation?.Cancel(); core.Cancel(); }

    private async Task RunAsync(string label, Func<CancellationToken, Task> operation)
    {
        if (operationCancellation is not null) return;
        operationCancellation = new CancellationTokenSource();
        SetBusy(true, label);
        try { await operation(operationCancellation.Token); ActivityText.Text = L10n.T("activity.doneFmt", label); }
        catch (OperationCanceledException) { ActivityText.Text = L10n.T("activity.cancelled"); }
        catch (Exception error) { ActivityText.Text = L10n.T("activity.failed"); await ShowErrorAsync(error.Message); }
        finally
        {
            operationCancellation.Dispose(); operationCancellation = null;
            SetBusy(false, ActivityText.Text); Refresh();
        }
    }

    private void SetBusy(bool busy, string activity)
    {
        BusyBar.Visibility = VisibleIf(busy);
        CancelButton.Visibility = VisibleIf(busy);
        Navigation.IsEnabled = !busy;
        NewButton.IsEnabled = OpenButton.IsEnabled = SettingsButton.IsEnabled = !busy;
        WelcomeNew.IsEnabled = WelcomeOpen.IsEnabled = !busy;
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
        RefreshState();
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

    private void RefreshState()
    {
        SaveStateText.Text = session.Project is null ? L10n.T("status.noProject") : session.IsDirty ? L10n.T("status.edited") : L10n.T("status.saved");
        UndoButton.IsEnabled = AlignUndoButton.IsEnabled = session.CanUndo;
        RedoButton.IsEnabled = AlignRedoButton.IsEnabled = session.CanRedo;
    }

    private void DismissEditor(object sender, PointerRoutedEventArgs args)
    {
        if (KeyOwner() is not (ShortcutOwner.Editor or ShortcutOwner.NativeControl)) return;
        for (var node = args.OriginalSource as DependencyObject; node is not null && node != this;
            node = VisualTreeHelper.GetParent(node))
            if (node is TextBox or PasswordBox or RichEditBox or ContentDialog
                or Microsoft.UI.Xaml.Controls.Primitives.ButtonBase or ComboBox or NumberBox) return;
        Focus(FocusState.Pointer);
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

    private void Window_Activated(object sender, WindowActivatedEventArgs e)
    {
        if (e.WindowActivationState == WindowActivationState.Deactivated) Timeline.ResetHeldKeys();
    }

    private void GlobalKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (session.Project is null || BusyBar.Visibility == Visibility.Visible) return;
        // Text editors and dialogs own their keys; all other alignment surfaces
        // share the same shortcuts, including the left lyric list.
        if (TimelineKeyboard.IsReserved(e.Key, KeyOwner())) { Timeline.ResetHeldKeys(); return; }
        var control = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        var shift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        var alt = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Menu)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        if (alt) return;
        if (control && e.Key is VirtualKey.Z or VirtualKey.Y)
        {
            if (e.Key == VirtualKey.Y || shift) session.Redo(); else session.Undo();
            e.Handled = true;
        }
        else if (!control && !shift && e.Key == VirtualKey.Space)
        {
            if (!e.KeyStatus.WasKeyDown) TogglePlay();
            e.Handled = true;
        }
        else if (CurrentPageTag() == "alignment") Timeline.HandleKeyDown(sender, e);
    }

    private ShortcutOwner KeyOwner()
    {
        if (projectPickerActive) return ShortcutOwner.Modal;
        // A tooltip must not disable the entire keyboard. Menus/dialogs still own their keys.
        if (VisualTreeHelper.GetOpenPopupsForXamlRoot(XamlRoot).Any(popup => popup.Child is not ToolTip))
            return ShortcutOwner.Modal;
        for (var node = FocusManager.GetFocusedElement(XamlRoot) as DependencyObject;
            node is not null; node = VisualTreeHelper.GetParent(node))
        {
            if (node is ContentDialog) return ShortcutOwner.Modal;
            if (node is TextBox or PasswordBox or RichEditBox) return ShortcutOwner.Editor;
            if (node is ComboBox or Slider) return ShortcutOwner.NativeControl;
        }
        return ShortcutOwner.Workspace;
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
