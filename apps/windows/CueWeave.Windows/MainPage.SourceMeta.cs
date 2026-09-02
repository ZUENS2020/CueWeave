using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;

namespace CueWeave.WinUI;

public sealed partial class MainPage
{
    private async void ReplaceTarget_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync(L10n.T("pick.replaceMp3"), ".mp3");
        if (file is not null) await RunAsync(L10n.T("activity.replacingTarget"), token => session.RunProjectCommandAsync("retarget", new System.Text.Json.Nodes.JsonObject { ["target_path"] = file.Path }, token));
    }

    private void BindSource(ProjectDocument project)
    {
        SourceName.Text = Path.GetFileName(project.Source?.Path ?? L10n.T("file.missing"));
        SourcePath.Text = project.Source?.Path ?? L10n.T("file.missing");
        SourceDetails.Text = $"{L10n.T("source.format")}  {project.Source?.Format?.ToUpperInvariant() ?? "NCM"}\n{L10n.T("source.musicId")}  {project.Source?.MusicId?.ToString() ?? "—"}\n{L10n.T("source.duration")}  {FormatTime(project.Source?.DurationMs)}";
        TargetName.Text = Path.GetFileName(project.Target?.Path ?? L10n.T("file.missing"));
        TargetPath.Text = project.Target?.Path ?? L10n.T("file.missing");
        TargetDetails.Text = $"{L10n.T("source.format")}  MP3\n{L10n.T("source.duration")}  {FormatTime(project.Target?.DurationMs)}";
        SourceCoverCaption.Text = project.Metadata.Draft.CoverPath ?? L10n.T("source.remoteCover");
        BindCover(SourceCover, project);
    }

    private void BindMetadata(ProjectDocument project)
    {
        var source = project.Metadata.Source; var target = project.Metadata.Target; var draft = project.Metadata.Draft;
        SourceTitle.Text = source.Title ?? "—"; TargetTitle.Text = target.Title ?? "—"; DraftTitle.Text = draft.Title ?? "";
        SourceArtist.Text = Join(source.Artists); TargetArtist.Text = Join(target.Artists); DraftArtist.Text = Join(draft.Artists, " / ");
        SourceAlbum.Text = source.Album ?? "—"; TargetAlbum.Text = target.Album ?? "—"; DraftAlbum.Text = draft.Album ?? "";
        SourceAlbumArtist.Text = source.AlbumArtist ?? "—"; TargetAlbumArtist.Text = target.AlbumArtist ?? "—"; DraftAlbumArtist.Text = draft.AlbumArtist ?? "";
        SourceDate.Text = source.Date ?? "—"; TargetDate.Text = target.Date ?? "—"; DraftDate.Text = draft.Date ?? "";
        SourceTrack.Text = NumberText(source.Track); TargetTrack.Text = NumberText(target.Track); DraftTrack.Text = draft.Track?.ToString() ?? "";
        SourceDisc.Text = NumberText(source.Disc); TargetDisc.Text = NumberText(target.Disc); DraftDisc.Text = draft.Disc?.ToString() ?? "";
        SourceComposer.Text = source.Composer ?? "—"; TargetComposer.Text = target.Composer ?? "—"; DraftComposer.Text = draft.Composer ?? "";
        SourceLyricist.Text = source.Lyricist ?? "—"; TargetLyricist.Text = target.Lyricist ?? "—"; DraftLyricist.Text = draft.Lyricist ?? "";
        BindCover(MetaCover, project);
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
            project.Metadata.Draft.Composer = EmptyToNull(DraftComposer.Text);
            project.Metadata.Draft.Lyricist = EmptyToNull(DraftLyricist.Text);
            project.Metadata.Draft.Track = ParseOptionalUInt(DraftTrack.Text);
            project.Metadata.Draft.Disc = ParseOptionalUInt(DraftDisc.Text);
        });
    }

    private void AdoptMetadata_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag }) return;
        var parts = tag.Split('|');
        if (parts.Length != 2) return;
        session.AdoptMetadata(parts[0], parts[1] == "source");
    }

    private async void ChooseCover_Click(object sender, RoutedEventArgs e)
    {
        var file = await PickOpenAsync(L10n.T("pick.cover"), ".png", ".jpg", ".jpeg");
        if (file is not null) session.SetCoverPath(file.Path);
    }

    private void BindExport(ProjectDocument project)
    {
        var draft = project.Metadata.Draft;
        ExportSummaryTitle.Text = draft.Title ?? L10n.T("file.untitled");
        ExportSummaryArtist.Text = string.Join(" / ", draft.Artists);
        ExportSummaryAlbum.Text = draft.Album ?? "—";
        ExportSummaryAlbumArtist.Text = draft.AlbumArtist ?? "—";
        ExportSummaryDate.Text = draft.Date ?? "—";
        BindCover(ExportCover, project);
        SaveCueSheetButton.IsEnabled = true;
        ExportFinalButton.IsEnabled = true;
        LrcCheck.IsChecked = project.ExportProfile.Formats.Contains("lrc");
        UsltCheck.IsChecked = project.ExportProfile.Formats.Contains("uslt");
        SyltCheck.IsChecked = project.ExportProfile.Formats.Contains("sylt");
        BilingualPicker.SelectedIndex = project.ExportProfile.Bilingual is "bilingual" or "combined" ? 1 : 0;
        OffsetBox.Value = project.ExportProfile.OffsetMs;
        OffsetBox.Header = L10n.T("export.offset", project.ExportProfile.OffsetMs.ToString());
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

    private void BindCover(Image image, ProjectDocument project)
    {
        var resolved = ResolveCover(project);
        if (resolved is null)
        {
            image.Source = null;
            return;
        }
        try
        {
            var bitmap = new BitmapImage { CreateOptions = BitmapCreateOptions.IgnoreImageCache };
            bitmap.UriSource = resolved.StartsWith("http", StringComparison.OrdinalIgnoreCase)
                ? new Uri(resolved)
                : new Uri(Path.GetFullPath(resolved));
            image.Source = bitmap;
        }
        catch { image.Source = null; }
    }

    private string? ResolveCover(ProjectDocument project)
    {
        var cover = project.Metadata.Draft.CoverPath;
        if (!string.IsNullOrWhiteSpace(cover))
        {
            if (Path.IsPathRooted(cover) && File.Exists(cover)) return cover;
            if (session.ProjectPath is string projectPath)
            {
                var joined = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(projectPath)!, cover));
                if (File.Exists(joined)) return joined;
            }
        }
        return string.IsNullOrWhiteSpace(project.Source?.CoverUrl) ? null : project.Source!.CoverUrl;
    }

    private static string NumberText(uint? value) => value?.ToString() ?? "—";
    private static uint? ParseOptionalUInt(string text) => uint.TryParse(text.Trim(), out var value) ? value : null;
}
