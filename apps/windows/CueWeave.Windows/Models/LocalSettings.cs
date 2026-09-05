namespace CueWeave.WinUI.Models;

public static class ModelDefaults
{
    public const string OpenRouter = "google/gemini-3.8-flash";
    public const string AiStudio = "gemini-3.8-flash";
    internal const string LegacyOpenRouter = "google/gemini-3.7-flash";
    internal const string LegacyAiStudio = "gemini-3.7-flash";
}

public sealed class LocalSettings
{
    public string AlignmentProvider { get; set; } = "openrouter";
    public string OpenRouterApiKey { get; set; } = "";
    public string AiStudioApiKey { get; set; } = "";
    public string OpenRouterModel { get; set; } = ModelDefaults.OpenRouter;
    public string AiStudioModel { get; set; } = ModelDefaults.AiStudio;
    public string UiLanguage { get; set; } = "system";

    public void MigrateLegacyModelDefaults()
    {
        if (OpenRouterModel == ModelDefaults.LegacyOpenRouter)
            OpenRouterModel = ModelDefaults.OpenRouter;
        if (AiStudioModel == ModelDefaults.LegacyAiStudio)
            AiStudioModel = ModelDefaults.AiStudio;
    }
}
