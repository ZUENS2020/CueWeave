using System.Text.Json;
using System.Text.Json.Nodes;
using CommunityToolkit.Mvvm.ComponentModel;
using CueWeave.WinUI.Models;

namespace CueWeave.WinUI.Services;

public sealed partial class ProjectSession(CoreProcess core) : ObservableObject
{
    private const int UndoLimit = 100;
    private const int AutosaveMs = 400;
    private readonly List<byte[]> undo = [];
    private readonly List<byte[]> redo = [];
    private readonly SemaphoreSlim saveGate = new(1, 1);
    private int autosaveGeneration;

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
        Interlocked.Increment(ref autosaveGeneration);
        var result = await core.CallAsync("load_project", new JsonObject { ["project_path"] = path }, token);
        var loaded = JsonSerializer.Deserialize(result.GetRawText(), CueJsonContext.Default.ProjectDocument)
            ?? throw new CoreException("invalid_response", L10n.T("error.coreEmpty"));
        if (keepUndo && Project is not null) { Push(undo, Snapshot(Project)); redo.Clear(); }
        else { undo.Clear(); redo.Clear(); }
        Project = loaded;
        ProjectPath = path;
        IsDirty = false;
        NotifyState();
    }

    public async Task SaveAsync(CancellationToken token = default)
    {
        Interlocked.Increment(ref autosaveGeneration);
        await saveGate.WaitAsync(token);
        try { await SaveCoreAsync(token); }
        finally { saveGate.Release(); }
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

    public void SetLineOriginal(ulong lineId, string text) => Mutate(document => {
        var line = document.Lyrics.Lines.FirstOrDefault(value => value.Id == lineId);
        if (line is null) return;
        line.Original = text;
        if (line.Segments.Count == 1) line.Segments[0].Text = text;
    });

    public void ClearTranslations() => Mutate(document => {
        foreach (var line in document.Lyrics.Lines) line.Translation = null;
    });

    public void AdoptMetadata(string field, bool fromSource) => Mutate(document => {
        var origin = fromSource ? document.Metadata.Source : document.Metadata.Target;
        var draft = document.Metadata.Draft;
        switch (field)
        {
            case "title": draft.Title = origin.Title; break;
            case "artists": draft.Artists = [.. origin.Artists]; break;
            case "albumArtist": draft.AlbumArtist = origin.AlbumArtist; break;
            case "album": draft.Album = origin.Album; break;
            case "date": draft.Date = origin.Date; break;
            case "track": draft.Track = origin.Track; break;
            case "disc": draft.Disc = origin.Disc; break;
            case "composer": draft.Composer = origin.Composer; break;
            case "lyricist": draft.Lyricist = origin.Lyricist; break;
        }
    });

    public void SetCoverPath(string path) => Mutate(document => document.Metadata.Draft.CoverPath = path);

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
        ScheduleAutosave();
    }

    public void Undo()
    {
        if (Project is null || undo.Count == 0) return;
        Push(redo, Snapshot(Project));
        Project = Restore(Pop(undo));
        IsDirty = true;
        NotifyState();
        ScheduleAutosave();
    }

    public void Redo()
    {
        if (Project is null || redo.Count == 0) return;
        Push(undo, Snapshot(Project));
        Project = Restore(Pop(redo));
        IsDirty = true;
        NotifyState();
        ScheduleAutosave();
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

    public void ClearFinal(ulong id) => ClearFinals([id]);

    public void ClearFinals(IEnumerable<ulong> ids)
    {
        var set = ids as ISet<ulong> ?? ids.ToHashSet();
        if (set.Count == 0) return;
        Mutate(document => {
            foreach (var segment in document.Segments)
                if (set.Contains(segment.Id)) segment.Timing.Final = null;
        });
    }

    public void SetCreditTime(ulong id, ulong milliseconds) => Mutate(document => ApplyCreditTime(document, id, milliseconds));

    public void BeginCreditDrag()
    {
        if (Project is null) return;
        Push(undo, Snapshot(Project));
        redo.Clear();
    }

    public void SetCreditTimeLive(ulong id, ulong milliseconds)
    {
        if (Project is null) return;
        ApplyCreditTime(Project, id, milliseconds);
        IsDirty = true;
    }

    public void EndCreditDrag()
    {
        ScheduleAutosave();
        OnPropertyChanged(nameof(Project));
        NotifyState();
    }

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
        ApplyCreditTime(document, id, 0);
    });

    private static void ApplyCreditTime(ProjectDocument document, ulong id, ulong milliseconds)
    {
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
    }

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

    private void ScheduleAutosave()
    {
        var generation = Interlocked.Increment(ref autosaveGeneration);
        _ = DebouncedSaveAsync(generation);
    }

    private async Task DebouncedSaveAsync(int generation)
    {
        try
        {
            await Task.Delay(AutosaveMs);
            if (generation != Volatile.Read(ref autosaveGeneration) || !IsDirty) return;
            await saveGate.WaitAsync();
            try
            {
                if (generation != Volatile.Read(ref autosaveGeneration) || !IsDirty) return;
                await SaveCoreAsync(CancellationToken.None);
                NotifyState();
                OnPropertyChanged(nameof(IsDirty));
            }
            finally { saveGate.Release(); }
        }
        catch { }
    }

    private async Task SaveCoreAsync(CancellationToken token)
    {
        if (Project is null || ProjectPath is null) return;
        var savedProject = Project;
        var savedPath = ProjectPath;
        var savedSnapshot = Snapshot(savedProject);
        await core.CallAsync("save_project", new JsonObject {
            ["project_path"] = savedPath,
            ["project"] = JsonNode.Parse(savedSnapshot)
        }, token);
        // Do not mark edits made while the RPC was in flight as already saved.
        if (ReferenceEquals(Project, savedProject) && ProjectPath == savedPath
            && savedSnapshot.AsSpan().SequenceEqual(Snapshot(savedProject))) IsDirty = false;
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
