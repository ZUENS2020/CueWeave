using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using CueWeave.WinUI.Services;

namespace CueWeave.WinUI;

public sealed partial class MainPage
{
    private string translationDefault = "";

    private void BindChrome()
    {
        NewButton.Label = L10n.T("action.newShort");
        OpenButton.Label = L10n.T("action.openShort");
        UndoButton.Label = L10n.T("action.undo");
        RedoButton.Label = L10n.T("action.redo");
        SettingsButton.Label = L10n.T("action.settings");
        NavSource.Content = L10n.T("page.source");
        NavMetadata.Content = L10n.T("page.metadata");
        NavLyrics.Content = L10n.T("page.lyrics");
        NavTranslation.Content = L10n.T("page.translation");
        NavAlignment.Content = L10n.T("page.alignment");
        NavExport.Content = L10n.T("page.export");
        PaneFooterLabel.Text = L10n.T("chrome.alignmentProvider");
        WelcomeKicker.Text = L10n.T("welcome.kicker");
        WelcomeHeadline.Text = L10n.T("welcome.headline");
        WelcomeBody.Text = L10n.T("welcome.body");
        WelcomeNew.Content = L10n.T("welcome.new");
        WelcomeOpen.Content = L10n.T("welcome.open");
        WelcomePipeline.Text = L10n.T("welcome.pipeline");
        SourceHeading.Text = L10n.T("page.source");
        SourceSubtitle.Text = L10n.T("page.source.subtitle");
        TimingAuthorityText.Text = L10n.T("source.timingAuthority");
        SourceCoverLabel.Text = L10n.T("source.referenceCover");
        SourceRole.Text = L10n.T("source.infoRole");
        TargetRole.Text = L10n.T("source.targetRole");
        SourceFixedButton.Content = L10n.T("source.fixed");
        ToolTipService.SetToolTip(SourceFixedButton, L10n.T("source.help.fixed"));
        ReplaceTargetButton.Content = L10n.T("source.replace");
        TimingIsolationTitle.Text = L10n.T("source.timingIsolation");
        TimingIsolationBody.Text = L10n.T("source.timingIsolationBody");
        MetadataHeading.Text = L10n.T("page.metadata");
        MetadataSubtitle.Text = L10n.T("page.metadata.subtitle");
        MetaCoverLabel.Text = L10n.T("meta.draftCover");
        ChooseCoverButton.Content = L10n.T("meta.chooseCover");
        MetaCoverHint.Text = L10n.T("meta.coverHint");
        MetaColField.Text = L10n.T("meta.field");
        MetaColSource.Text = L10n.T("meta.source");
        MetaColTarget.Text = L10n.T("meta.target");
        MetaColDraft.Text = L10n.T("meta.draft");
        MetaLabelTitle.Text = L10n.T("meta.title");
        MetaLabelArtist.Text = L10n.T("meta.artist");
        MetaLabelAlbum.Text = L10n.T("meta.album");
        MetaLabelAlbumArtist.Text = L10n.T("meta.albumArtist");
        MetaLabelDate.Text = L10n.T("meta.date");
        MetaAdvancedLabel.Text = L10n.T("meta.advanced");
        MetaLabelTrack.Text = L10n.T("meta.track");
        MetaLabelDisc.Text = L10n.T("meta.disc");
        MetaLabelComposer.Text = L10n.T("meta.composer");
        MetaLabelLyricist.Text = L10n.T("meta.lyricist");
        LyricsHeading.Text = L10n.T("page.lyrics");
        LyricsSubtitle.Text = L10n.T("page.lyrics.subtitle");
        ImportLyricsButton.Content = L10n.T("lyrics.import");
        AddLyricsButton.Content = L10n.T("lyrics.addLines");
        FetchLyricsButton.Content = L10n.T("lyrics.fetchNetease");
        RequestPreviewButton.Content = L10n.T("lyrics.requestPreview");
        LyricsEmptyTitle.Text = L10n.T("lyrics.emptyTitle");
        LyricsEmptyDetail.Text = L10n.T("lyrics.emptyDetail");
        LyricsEmptyAdd.Content = L10n.T("lyrics.addLines");
        LyricsEmptyImport.Content = L10n.T("lyrics.import");
        LyricsEmptyFetch.Content = L10n.T("lyrics.fetchNetease");
        LyricsNoCredits.Text = L10n.T("lyrics.noCredits");
        LyricsCreditsNote.Text = L10n.T("lyrics.creditsNote");
        LyricsTranslationLabel.Text = L10n.T("lyrics.translation");
        LyricsTranslationHint.Text = L10n.T("lyrics.translationHint");
        OpenTranslationButton.Content = L10n.T("lyrics.openTranslation");
        LyricsLinesLabel.Text = L10n.T("lyrics.lines");
        InsertAtStartButton.Content = L10n.T("lyrics.insertHere");
        TranslationHeading.Text = L10n.T("page.translation");
        TranslationSubtitle.Text = L10n.T("page.translation.subtitle");
        TargetLanguageBox.PlaceholderText = L10n.T("translation.targetLanguage");
        var nextDefault = L10n.T("translation.targetDefault");
        if (string.IsNullOrWhiteSpace(TargetLanguageBox.Text) || TargetLanguageBox.Text == translationDefault)
            TargetLanguageBox.Text = nextDefault;
        translationDefault = nextDefault;
        ImportTranslationButton.Content = L10n.T("translation.import");
        ClearTranslationButton.Content = L10n.T("translation.clearAll");
        TranslationEmptyTitle.Text = L10n.T("translation.emptyTitle");
        TranslationEmptyDetail.Text = L10n.T("translation.emptyDetail");
        TranslationProviderLabel.Text = L10n.T("translation.gemini");
        TranslationGeminiHint.Text = L10n.T("translation.geminiHint");
        TranslationCoverageLabel.Text = L10n.T("translation.coverage");
        TranslationCoverageHint.Text = L10n.T("translation.coverageHint");
        TranslationLineHeader.Text = L10n.T("translation.lineHeader");
        AlignHeading.Text = L10n.T("timeline.title").ToUpperInvariant();
        AlignSubtitle.Text = L10n.T("page.alignment.subtitle");
        RestoreButton.Content = L10n.T("align.restoreGemini");
        ToolTipService.SetToolTip(RestoreButton, L10n.T("align.restoreHelp"));
        AlignEmptyTitle.Text = L10n.T("align.emptyTitle");
        AlignEmptyDetail.Text = L10n.T("align.emptyDetail");
        SegmentsLabel.Text = L10n.T("align.segments");
        CreditsSectionLabel.Text = L10n.T("align.credits");
        LyricsSectionLabel.Text = L10n.T("align.lyricsSection");
        BatchAllButton.Content = L10n.T("align.allBtn");
        BatchClearButton.Content = L10n.T("action.clear");
        BatchClearFinalButton.Content = L10n.T("align.clearFinal");
        InspectEmptyTitle.Text = L10n.T("inspect.emptyTitle");
        InspectEmptyDetail.Text = L10n.T("inspect.emptyDetail");
        CreditInspectorLabel.Text = L10n.T("align.credits");
        CreditMarkButton.Content = L10n.T("inspect.markPlayhead");
        InspectorLyricLabel.Text = L10n.T("inspect.lyricText");
        InspectorLyricBox.PlaceholderText = L10n.T("inspect.lyricPlaceholder");
        InspectorClearFinal.Content = L10n.T("align.clearFinal");
        ToolTipService.SetToolTip(PlayButton, L10n.T("hotkey.playPause"));
        ToolTipService.SetToolTip(LoopAButton, L10n.T("loop.a.help"));
        ToolTipService.SetToolTip(LoopBButton, L10n.T("loop.b.help"));
        LoopClearButton.Content = L10n.T("action.clear");
        FollowButton.Content = L10n.T("follow");
        ToolTipService.SetToolTip(FollowButton, L10n.T("follow.help"));
        NextButton.Content = L10n.T("next");
        ToolTipService.SetToolTip(NextButton, L10n.T("next.help"));
        MarkButton.Content = L10n.T("mark");
        AlignUndoButton.Content = L10n.T("action.undo");
        AlignRedoButton.Content = L10n.T("action.redo");
        HotkeyHint.Text = L10n.T("hotkey.windowsHint");
        PlayAroundButton.Content = L10n.T("inspect.playAround");
        UseGeminiButton.Content = L10n.T("inspect.useGemini");
        ExportHeading.Text = L10n.T("export.title");
        ExportSubtitle.Text = L10n.T("page.export.subtitle");
        ExportHint.Text = L10n.T("export.outputHint");
        ExportOutputLabel.Text = L10n.T("export.output");
        SaveCueSheetButton.Content = L10n.T("export.saveCueSheet");
        ExportFinalButton.Content = L10n.T("export.exportFinal");
        AdaptersLabel.Text = L10n.T("export.adapters");
        LrcCheckTitle.Text = L10n.T("export.lrcCheck");
        LrcCheckDetail.Text = L10n.T("export.lrc");
        UsltCheckTitle.Text = L10n.T("export.usltCheck");
        UsltCheckDetail.Text = L10n.T("export.uslt");
        SyltCheckTitle.Text = L10n.T("export.syltCheck");
        SyltCheckDetail.Text = L10n.T("export.sylt");
        BilingualLabel.Text = L10n.T("export.bilingual");
        BilingualOriginal.Content = L10n.T("export.originalOnly");
        BilingualCombined.Content = L10n.T("export.combined");
        OverwriteTitle.Text = L10n.T("export.overwriteExisting");
        OverwriteHint.Text = L10n.T("export.overwriteExistingHint");
        AdaptersNote.Text = L10n.T("export.adaptersNote");
        ExportProtectPill.Text = L10n.T("export.protectTarget");
        ExportReencodePill.Text = L10n.T("export.noReencode");
        ExportAtomicPill.Text = L10n.T("export.atomic");
        ExportAlbumLabel.Text = L10n.T("meta.albumLabel");
        ExportAlbumArtistLabel.Text = L10n.T("meta.albumArtistLabel");
        ExportReleaseLabel.Text = L10n.T("meta.release");
        CancelButton.Content = L10n.T("action.cancel");
        Timeline.LocalizeLanes(key => L10n.T(key));
        LyricsCreditsLabel.Text = L10n.T("align.credits");
        AddCreditButton.Content = "+";
        MergeCreditsButton.Content = L10n.T("credit.merge");
        CreditIntroText.Text = L10n.T("credit.introTooShort");
        BindPageChrome(session.Project is null ? null : CurrentPageTag());
    }

    private void BindPageChrome(string? tag)
    {
        if (session.Project is null)
        {
            ChromePageTitle.Text = "CUEWEAVE";
            ChromePageDetail.Text = L10n.T("welcome.headline.one");
            return;
        }
        ChromePageTitle.Text = L10n.T(tag switch
        {
            "source" => "page.source",
            "metadata" => "page.metadata",
            "lyrics" => "page.lyrics",
            "translation" => "page.translation",
            "alignment" => "page.alignment",
            "export" => "page.export",
            _ => "page.source"
        }).ToUpperInvariant();
        ChromePageDetail.Text = L10n.T(tag switch
        {
            "source" => "page.source.subtitle",
            "metadata" => "page.metadata.subtitle",
            "lyrics" => "page.lyrics.subtitle",
            "translation" => "page.translation.subtitle",
            "alignment" => "page.alignment.subtitle",
            "export" => "page.export.subtitle",
            _ => "page.source.subtitle"
        });
    }
}
