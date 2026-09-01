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
        SaveButton.Label = L10n.T("action.save");
        RevertButton.Label = L10n.T("action.revert");
        UndoButton.Label = L10n.T("action.undo");
        RedoButton.Label = L10n.T("action.redo");
        SettingsButton.Label = L10n.T("action.settingsProvider");
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
        SourceRole.Text = L10n.T("source.infoRole");
        TargetRole.Text = L10n.T("source.targetRole");
        ReplaceTargetButton.Content = L10n.T("source.replace");
        MetadataHeading.Text = L10n.T("page.metadata");
        MetadataSubtitle.Text = L10n.T("page.metadata.subtitle");
        MetaColSource.Text = L10n.T("meta.source");
        MetaColTarget.Text = L10n.T("meta.target");
        MetaColDraft.Text = L10n.T("meta.draftExported");
        MetaLabelTitle.Text = L10n.T("meta.title");
        MetaLabelArtist.Text = L10n.T("meta.artist");
        MetaLabelAlbum.Text = L10n.T("meta.album");
        MetaLabelAlbumArtist.Text = L10n.T("meta.albumArtist");
        MetaLabelDate.Text = L10n.T("meta.date");
        LyricsHeading.Text = L10n.T("page.lyrics");
        LyricsSubtitle.Text = L10n.T("page.lyrics.subtitle.win");
        ImportLyricsButton.Content = L10n.T("lyrics.import");
        AddLyricsButton.Content = L10n.T("lyrics.addLines");
        FetchLyricsButton.Content = L10n.T("lyrics.fetchNetease");
        TranslationHeading.Text = L10n.T("page.translation");
        TranslationSubtitle.Text = L10n.T("page.translation.subtitle.win");
        TargetLanguageBox.PlaceholderText = L10n.T("translation.targetLanguage");
        var nextDefault = L10n.T("translation.targetDefault");
        if (string.IsNullOrWhiteSpace(TargetLanguageBox.Text) || TargetLanguageBox.Text == translationDefault)
            TargetLanguageBox.Text = nextDefault;
        translationDefault = nextDefault;
        ImportTranslationButton.Content = L10n.T("translation.import");
        ClearTranslationButton.Content = L10n.T("translation.clearAll");
        TranslateButton.Content = L10n.T("translation.translateGemini");
        PlayButton.Label = L10n.T("hotkey.playPause");
        ToolTipService.SetToolTip(LoopAButton, L10n.T("loop.a.help.win"));
        ToolTipService.SetToolTip(LoopBButton, L10n.T("loop.b.help.win"));
        LoopClearButton.Content = L10n.T("action.clear");
        FollowButton.Content = L10n.T("follow");
        ToolTipService.SetToolTip(FollowButton, L10n.T("follow.help.win"));
        NextButton.Content = L10n.T("next");
        ToolTipService.SetToolTip(NextButton, L10n.T("next.help.win"));
        MarkButton.Content = L10n.T("mark");
        AlignButton.Content = L10n.T("align.runGemini");
        RestoreButton.Content = L10n.T("align.restoreAI");
        HotkeyHintButton.Label = L10n.T("hotkey.windowsHint");
        PlayAroundButton.Content = L10n.T("inspect.playAround");
        UseGeminiButton.Content = L10n.T("inspect.useGemini");
        ExportHeading.Text = L10n.T("export.title");
        ExportHint.Text = L10n.T("export.outputHint.win");
        SaveCueSheetButton.Content = L10n.T("export.saveCueSheet");
        ExportFinalButton.Content = L10n.T("export.exportFinal");
        AdaptersLabel.Text = L10n.T("export.adapters");
        LrcCheck.Content = L10n.T("export.lrcCheck");
        UsltCheck.Content = L10n.T("export.usltCheck");
        SyltCheck.Content = L10n.T("export.syltCheck");
        BilingualLabel.Text = L10n.T("export.bilingual");
        BilingualOriginal.Content = L10n.T("export.originalOnly");
        BilingualCombined.Content = L10n.T("export.combinedWin");
        OffsetBox.Header = L10n.T("export.offsetHeader");
        OverwriteCheck.Content = L10n.T("export.overwriteExisting");
        ToolTipService.SetToolTip(OverwriteCheck, L10n.T("export.overwriteExistingHint"));
        CancelButton.Content = L10n.T("action.cancel");
        Timeline.LocalizeLanes(L10n.T);
        if (LyricsCreditsLabel is not null) LyricsCreditsLabel.Text = L10n.T("align.credits");
        if (AddCreditButton is not null) AddCreditButton.Content = L10n.T("lyrics.credits");
        if (MergeCreditsButton is not null) MergeCreditsButton.Content = L10n.T("credit.merge");
        if (CreditIntroText is not null) CreditIntroText.Text = L10n.T("credit.introTooShort");
    }
}
