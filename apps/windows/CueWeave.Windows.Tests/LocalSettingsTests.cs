using CueWeave.WinUI.Models;
using CueWeave.WinUI.Services;

namespace CueWeave.Windows.Tests;

[TestClass]
public sealed class LocalSettingsTests
{
    [TestMethod]
    public void SettingsRoundTripUsesPlainLocalJson()
    {
        var path = Path.Combine(Path.GetTempPath(), "cueweave-settings-test", Guid.NewGuid().ToString("N"), "settings.json");
        try
        {
            LocalSettingsStore.Save(new LocalSettings {
                AlignmentProvider = "ai_studio",
                OpenRouterApiKey = "openrouter-secret",
                AiStudioApiKey = "aistudio-secret",
                UiLanguage = "zh",
            }, path);
            var loaded = LocalSettingsStore.Load(path);
            Assert.AreEqual("ai_studio", loaded.AlignmentProvider);
            Assert.AreEqual("openrouter-secret", loaded.OpenRouterApiKey);
            Assert.AreEqual("aistudio-secret", loaded.AiStudioApiKey);
            Assert.AreEqual("zh", loaded.UiLanguage);
            StringAssert.Contains(LocalSettingsStore.ConfigPath, "CueWeave");
            StringAssert.Contains(LocalSettingsStore.ConfigPath, "settings.json");
        }
        finally
        {
            var root = Directory.GetParent(Path.GetDirectoryName(path)!)?.FullName;
            if (root is not null && Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
}
