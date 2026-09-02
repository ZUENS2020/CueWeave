using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;

namespace CueWeave.WinUI;

public sealed class CreditRow
{
    public ulong Id { get; set; }
    public ulong TimeMs { get; set; }
    public string Text { get; set; } = "";
    public string Time { get; set; } = "";
}

public sealed partial class MainPage
{
    private void BindCredits(ProjectDocument project)
    {
        var rows = project.Lyrics.Credits.Select(credit => {
            var time = CreditTime(project, credit.Id);
            return new CreditRow
            {
                Id = credit.Id,
                TimeMs = time,
                Text = credit.DisplayText,
                Time = FormatCreditTime(time)
            };
        }).ToList();
        CreditsList.ItemsSource = rows;
        LyricsCreditsList.ItemsSource = project.Lyrics.Credits;
        Timeline.SetCredits([.. rows.Select(row => (row.Id, row.TimeMs, row.Text))]);
        var tooShort = CreditIntroTooShort(project);
        CreditIntroBanner.Visibility = tooShort ? Visibility.Visible : Visibility.Collapsed;
        CreditIntroText.Text = L10n.T("credit.introTooShort");
        MergeCreditsButton.Content = L10n.T("credit.merge");
    }

    private static bool CreditIntroTooShort(ProjectDocument project)
    {
        var times = project.Lyrics.Credits.Select(credit => CreditTime(project, credit.Id)).ToList();
        if (times.Count < 2 || times.Exists(time => time != 0)) return false;
        ulong first = 0;
        foreach (var segment in project.Segments)
        {
            var point = segment.Timing.Final ?? segment.Timing.Gemini;
            if (point is null) continue;
            if (first == 0 || point.TimeMs < first) first = point.TimeMs;
        }
        return first > 0 && first < 500 + 1_500 * (ulong)times.Count;
    }

    private void MergeCredits_Click(object sender, RoutedEventArgs e) => session.MergeCredits();

    private static ulong CreditTime(ProjectDocument project, ulong id)
    {
        foreach (var cue in project.Timeline)
        {
            if (cue.ValueKind == System.Text.Json.JsonValueKind.Object
                && cue.TryGetProperty("type", out var type)
                && type.GetString() == "credit"
                && cue.TryGetProperty("credit_id", out var creditId)
                && creditId.GetUInt64() == id
                && cue.TryGetProperty("time_ms", out var time))
            {
                return time.GetUInt64();
            }
        }
        return 0;
    }

    private static string FormatCreditTime(ulong ms) =>
        $"{ms / 60_000:00}:{ms / 1_000 % 60:00}.{ms % 1_000:000}";

    private void CreditsList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is CreditRow row) Timeline.SelectCredit(row.Id);
    }

    private void AddCredit_Click(object sender, RoutedEventArgs e) => session.AddCredit();

    private void RemoveCredit_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: Credit credit }) session.RemoveCredit(credit.Id);
    }

    private void CreditLabel_LostFocus(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox { DataContext: Credit credit } box)
            session.Mutate(document => {
                var item = document.Lyrics.Credits.FirstOrDefault(value => value.Id == credit.Id);
                if (item is not null) item.Label = box.Text;
            });
    }

    private void CreditValue_LostFocus(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox { DataContext: Credit credit } box)
            session.Mutate(document => {
                var item = document.Lyrics.Credits.FirstOrDefault(value => value.Id == credit.Id);
                if (item is not null) item.Value = box.Text;
            });
    }

    private async Task ReloadSpectrogramAsync()
    {
        if (string.IsNullOrWhiteSpace(audioPath) || !Timeline.NeedsSpectrogram) return;
        try
        {
            var sha = session.Project?.Target?.Fingerprint?.Sha256;
            var data = await AudioVizClient.EnrichAsync(
                core,
                localAudioPath ?? audioPath,
                sha,
                Timeline.CurrentWaveform,
                Timeline.NeededScales,
                waveformCancellation?.Token ?? CancellationToken.None);
            Timeline.SetWaveform(data);
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { await ShowErrorAsync(L10n.T("error.audioAnalysis", error.Message)); }
    }
}
