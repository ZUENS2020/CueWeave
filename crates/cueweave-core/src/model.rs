use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const CURRENT_SCHEMA_VERSION: u32 = 3;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SongProject {
    pub schema_version: u32,
    #[serde(default)]
    pub source: Option<SourceInfo>,
    #[serde(default)]
    pub target: Option<TargetAudio>,
    #[serde(default)]
    pub metadata: MetadataSet,
    #[serde(default)]
    pub lyrics: LyricsDocument,
    #[serde(default)]
    pub timeline: Vec<Cue>,
    #[serde(default)]
    pub export: ExportProfile,
}

impl Default for SongProject {
    fn default() -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            source: None,
            target: None,
            metadata: MetadataSet::default(),
            lyrics: LyricsDocument::default(),
            timeline: Vec::new(),
            export: ExportProfile::default(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SourceInfo {
    #[serde(with = "portable_path")]
    pub path: PathBuf,
    #[serde(default)]
    pub fingerprint: Option<MediaFingerprint>,
    #[serde(default)]
    pub music_id: Option<u64>,
    #[serde(default)]
    pub cover_url: Option<String>,
    #[serde(default)]
    pub format: Option<String>,
    #[serde(default)]
    pub duration_ms: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct TargetAudio {
    #[serde(with = "portable_path")]
    pub path: PathBuf,
    #[serde(default)]
    pub fingerprint: Option<MediaFingerprint>,
    #[serde(default)]
    pub duration_ms: Option<u64>,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct MetadataSet {
    #[serde(default)]
    pub source: MetadataValues,
    #[serde(default)]
    pub target: MetadataValues,
    #[serde(default)]
    pub draft: MetadataValues,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct MetadataValues {
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub artists: Vec<String>,
    #[serde(default)]
    pub album_artist: Option<String>,
    #[serde(default)]
    pub album: Option<String>,
    #[serde(default)]
    pub track: Option<u32>,
    #[serde(default)]
    pub disc: Option<u32>,
    #[serde(default)]
    pub date: Option<String>,
    #[serde(default)]
    pub composer: Option<String>,
    #[serde(default)]
    pub lyricist: Option<String>,
    #[serde(default, with = "portable_path_option")]
    pub cover_path: Option<PathBuf>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct MediaFingerprint {
    pub file_name: String,
    pub size_bytes: u64,
    pub sha256: String,
}

mod portable_path {
    use serde::{Deserialize, Deserializer, Serializer};
    use std::path::{Path, PathBuf};

    pub fn serialize<S: Serializer>(path: &Path, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&path.to_string_lossy().replace('\\', "/"))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<PathBuf, D::Error> {
        String::deserialize(deserializer).map(PathBuf::from)
    }
}

mod portable_path_option {
    use serde::{Deserialize, Deserializer, Serialize, Serializer};
    use std::path::PathBuf;

    pub fn serialize<S: Serializer>(
        path: &Option<PathBuf>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        path.as_ref()
            .map(|path| path.to_string_lossy().replace('\\', "/"))
            .serialize(serializer)
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<Option<PathBuf>, D::Error> {
        Option::<String>::deserialize(deserializer).map(|path| path.map(PathBuf::from))
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct LyricsDocument {
    #[serde(default)]
    pub credits: Vec<Credit>,
    #[serde(default)]
    pub lines: Vec<LyricLine>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Credit {
    #[serde(default)]
    pub id: CreditId,
    pub label: String,
    pub value: String,
}

impl Credit {
    pub fn display_text(&self) -> String {
        let label = self.label.trim();
        let value = self.value.trim();
        if label.is_empty() {
            value.to_owned()
        } else {
            format!("{label}：{value}")
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LyricLine {
    pub id: LineId,
    pub original: String,
    #[serde(default)]
    pub translation: Option<String>,
    #[serde(default)]
    pub segments: Vec<LyricSegment>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LyricSegment {
    pub id: SegmentId,
    pub text: String,
    #[serde(default)]
    pub timing: SegmentTiming,
}

#[derive(Clone, Copy, Debug, Default, Eq, Hash, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct CreditId(pub u64);

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct LineId(pub u64);

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct SegmentId(pub u64);

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct AlignmentPoint {
    pub time_ms: u64,
    #[serde(default)]
    pub confidence: Option<f32>,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct SegmentTiming {
    #[serde(default)]
    pub gemini: Option<AlignmentPoint>,
    #[serde(default, rename = "final")]
    pub final_point: Option<AlignmentPoint>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Cue {
    Credit { credit_id: CreditId, time_ms: u64 },
    Lyric { line_id: LineId },
    Spacer { time_ms: u64 },
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ExportProfile {
    #[serde(default)]
    pub offset_ms: i64,
    #[serde(default = "default_export_formats")]
    pub formats: Vec<ExportFormat>,
    #[serde(default)]
    pub bilingual: BilingualMode,
}

impl Default for ExportProfile {
    fn default() -> Self {
        Self {
            offset_ms: 0,
            formats: default_export_formats(),
            bilingual: BilingualMode::OriginalOnly,
        }
    }
}

fn default_export_formats() -> Vec<ExportFormat> {
    vec![ExportFormat::Lrc]
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExportFormat {
    Lrc,
    Uslt,
    Sylt,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BilingualMode {
    #[default]
    OriginalOnly,
    #[serde(alias = "combined")]
    Bilingual,
}
