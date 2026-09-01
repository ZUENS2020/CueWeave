using System.Text.Json;
using System.Text.Json.Nodes;
using CommunityToolkit.Mvvm.ComponentModel;
using CueWeave.WinUI.Models;

namespace CueWeave.WinUI.Services;

public sealed partial class ProjectSession(CoreProcess core) : ObservableObject
{
    private const int UndoLimit = 100;
    private readonly List<byte[]> undo = [];
    private readonly List<byte[]> redo = [];

    [ObservableProperty] public partial ProjectDocument? Project { get; set; }
    [ObservableProperty] public partial string? ProjectPath { get; set; }
    [ObservableProperty] public partial bool IsDirty { get; set; }

    public bool CanUndo => undo.Count > 0;
    public bool CanRedo => redo.Count > 0;
    public string Title => Project?.Metadata.Draft.Title ?? "CueWeave";

    public async Task CreateAsync(string path, string source, string target, CancellationToken token)
    {
        await core.CallAsync("create", new JsonObject {
            ["project_path"] = path, ["source_path"] = source, ["target_path"] = target
        }, token);
        await LoadAsync(path, token);
    }

    public async Task LoadAsync(string path, CancellationToken token = default, bool keepUndo = false)
    {
        var result = await core.CallAsync("load_project", new JsonObject { ["project_path"] = path }, token);
        var loaded = JsonSerializer.Deserialize(result.GetRawText(), CueJsonContext.Default.ProjectDocument)
            ?? throw new CoreException("invalid_response", L10n.T("error.coreEmpty"));
        if (keepUndo && Project is not null) Push(undo, Snapshot(Project));
        else { undo.Clear(); redo.Clear(); }
        Project = loaded;
        ProjectPath = path;
        IsDirty = false;
        NotifyState();
    }

    public async Task SaveAsync(CancellationToken token = default)
    {
        if (Project is null || ProjectPath is null) return;
        await core.CallAsync("save_project", new JsonObject {
            ["project_path"] = ProjectPath,
            ["project"] = JsonSerializer.SerializeToNode(Project, CueJsonContext.Default.ProjectDocument)
        }, token);
        IsDirty = false;
    }

    public async Task RunProjectCommandAsync(string command, JsonObject? extra, CancellationToken token)
    {
        if (ProjectPath is null) return;
        await SaveAsync(token);
        var payload = extra ?? new JsonObject();
        payload["project_path"] = ProjectPath;
        await core.CallAsync(command, payload, token);
        await LoadAsync(ProjectPath, token, keepUndo: true);
    }

    public async Task<JsonElement> ExportAsync(string outputPath, bool overwrite, CancellationToken token)
    {
        await SaveAsync(token);
        return await core.CallAsync("export", new JsonObject {
            ["project_path"] = ProjectPath,
            ["output_path"] = outputPath,
            ["overwrite"] = overwrite
        }, token);
    }

    public async Task ExportCueSheetAsync(string outputPath, CancellationToken token)
    {
        await SaveAsync(token);
        await core.CallAsync("export_cuesheet", new JsonObject { ["project_path"] = ProjectPath, ["output_path"] = outputPath }, token);
    }

    public void SetLineTranslation(ulong lineId, string? text) => Mutate(document => {
        var line = document.Lyrics.Lines.FirstOrDefault(value => value.Id == lineId);
        if (line is null) return;
        line.Translation = string.IsNullOrWhiteSpace(text) ? null : text.Trim();
    });

    public void ClearTranslations() => Mutate(document => {
        foreach (var line in document.Lyrics.Lines) line.Translation = null;
    });

    public void Mutate(Action<ProjectDocument> action)
    {
        if (Project is null) return;
        var before = Snapshot(Project);
        action(Project);
        var after = Snapshot(Project);
        if (before.AsSpan().SequenceEqual(after)) return;
        Push(undo, before);
        redo.Clear();
        IsDirty = true;
        OnPropertyChanged(nameof(Project));
        NotifyState();
    }

    public void Undo()
    {
        if (Project is null || undo.Count == 0) return;
        Push(redo, Snapshot(Project));
        Project = Restore(Pop(undo));
        IsDirty = true;
        NotifyState();
    }

    public void Redo()
    {
        if (Project is null || redo.Count == 0) return;
        Push(undo, Snapshot(Project));
        Project = Restore(Pop(redo));
        IsDirty = true;
        NotifyState();
    }

    public void SetFinal(ulong id, long milliseconds)
    {
        Mutate(document => {
            var segments = document.Segments;
            var index = segments.FindIndex(s => s.Id == id);
            if (index < 0) return;
            var lower = index == 0 ? 0UL : segments[index - 1].Timing.Final?.TimeMs ?? 0;
            var upper = index + 1 == segments.Count ? document.Target?.DurationMs ?? ulong.MaxValue
                : segments[index + 1].Timing.Final?.TimeMs ?? document.Target?.DurationMs ?? ulong.MaxValue;
            var clamped = (ulong)Math.Clamp(milliseconds, (long)Math.Min(lower, long.MaxValue), (long)Math.Min(upper, long.MaxValue));
            segments[index].Timing.Final = new AlignmentPoint { TimeMs = clamped };
        });
    }

    public void UseGemini(ulong id) => Mutate(document => {
        var segment = document.Segments.FirstOrDefault(s => s.Id == id);
        if (segment?.Timing.Gemini is null) return;
        segment.Timing.Final = new AlignmentPoint { TimeMs = segment.Timing.Gemini.TimeMs };
    });

    public void ClearFinal(ulong id) => Mutate(document => {
        var segment = document.Segments.FirstOrDefault(s => s.Id == id);
        if (segment is null) return;
        segment.Timing.Final = null;
    });

    public void SetCreditTime(ulong id, ulong milliseconds) => Mutate(document => {
        var duration = document.Target?.DurationMs ?? ulong.MaxValue;
        var time = Math.Min(milliseconds, duration);
        var next = new List<JsonElement>();
        var found = false;
        foreach (var cue in document.Timeline)
        {
            if (IsCreditCue(cue, id))
            {
                next.Add(WithTime(cue, time));
                found = true;
            }
            else next.Add(cue);
        }
        if (!found)
        {
            next.Insert(0, JsonSerializer.Deserialize<JsonElement>(
                $$"""{"type":"credit","credit_id":{{id}},"time_ms":{{time}}}""")!);
        }
        document.Timeline = next;
    });

    public void AddCredit() => Mutate(document => {
        var id = document.Lyrics.Credits.Select(credit => credit.Id).DefaultIfEmpty().Max() + 1;
        document.Lyrics.Credits.Add(new Credit { Id = id, Label = "Role", Value = "Name" });
        document.Timeline.Insert(0, JsonSerializer.Deserialize<JsonElement>(
            $$"""{"type":"credit","credit_id":{{id}},"time_ms":0}""")!);
    });

    public void RemoveCredit(ulong id) => Mutate(document => {
        document.Lyrics.Credits.RemoveAll(credit => credit.Id == id);
        document.Timeline = [.. document.Timeline.Where(cue => !IsCreditCue(cue, id))];
    });

    public void MergeCredits() => Mutate(document => {
        if (document.Lyrics.Credits.Count < 2) return;
        var merged = string.Join(" / ", document.Lyrics.Credits.Select(credit => credit.DisplayText).Where(text => text.Length > 0));
        var id = document.Lyrics.Credits[0].Id;
        document.Lyrics.Credits = [new Credit { Id = id, Label = "", Value = merged }];
        document.Timeline = [.. document.Timeline.Where(cue => cue.ValueKind != JsonValueKind.Object
            || !cue.TryGetProperty("type", out var type)
            || type.GetString() != "credit"
            || (cue.TryGetProperty("credit_id", out var creditId) && creditId.GetUInt64() == id))];
        SetCreditTimeRaw(document, id, 0);
    });

    private static bool IsCreditCue(JsonElement cue, ulong id) =>
        cue.ValueKind == JsonValueKind.Object
        && cue.TryGetProperty("type", out var type)
        && type.GetString() == "credit"
        && cue.TryGetProperty("credit_id", out var creditId)
        && creditId.GetUInt64() == id;

    private static JsonElement WithTime(JsonElement cue, ulong time)
    {
        var node = JsonNode.Parse(cue.GetRawText())!.AsObject();
        node["time_ms"] = time;
        return JsonSerializer.Deserialize<JsonElement>(node.ToJsonString())!;
    }

    private static void SetCreditTimeRaw(ProjectDocument document, ulong id, ulong time)
    {
        document.Timeline = [.. document.Timeline.Select(cue => IsCreditCue(cue, id) ? WithTime(cue, time) : cue)];
    }

    private static byte[] Snapshot(ProjectDocument value) =>
        JsonSerializer.SerializeToUtf8Bytes(value, CueJsonContext.Default.ProjectDocument);
    private static ProjectDocument Restore(byte[] value) =>
        JsonSerializer.Deserialize(value, CueJsonContext.Default.ProjectDocument)!;
    private static byte[] Pop(List<byte[]> stack) { var value = stack[^1]; stack.RemoveAt(stack.Count - 1); return value; }
    private static void Push(List<byte[]> stack, byte[] value) { stack.Add(value); if (stack.Count > UndoLimit) stack.RemoveAt(0); }
    private void NotifyState()
    {
        OnPropertyChanged(nameof(CanUndo));
        OnPropertyChanged(nameof(CanRedo));
        OnPropertyChanged(nameof(Title));
    }
}
