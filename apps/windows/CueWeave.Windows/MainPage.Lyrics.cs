using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;
using Windows.Storage;

namespace CueWeave.WinUI;

public sealed class LineRow
{
    public ulong Id { get; set; }
    public string LineIdText { get; set; } = "";
    public string SegmentIdText { get; set; } = "";
    public string Original { get; set; } = "";
    public string? Translation { get; set; }
}

public sealed partial class MainPage
{
    private async void ImportLyrics_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync(L10n.T("pick.importLyrics"), ".txt", ".lrc", ".yrc");
        if (file is null) return;
        var text = await FileIO.ReadTextAsync(file);
        await RunAsync(L10n.T("activity.applyingLyrics"), token => session.RunProjectCommandAsync("replace_lyrics", new JsonObject { ["original"] = text, ["translation"] = "" }, token));
    }

    private async void AddLyrics_Click(object sender, RoutedEventArgs e) =>
        await PromptInsertLyricsAsync(session.Project?.Lyrics.Lines.LastOrDefault()?.Id);

    private async void InsertAtStart_Click(object sender, RoutedEventArgs e) => await PromptInsertLyricsAsync(null, atStart: true);

    private async void InsertAfter_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement element && element.DataContext is LineRow row)
            await PromptInsertLyricsAsync(row.Id);
        else if (sender is FrameworkElement lineElement && lineElement.DataContext is LyricLine line)
            await PromptInsertLyricsAsync(line.Id);
    }

    private async Task PromptInsertLyricsAsync(ulong? preferredAfter, bool atStart = false)
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
        var preferredIndex = atStart ? 0 : preferredAfter is ulong id ? lines.FindIndex(line => line.Id == id) + 1 : 0;
        positions.SelectedIndex = preferredIndex > 0 ? preferredIndex : atStart ? 0 : lines.Count;
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

    private async void RequestPreview_Click(object sender, RoutedEventArgs e)
    {
        if (session.Project is null) return;
        var lines = session.Project.Lyrics.Lines;
        var list = new ListView { Height = 360 };
        foreach (var line in lines)
        {
            list.Items.Add($"{(line.Segments.FirstOrDefault()?.Id ?? 0):0000}  {line.Original}");
        }
        var pills = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        pills.Children.Add(new TextBlock { Text = L10n.T("lyrics.noSourceTiming"), FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), FontSize = 11 });
        pills.Children.Add(new TextBlock { Text = L10n.T("lyrics.noCreditsPill"), FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), FontSize = 11 });
        pills.Children.Add(new TextBlock { Text = L10n.T("lyrics.linesPill", lines.Count.ToString()), FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), FontSize = 11 });
        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(pills);
        content.Children.Add(list);
        await new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = L10n.T("lyrics.previewTitle"),
            Content = content,
            CloseButtonText = L10n.T("action.done")
        }.ShowAsync();
    }

    private void OpenTranslation_Click(object sender, RoutedEventArgs e) => Navigation.SelectedItem = NavTranslation;

    private void BindLyrics(ProjectDocument project)
    {
        var empty = project.Lyrics.Lines.Count == 0;
        LyricsEmpty.Visibility = VisibleIf(empty);
        LyricsSplit.Visibility = VisibleIf(!empty);
        RequestPreviewButton.IsEnabled = !empty;
        FetchLyricsButton.IsEnabled = project.Source?.MusicId is not null;
        LyricsEmptyFetch.IsEnabled = project.Source?.MusicId is not null;
        LyricsNoCredits.Visibility = VisibleIf(project.Lyrics.Credits.Count == 0);
        LyricsCreditsList.ItemsSource = project.Lyrics.Credits;
        var translated = project.Lyrics.Lines.Count(line => !string.IsNullOrWhiteSpace(line.Translation));
        LyricsTranslationPill.Text = translated > 0 ? L10n.T("lyrics.translationCount", translated.ToString()) : L10n.T("lyrics.optional");
        OpenTranslationButton.IsEnabled = !empty;
        LyricsLinesMeta.Text = L10n.T("lyrics.linesMeta", project.Lyrics.Lines.Count.ToString(), project.Segments.Count.ToString());
        LyricsList.ItemsSource = project.Lyrics.Lines.Select(ToLineRow).ToList();
    }

    private void LyricOriginal_LostFocus(object sender, RoutedEventArgs e)
    {
        if (refreshing || sender is not TextBox { DataContext: LineRow row } box) return;
        session.SetLineOriginal(row.Id, box.Text);
    }

    private async void Translate_Click(object sender, RoutedEventArgs e)
    {
        var provider = settings.AlignmentProvider;
        var key = provider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        var model = provider == "openrouter" ? settings.OpenRouterModel : settings.AiStudioModel;
        if (string.IsNullOrWhiteSpace(key)) { await ShowErrorAsync(L10n.T("error.needApiKey")); return; }
        var title = provider == "openrouter" ? "OpenRouter" : "AI Studio";
        await RunAsync(L10n.T("activity.translating", title), token => session.RunProjectCommandAsync("translate", new JsonObject {
            ["provider"] = provider, ["api_key"] = key, ["model"] = model, ["target_language"] = TargetLanguageBox.Text
        }, token));
    }

    private async void ImportTranslations_Click(object sender, RoutedEventArgs e)
    {
        var box = new TextBox { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Height = 220 };
        var hint = new TextBlock { Text = L10n.T("translation.lineOrder"), Opacity = .75 };
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(hint);
        panel.Children.Add(new TextBlock { Text = L10n.T("translation.originalLines", (session.Project?.Lyrics.Lines.Count ?? 0).ToString()), FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"), FontSize = 11 });
        panel.Children.Add(box);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = L10n.T("translation.importTitle"),
            Content = panel,
            PrimaryButtonText = L10n.T("action.apply"),
            CloseButtonText = L10n.T("action.cancel")
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (string.IsNullOrWhiteSpace(box.Text)) return;
        await RunAsync(L10n.T("activity.applyingTranslations"), token => session.RunProjectCommandAsync("replace_translations", new JsonObject { ["translation"] = box.Text }, token));
    }

    private void ClearTranslations_Click(object sender, RoutedEventArgs e) => session.ClearTranslations();

    private void Translation_LostFocus(object sender, RoutedEventArgs e)
    {
        if (refreshing || sender is not TextBox { DataContext: LineRow row } box) return;
        session.SetLineTranslation(row.Id, box.Text);
    }

    private void BindTranslation(ProjectDocument project)
    {
        var empty = project.Lyrics.Lines.Count == 0;
        TranslationEmpty.Visibility = VisibleIf(empty);
        TranslationSplit.Visibility = VisibleIf(!empty);
        ImportTranslationButton.IsEnabled = !empty;
        TranslateButton.IsEnabled = !empty;
        var providerName = settings.AlignmentProvider == "openrouter" ? "OpenRouter" : "AI Studio";
        TranslateButton.Content = L10n.T("translation.translateWith", providerName);
        TranslationProviderPill.Text = providerName;
        var key = settings.AlignmentProvider == "openrouter" ? settings.OpenRouterApiKey : settings.AiStudioApiKey;
        TranslationKeyPill.Text = key.Length == 0 ? L10n.T("settings.keyMissing") : L10n.T("translation.sameKey");
        var translated = project.Lyrics.Lines.Count(line => !string.IsNullOrWhiteSpace(line.Translation));
        TranslationCoveragePill.Text = translated > 0
            ? L10n.T("translation.coverageCount", translated.ToString(), project.Lyrics.Lines.Count.ToString())
            : L10n.T("translation.none");
        ClearTranslationButton.IsEnabled = translated > 0;
        TranslationLinesCount.Text = L10n.T("translation.linesCount", project.Lyrics.Lines.Count.ToString());
        TranslationList.ItemsSource = project.Lyrics.Lines.Select(ToLineRow).ToList();
    }

    private static LineRow ToLineRow(LyricLine line) => new()
    {
        Id = line.Id,
        LineIdText = line.Id.ToString("000"),
        SegmentIdText = $"ID {(line.Segments.FirstOrDefault()?.Id ?? 0):0000}",
        Original = line.Original,
        Translation = line.Translation
    };
}
