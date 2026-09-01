use crate::{BilingualMode, Cue, ExportError, ExportFormat, SongProject};
use id3::frame::{Lyrics, SynchronisedLyrics, SynchronisedLyricsType, TimestampFormat};
use id3::{Tag, TagLike};
use serde::{Deserialize, Serialize};

pub const CUESHEET_SCHEMA_VERSION: u32 = 1;

/// Player-agnostic lyric snapshot. Built-in exporters and future player plugins
/// should consume this document instead of reading SongProject internals.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ExportCueSheet {
    pub schema_version: u32,
    pub offset_ms: i64,
    pub bilingual: BilingualMode,
    pub metadata: ExportCueMetadata,
    pub lines: Vec<ExportCueLine>,
    pub events: Vec<ExportCueEvent>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ExportCueMetadata {
    pub title: Option<String>,
    pub artists: Vec<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub date: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ExportCueLine {
    pub id: u64,
    pub original: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub translation: Option<String>,
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_ms: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ExportCueEvent {
    Credit {
        time_ms: u64,
        text: String,
    },
    Spacer {
        time_ms: u64,
    },
    Lyric {
        line_id: u64,
        time_ms: u64,
        text: String,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ExportAdapterKind {
    Sidecar,
    EmbeddedTag,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ExportAdapterInfo {
    pub id: String,
    pub title: String,
    pub detail: String,
    pub kind: ExportAdapterKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sidecar_extension: Option<String>,
}

/// In-process player adapter. Future plugins should either implement this trait
/// or consume `ExportCueSheet` JSON (`schema_version` 1) from stdin / a file.
pub trait PlayerExportAdapter: Send + Sync {
    fn info(&self) -> ExportAdapterInfo;
    fn write_sidecar(&self, _sheet: &ExportCueSheet) -> Result<Vec<u8>, ExportError> {
        Err(ExportError::Invalid(format!(
            "{} is not a sidecar adapter",
            self.info().id
        )))
    }
    fn embed(&self, _tag: &mut Tag, _sheet: &ExportCueSheet) -> Result<(), ExportError> {
        Err(ExportError::Invalid(format!(
            "{} is not an embedded-tag adapter",
            self.info().id
        )))
    }
}

pub struct LrcAdapter;
pub struct UsltAdapter;
pub struct SyltAdapter;

impl PlayerExportAdapter for LrcAdapter {
    fn info(&self) -> ExportAdapterInfo {
        ExportAdapterInfo {
            id: "lrc".into(),
            title: "LRC".into(),
            detail: "Sidecar synced lyrics".into(),
            kind: ExportAdapterKind::Sidecar,
            sidecar_extension: Some("lrc".into()),
        }
    }

    fn write_sidecar(&self, sheet: &ExportCueSheet) -> Result<Vec<u8>, ExportError> {
        let mut output = String::new();
        for event in &sheet.events {
            match event {
                ExportCueEvent::Credit { time_ms, text } => {
                    push_lrc_line(&mut output, *time_ms, text);
                }
                ExportCueEvent::Spacer { time_ms } => push_lrc_line(&mut output, *time_ms, ""),
                ExportCueEvent::Lyric { time_ms, text, .. } => {
                    push_lrc_line(&mut output, *time_ms, text);
                }
            }
        }
        Ok(output.into_bytes())
    }
}

impl PlayerExportAdapter for UsltAdapter {
    fn info(&self) -> ExportAdapterInfo {
        ExportAdapterInfo {
            id: "uslt".into(),
            title: "USLT".into(),
            detail: "Embedded static lyrics".into(),
            kind: ExportAdapterKind::EmbeddedTag,
            sidecar_extension: None,
        }
    }

    fn embed(&self, tag: &mut Tag, sheet: &ExportCueSheet) -> Result<(), ExportError> {
        let text = sheet
            .lines
            .iter()
            .map(|line| line.text.as_str())
            .collect::<Vec<_>>()
            .join("\n");
        tag.add_frame(Lyrics {
            lang: "und".into(),
            description: "CueWeave".into(),
            text,
        });
        Ok(())
    }
}

impl PlayerExportAdapter for SyltAdapter {
    fn info(&self) -> ExportAdapterInfo {
        ExportAdapterInfo {
            id: "sylt".into(),
            title: "SYLT".into(),
            detail: "Embedded synced lyrics".into(),
            kind: ExportAdapterKind::EmbeddedTag,
            sidecar_extension: None,
        }
    }

    fn embed(&self, tag: &mut Tag, sheet: &ExportCueSheet) -> Result<(), ExportError> {
        let mut content = Vec::new();
        for line in &sheet.lines {
            let Some(time_ms) = line.start_ms else {
                continue;
            };
            content.push((
                u32::try_from(time_ms)
                    .map_err(|_| ExportError::Invalid("SYLT timestamp exceeds u32".into()))?,
                line.text.clone(),
            ));
        }
        tag.add_frame(SynchronisedLyrics {
            lang: "und".into(),
            timestamp_format: TimestampFormat::Ms,
            content_type: SynchronisedLyricsType::Lyrics,
            content,
            description: "CueWeave".into(),
        });
        Ok(())
    }
}

impl ExportFormat {
    pub fn adapter_id(self) -> &'static str {
        match self {
            Self::Lrc => "lrc",
            Self::Uslt => "uslt",
            Self::Sylt => "sylt",
        }
    }
}

pub fn builtin_player_adapters() -> Vec<Box<dyn PlayerExportAdapter>> {
    vec![
        Box::new(LrcAdapter),
        Box::new(UsltAdapter),
        Box::new(SyltAdapter),
    ]
}

pub fn builtin_player_adapter(id: &str) -> Option<Box<dyn PlayerExportAdapter>> {
    match id {
        "lrc" => Some(Box::new(LrcAdapter)),
        "uslt" => Some(Box::new(UsltAdapter)),
        "sylt" => Some(Box::new(SyltAdapter)),
        _ => None,
    }
}

pub fn list_export_adapters() -> Vec<ExportAdapterInfo> {
    builtin_player_adapters()
        .into_iter()
        .map(|adapter| adapter.info())
        .collect()
}

pub fn build_export_cue_sheet(project: &SongProject) -> Result<ExportCueSheet, ExportError> {
    project
        .validate()
        .map_err(|error| ExportError::Invalid(error.to_string()))?;
    let offset_ms = project.export.offset_ms;
    let bilingual = project.export.bilingual;
    let lines = project
        .lyrics
        .lines
        .iter()
        .map(|line| {
            let start_ms = line
                .segments
                .iter()
                .find_map(|segment| segment.timing.final_point.map(|point| point.time_ms))
                .map(|time_ms| offset_time(time_ms, offset_ms));
            ExportCueLine {
                id: line.id.0,
                original: line.original.clone(),
                translation: line.translation.clone(),
                text: resolved_line_text(&line.original, line.translation.as_deref(), bilingual),
                start_ms,
            }
        })
        .collect::<Vec<_>>();
    let mut events = Vec::new();
    for cue in &project.timeline {
        match cue {
            Cue::Credit { time_ms, text } => events.push(ExportCueEvent::Credit {
                time_ms: offset_time(*time_ms, offset_ms),
                text: text.clone(),
            }),
            Cue::Spacer { time_ms } => events.push(ExportCueEvent::Spacer {
                time_ms: offset_time(*time_ms, offset_ms),
            }),
            Cue::Lyric { line_id } => {
                let Some(line) = lines.iter().find(|line| line.id == line_id.0) else {
                    return Err(ExportError::Invalid(format!("missing line {}", line_id.0)));
                };
                let Some(time_ms) = line.start_ms else {
                    continue;
                };
                events.push(ExportCueEvent::Lyric {
                    line_id: line.id,
                    time_ms,
                    text: line.text.clone(),
                });
            }
        }
    }
    Ok(ExportCueSheet {
        schema_version: CUESHEET_SCHEMA_VERSION,
        offset_ms,
        bilingual,
        metadata: ExportCueMetadata {
            title: project.metadata.draft.title.clone(),
            artists: project.metadata.draft.artists.clone(),
            album: project.metadata.draft.album.clone(),
            album_artist: project.metadata.draft.album_artist.clone(),
            date: project.metadata.draft.date.clone(),
        },
        lines,
        events,
    })
}

pub fn render_cuesheet_json(project: &SongProject) -> Result<String, ExportError> {
    let sheet = build_export_cue_sheet(project)?;
    serde_json::to_string_pretty(&sheet)
        .map_err(|error| ExportError::Invalid(format!("cue sheet JSON failed: {error}")))
}

pub(crate) fn resolved_line_text(
    original: &str,
    translation: Option<&str>,
    mode: BilingualMode,
) -> String {
    match (mode, translation.filter(|text| !text.trim().is_empty())) {
        (BilingualMode::Combined, Some(translation)) => format!("{original} / {translation}"),
        _ => original.to_owned(),
    }
}

pub(crate) fn offset_time(time_ms: u64, offset_ms: i64) -> u64 {
    if offset_ms >= 0 {
        time_ms.saturating_add(offset_ms as u64)
    } else {
        time_ms.saturating_sub(offset_ms.unsigned_abs())
    }
}

fn push_lrc_line(output: &mut String, time_ms: u64, text: &str) {
    let minutes = time_ms / 60_000;
    let seconds = time_ms % 60_000 / 1_000;
    let millis = time_ms % 1_000;
    output.push_str(&format!("[{minutes:02}:{seconds:02}.{millis:03}]{text}\n"));
}
