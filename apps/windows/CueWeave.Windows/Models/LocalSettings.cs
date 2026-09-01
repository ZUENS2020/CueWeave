namespace CueWeave.WinUI.Models;

public sealed class LocalSettings
{
    public string AlignmentProvider { get; set; } = "openrouter";
    public string OpenRouterApiKey { get; set; } = "";
    public string AiStudioApiKey { get; set; } = "";
    public string OpenRouterModel { get; set; } = "google/gemini-3.7-flash";
    public string AiStudioModel { get; set; } = "gemini-3.7-flash";
}
