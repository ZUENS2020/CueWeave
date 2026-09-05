using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using CueWeave.WinUI.Services;

namespace CueWeave.WinUI;

public sealed partial class MainPage
{
    private async void Hotkeys_Click(object sender, RoutedEventArgs e)
    {
        var content = new StackPanel { Spacing = 12, MaxWidth = 480 };
        foreach (var key in new[] { "play", "selectPlaying", "selectNext", "selectPrev", "followNext", "followCurrent", "mark",
            "clearFinal", "nextPrev", "movePlayhead", "nudge1", "nudge10", "nudge50", "nudgeComma", "jump",
            "speed", "zoom.win", "loopA", "loopB", "loopClear", "undo.win", "redo.win", "clickAway" })
            content.Children.Add(new TextBlock { Text = L10n.T("hotkey." + key), TextWrapping = TextWrapping.Wrap });
        await new ContentDialog { XamlRoot = XamlRoot, Title = L10n.T("hotkeys.help"),
            Content = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto },
            CloseButtonText = L10n.T("action.ok") }.ShowAsync();
    }

    private async void Settings_Click(object sender, RoutedEventArgs e)
    {
        var language = new ComboBox {
            ItemsSource = new[] { L10n.T("lang.system"), L10n.T("lang.en"), L10n.T("lang.zh") },
            SelectedIndex = settings.UiLanguage == "en" ? 1 : settings.UiLanguage == "zh" ? 2 : 0
        };
        var provider = new ComboBox { ItemsSource = new[] { "OpenRouter", "AI Studio" }, SelectedIndex = settings.AlignmentProvider == "ai_studio" ? 1 : 0 };
        var keyBox = new PasswordBox { PlaceholderText = L10n.T("settings.pasteKey") };
        var modelBox = new TextBox { Header = L10n.T("settings.model") };
        var keyStatus = new TextBlock { FontFamily = new FontFamily("Consolas"), FontSize = 11 };
        var path = new TextBlock { Text = LocalSettingsStore.ConfigPath, FontFamily = new FontFamily("Consolas"), FontSize = 11, Opacity = .65, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        var orKey = settings.OpenRouterApiKey;
        var orModel = settings.OpenRouterModel;
        var aiKey = settings.AiStudioApiKey;
        var aiModel = settings.AiStudioModel;
        var lastProvider = provider.SelectedIndex;
        void BindProviderFields()
        {
            var studio = provider.SelectedIndex == 1;
            keyBox.Password = studio ? aiKey : orKey;
            modelBox.Text = studio ? aiModel : orModel;
            keyStatus.Text = keyBox.Password.Length == 0 ? L10n.T("settings.keyMissing") : L10n.T("settings.keyStored");
        }
        void FlushProviderFields()
        {
            if (lastProvider == 1) { aiKey = keyBox.Password; aiModel = modelBox.Text.Trim(); }
            else { orKey = keyBox.Password; orModel = modelBox.Text.Trim(); }
        }
        provider.SelectionChanged += (_, _) =>
        {
            FlushProviderFields();
            lastProvider = provider.SelectedIndex;
            BindProviderFields();
        };
        BindProviderFields();
        var clear = new Button { Content = L10n.T("settings.clearKey") };
        clear.Click += (_, _) => { keyBox.Password = ""; keyStatus.Text = L10n.T("settings.keyMissing"); };
        var content = new StackPanel { Spacing = 10, MaxWidth = 420 };
        content.Children.Add(new TextBlock { Text = L10n.T("settings.language"), FontFamily = new FontFamily("Consolas") });
        content.Children.Add(language);
        content.Children.Add(new TextBlock { Text = L10n.T("settings.provider"), FontFamily = new FontFamily("Consolas") });
        content.Children.Add(provider);
        content.Children.Add(new TextBlock { Text = L10n.T("settings.apiKey"), FontFamily = new FontFamily("Consolas") });
        content.Children.Add(keyBox);
        content.Children.Add(modelBox);
        content.Children.Add(keyStatus);
        content.Children.Add(clear);
        content.Children.Add(new TextBlock { Text = L10n.T("settings.keysNote"), TextWrapping = TextWrapping.Wrap, Opacity = .75 });
        content.Children.Add(path);
        var dialog = new ContentDialog { XamlRoot = XamlRoot, Title = L10n.T("settings.title"),
            Content = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto },
            PrimaryButtonText = L10n.T("settings.saveLocally"), CloseButtonText = L10n.T("action.cancel") };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        FlushProviderFields();
        settings.UiLanguage = language.SelectedIndex == 1 ? "en" : language.SelectedIndex == 2 ? "zh" : "system";
        settings.AlignmentProvider = provider.SelectedIndex == 1 ? "ai_studio" : "openrouter";
        settings.OpenRouterApiKey = orKey;
        settings.OpenRouterModel = orModel;
        settings.AiStudioApiKey = aiKey;
        settings.AiStudioModel = aiModel;
        try { LocalSettingsStore.Save(settings); L10n.Apply(settings.UiLanguage); BindChrome(); ActivityText.Text = L10n.T("activity.settingsSaved"); }
        catch (Exception error) { await ShowErrorAsync(error.Message); }
        Refresh();
    }
}
