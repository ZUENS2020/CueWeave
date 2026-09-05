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
            Assert.AreEqual(ModelDefaults.OpenRouter, loaded.OpenRouterModel);
            Assert.AreEqual(ModelDefaults.AiStudio, loaded.AiStudioModel);
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

    [TestMethod]
    public void LegacyDefaultsMigrateWithoutReplacingCustomModels()
    {
        var directory = Path.Combine(Path.GetTempPath(), "cueweave-settings-test", Guid.NewGuid().ToString("N"));
        var legacyPath = Path.Combine(directory, "legacy.json");
        var customPath = Path.Combine(directory, "custom.json");
        try
        {
            LocalSettingsStore.Save(new LocalSettings {
                OpenRouterModel = "google/gemini-3.7-flash",
                AiStudioModel = "gemini-3.7-flash",
            }, legacyPath);
            LocalSettingsStore.Save(new LocalSettings {
                OpenRouterModel = "custom/openrouter-model",
                AiStudioModel = "custom-aistudio-model",
            }, customPath);

            var migrated = LocalSettingsStore.Load(legacyPath);
            Assert.AreEqual(ModelDefaults.OpenRouter, migrated.OpenRouterModel);
            Assert.AreEqual(ModelDefaults.AiStudio, migrated.AiStudioModel);
            var custom = LocalSettingsStore.Load(customPath);
            Assert.AreEqual("custom/openrouter-model", custom.OpenRouterModel);
            Assert.AreEqual("custom-aistudio-model", custom.AiStudioModel);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, true);
        }
    }
}
