using System.Text.Json;
using System.Text.Json.Serialization;

namespace CueWeave.WinUI.Models;

public sealed class ProjectDocument
{
    public uint SchemaVersion { get; set; }
    public SourceInfo? Source { get; set; }
    public TargetAudio? Target { get; set; }
    public MetadataSet Metadata { get; set; } = new();
    public LyricsDocument Lyrics { get; set; } = new();
    public List<JsonElement> Timeline { get; set; } = [];
    [JsonPropertyName("export")] public ExportProfile ExportProfile { get; set; } = new();

    [JsonIgnore] public List<LyricSegment> Segments => Lyrics.Lines.SelectMany(line => line.Segments).ToList();
}

public sealed class SourceInfo
{
    public string Path { get; set; } = "";
    public MediaFingerprint? Fingerprint { get; set; }
    public ulong? MusicId { get; set; }
    public string? CoverUrl { get; set; }
    public string? Format { get; set; }
    public ulong? DurationMs { get; set; }
}

public sealed class TargetAudio
{
    public string Path { get; set; } = "";
    public MediaFingerprint? Fingerprint { get; set; }
    public ulong? DurationMs { get; set; }
}

public sealed class MediaFingerprint
{
    public string FileName { get; set; } = "";
    public ulong SizeBytes { get; set; }
    public string Sha256 { get; set; } = "";
}

public sealed class MetadataSet
{
    public MetadataValues Source { get; set; } = new();
    public MetadataValues Target { get; set; } = new();
    public MetadataValues Draft { get; set; } = new();
}

public sealed class MetadataValues
{
    public string? Title { get; set; }
    public List<string> Artists { get; set; } = [];
    public string? AlbumArtist { get; set; }
    public string? Album { get; set; }
    public uint? Track { get; set; }
    public uint? Disc { get; set; }
    public string? Date { get; set; }
    public string? Composer { get; set; }
    public string? Lyricist { get; set; }
    public string? CoverPath { get; set; }
}

public sealed class LyricsDocument
{
    public List<Credit> Credits { get; set; } = [];
    public List<LyricLine> Lines { get; set; } = [];
}

public sealed class Credit
{
    public ulong Id { get; set; }
    public string Label { get; set; } = "";
    public string Value { get; set; } = "";

    [JsonIgnore]
    public string DisplayText
    {
        get
        {
            var label = Label.Trim();
            var value = Value.Trim();
            return string.IsNullOrEmpty(label) ? value : $"{label}：{value}";
        }
    }
}

public sealed class LyricLine
{
    public ulong Id { get; set; }
    public string Original { get; set; } = "";
    public string? Translation { get; set; }
    public List<LyricSegment> Segments { get; set; } = [];
}

public sealed class LyricSegment
{
    public ulong Id { get; set; }
    public string Text { get; set; } = "";
    public SegmentTiming Timing { get; set; } = new();
}

public sealed class SegmentTiming
{
    public AlignmentPoint? Gemini { get; set; }
    [JsonPropertyName("final")] public AlignmentPoint? Final { get; set; }
}

public sealed class AlignmentPoint
{
    public ulong TimeMs { get; set; }
    public float? Confidence { get; set; }
}

public sealed class ExportProfile
{
    public long OffsetMs { get; set; }
    public List<string> Formats { get; set; } = ["lrc"];
    public string Bilingual { get; set; } = "original_only";
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower,
    WriteIndented = true, GenerationMode = JsonSourceGenerationMode.Metadata)]
[JsonSerializable(typeof(ProjectDocument))]
[JsonSerializable(typeof(LocalSettings))]
internal partial class CueJsonContext : JsonSerializerContext;
