use crate::{AlignmentPoint, SegmentId, SongProject};
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashSet;
use std::fs;
use std::time::Duration;
use thiserror::Error;

const INLINE_AUDIO_LIMIT: u64 = 14 * 1024 * 1024;
const INLINE_REQUEST_LIMIT: usize = 19 * 1024 * 1024;

#[derive(Clone, Debug)]
pub struct OpenRouterConfig {
    pub api_key: String,
    pub model: String,
    pub endpoint: String,
}

#[derive(Clone, Debug)]
pub struct AiStudioConfig {
    pub api_key: String,
    pub model: String,
    pub endpoint: String,
}

impl OpenRouterConfig {
    pub fn new(api_key: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            model: "google/gemini-3.7-flash".into(),
            endpoint: "https://openrouter.ai/api/v1/chat/completions".into(),
        }
    }
}

impl AiStudioConfig {
    pub fn new(api_key: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            model: "gemini-3.7-flash".into(),
            endpoint: "https://generativelanguage.googleapis.com/v1beta".into(),
        }
    }
}

#[derive(Debug, Error)]
pub enum AlignmentError {
    #[error("invalid alignment: {0}")]
    Invalid(String),
    #[error("alignment I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("alignment provider request failed: {0}")]
    Http(#[from] reqwest::Error),
    #[error("{name} HTTP {status}: {message}")]
    Provider {
        name: &'static str,
        status: u16,
        message: String,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MatchStatus {
    Matched,
    Unmatched,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AlignmentItem {
    pub id: SegmentId,
    pub status: MatchStatus,
    #[serde(default)]
    pub start_ms: Option<u64>,
    #[serde(default)]
    pub confidence: Option<f32>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AlignmentResponse {
    pub segments: Vec<AlignmentItem>,
}

#[derive(Deserialize)]
struct ProviderAlignmentResponse {
    segments: Vec<ProviderAlignmentItem>,
}

#[derive(Deserialize)]
struct ProviderAlignmentItem {
    id: SegmentId,
    status: MatchStatus,
    start_seconds: Option<f64>,
    confidence: Option<f32>,
}

pub fn align_with_openrouter(
    project: &SongProject,
    config: &OpenRouterConfig,
) -> Result<AlignmentResponse, AlignmentError> {
    if config.api_key.trim().is_empty() {
        return invalid("API key is empty");
    }
    if config.model.trim().is_empty() || config.model.len() > 200 {
        return invalid("OpenRouter model name is invalid");
    }
    let audio = encode_target_audio(project)?;
    let request = build_openrouter_request(project, audio, &config.model)?;
    ensure_request_size(&request, "OpenRouter")?;
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(180))
        .build()?;
    let response = client
        .post(&config.endpoint)
        .bearer_auth(&config.api_key)
        .header("HTTP-Referer", "https://github.com/ZUENS2020/CueWeave")
        .header("X-OpenRouter-Title", "CueWeave")
        .json(&request)
        .send()?;
    let status = response.status();
    let body = response.text()?;
    if !status.is_success() {
        return Err(AlignmentError::Provider {
            name: "OpenRouter",
            status: status.as_u16(),
            message: body,
        });
    }
    parse_openrouter_envelope(&body, project)
}

pub fn align_with_ai_studio(
    project: &SongProject,
    config: &AiStudioConfig,
) -> Result<AlignmentResponse, AlignmentError> {
    if config.api_key.trim().is_empty() {
        return invalid("API key is empty");
    }
    if config.model.is_empty()
        || !config.model.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.')
        })
    {
        return invalid("AI Studio model name contains unsupported characters");
    }
    let request = build_ai_studio_request(project, encode_target_audio(project)?)?;
    ensure_request_size(&request, "AI Studio")?;
    let url = format!(
        "{}/models/{}:generateContent",
        config.endpoint.trim_end_matches('/'),
        config.model
    );
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(180))
        .build()?;
    let response = client
        .post(url)
        .header("x-goog-api-key", &config.api_key)
        .json(&request)
        .send()?;
    let status = response.status();
    let body = response.text()?;
    if !status.is_success() {
        return Err(AlignmentError::Provider {
            name: "AI Studio",
            status: status.as_u16(),
            message: body,
        });
    }
    parse_ai_studio_envelope(&body, project)
}

pub fn build_openrouter_request(
    project: &SongProject,
    audio_base64: String,
    model: &str,
) -> Result<Value, AlignmentError> {
    let prompt = alignment_prompt(project)?;
    let request = json!({
        "model": model,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "input_audio", "input_audio": {"data": audio_base64, "format": "mp3"}}
            ]
        }],
        "response_format": {
            "type": "json_schema",
            "json_schema": {
                "name": "cueweave_alignment",
                "strict": true,
                "schema": alignment_schema()
            }
        },
        "provider": {"require_parameters": true},
        "temperature": 0,
        "stream": false
    });
    Ok(request)
}

pub fn build_ai_studio_request(
    project: &SongProject,
    audio_base64: String,
) -> Result<Value, AlignmentError> {
    let prompt = alignment_prompt(project)?;
    Ok(json!({
        "contents": [{
            "role": "user",
            "parts": [
                {"text": prompt},
                {"inlineData": {"mimeType": "audio/mpeg", "data": audio_base64}}
            ]
        }],
        "generationConfig": {
            "temperature": 0,
            "responseFormat": {
                "text": {
                    "mimeType": "APPLICATION_JSON",
                    "schema": alignment_schema()
                }
            }
        }
    }))
}

pub fn parse_openrouter_envelope(
    json: &str,
    project: &SongProject,
) -> Result<AlignmentResponse, AlignmentError> {
    let envelope: Value = serde_json::from_str(json).map_err(|error| {
        AlignmentError::Invalid(format!("OpenRouter envelope JSON failed: {error}"))
    })?;
    let text = envelope
        .pointer("/choices/0/message/content")
        .and_then(Value::as_str)
        .ok_or_else(|| AlignmentError::Invalid("OpenRouter returned no structured text".into()))?;
    parse_alignment_response(text, project)
}

pub fn parse_ai_studio_envelope(
    json: &str,
    project: &SongProject,
) -> Result<AlignmentResponse, AlignmentError> {
    let envelope: Value = serde_json::from_str(json).map_err(|error| {
        AlignmentError::Invalid(format!("AI Studio envelope JSON failed: {error}"))
    })?;
    let text = envelope
        .pointer("/candidates/0/content/parts/0/text")
        .and_then(Value::as_str)
        .ok_or_else(|| AlignmentError::Invalid("AI Studio returned no structured text".into()))?;
    parse_alignment_response(text, project)
}

pub fn parse_alignment_response(
    json: &str,
    project: &SongProject,
) -> Result<AlignmentResponse, AlignmentError> {
    let provider: ProviderAlignmentResponse = serde_json::from_str(json)
        .map_err(|error| AlignmentError::Invalid(format!("alignment JSON failed: {error}")))?;
    let mut segments = Vec::with_capacity(provider.segments.len());
    for item in provider.segments {
        let start_ms = match item.start_seconds {
            None => None,
            Some(seconds) if seconds.is_finite() && seconds >= 0.0 => {
                let milliseconds = seconds * 1_000.0;
                if milliseconds > u64::MAX as f64 {
                    return invalid(format!("segment {} timestamp is too large", item.id.0));
                }
                Some(milliseconds.round() as u64)
            }
            Some(_) => return invalid(format!("segment {} has invalid timestamp", item.id.0)),
        };
        segments.push(AlignmentItem {
            id: item.id,
            status: item.status,
            start_ms,
            confidence: item.confidence,
        });
    }
    let response = AlignmentResponse { segments };
    validate_alignment_response(&response, project)?;
    Ok(response)
}

pub fn validate_alignment_response(
    response: &AlignmentResponse,
    project: &SongProject,
) -> Result<(), AlignmentError> {
    let expected: Vec<_> = project
        .lyrics
        .lines
        .iter()
        .flat_map(|line| line.segments.iter().map(|segment| segment.id))
        .collect();
    let expected_set: HashSet<_> = expected.iter().copied().collect();
    let mut seen = HashSet::new();
    let mut previous = None;
    let duration = project
        .target
        .as_ref()
        .and_then(|target| target.duration_ms)
        .filter(|duration| *duration > 0)
        .ok_or_else(|| AlignmentError::Invalid("target duration is missing".into()))?;

    for (index, item) in response.segments.iter().enumerate() {
        if !expected_set.contains(&item.id) {
            return invalid(format!("unknown segment id {}", item.id.0));
        }
        if expected.get(index) != Some(&item.id) {
            return invalid(format!("segment {} is in the wrong ID order", item.id.0));
        }
        if !seen.insert(item.id) {
            return invalid(format!("duplicate segment id {}", item.id.0));
        }
        if item
            .confidence
            .is_some_and(|value| !value.is_finite() || !(0.0..=1.0).contains(&value))
        {
            return invalid(format!("segment {} has invalid confidence", item.id.0));
        }
        match (item.status, item.start_ms) {
            (MatchStatus::Unmatched, None) => {}
            (MatchStatus::Unmatched, Some(_)) => {
                return invalid(format!("unmatched segment {} has a time", item.id.0));
            }
            (_, None) => return invalid(format!("segment {} is missing start_ms", item.id.0)),
            (_, Some(time_ms)) => {
                if time_ms > duration {
                    return invalid(format!("segment {} exceeds target duration", item.id.0));
                }
                if previous.is_some_and(|last| time_ms < last) {
                    return invalid(format!("segment {} is out of order", item.id.0));
                }
                previous = Some(time_ms);
            }
        }
    }
    if seen.len() != expected.len() {
        let missing: Vec<_> = expected
            .into_iter()
            .filter(|id| !seen.contains(id))
            .map(|id| id.0)
            .collect();
        return invalid(format!("missing segment ids {missing:?}"));
    }
    Ok(())
}

pub fn apply_alignment_response(
    project: &mut SongProject,
    response: &AlignmentResponse,
) -> Result<(), AlignmentError> {
    apply_alignment_items(project, response, None)
}

pub fn apply_alignment_response_selected(
    project: &mut SongProject,
    response: &AlignmentResponse,
    selected: &[SegmentId],
) -> Result<(), AlignmentError> {
    if selected.is_empty() {
        return invalid("alignment selection is empty");
    }
    let selected: HashSet<_> = selected.iter().copied().collect();
    let known: HashSet<_> = project
        .lyrics
        .lines
        .iter()
        .flat_map(|line| line.segments.iter().map(|segment| segment.id))
        .collect();
    if let Some(id) = selected.iter().find(|id| !known.contains(id)) {
        return invalid(format!("unknown selected segment id {}", id.0));
    }
    apply_alignment_items(project, response, Some(&selected))
}

fn apply_alignment_items(
    project: &mut SongProject,
    response: &AlignmentResponse,
    selected: Option<&HashSet<SegmentId>>,
) -> Result<(), AlignmentError> {
    validate_alignment_response(response, project)?;
    for item in &response.segments {
        if selected.is_some_and(|ids| !ids.contains(&item.id)) {
            continue;
        }
        if item.status == MatchStatus::Unmatched {
            let segment = project
                .lyrics
                .lines
                .iter_mut()
                .flat_map(|line| &mut line.segments)
                .find(|segment| segment.id == item.id)
                .expect("validated segment must exist");
            segment.timing.gemini = None;
            continue;
        }
        project
            .apply_gemini_suggestion(
                item.id,
                AlignmentPoint {
                    time_ms: item.start_ms.expect("validated time must exist"),
                    confidence: item.confidence,
                },
            )
            .map_err(|error| AlignmentError::Invalid(error.to_string()))?;
    }
    Ok(())
}

fn encode_target_audio(project: &SongProject) -> Result<String, AlignmentError> {
    let target = project
        .target
        .as_ref()
        .ok_or_else(|| AlignmentError::Invalid("target audio is missing".into()))?;
    if !target.duration_ms.is_some_and(|duration| duration > 0) {
        return invalid("target duration is missing");
    }
    let metadata = fs::metadata(&target.path)?;
    if metadata.len() > INLINE_AUDIO_LIMIT {
        return invalid("target MP3 exceeds the 14 MiB inline MVP limit");
    }
    Ok(base64::engine::general_purpose::STANDARD.encode(fs::read(&target.path)?))
}

fn ensure_request_size(request: &Value, provider: &str) -> Result<(), AlignmentError> {
    if request.to_string().len() > INLINE_REQUEST_LIMIT {
        return invalid(format!(
            "{provider} inline request exceeds the 19 MiB safety limit"
        ));
    }
    Ok(())
}

fn alignment_prompt(project: &SongProject) -> Result<String, AlignmentError> {
    let mut ids = Vec::new();
    let mut lyric_lines = Vec::new();
    for line in &project.lyrics.lines {
        let [segment] = line.segments.as_slice() else {
            return invalid("full-song alignment requires exactly one segment per lyric line");
        };
        ids.push(segment.id.0);
        lyric_lines.push(line.original.as_str());
    }
    if lyric_lines.is_empty() {
        return invalid("lyrics contain no segments");
    }
    let duration_ms = project
        .target
        .as_ref()
        .and_then(|target| target.duration_ms)
        .filter(|duration| *duration > 0)
        .ok_or_else(|| AlignmentError::Invalid("target duration is missing".into()))?;
    let duration_seconds = duration_ms as f64 / 1_000.0;
    Ok(format!(
        "Listen to the complete target vocal audio before assigning any timestamps. Its measured duration is {duration_seconds:.3} seconds. The lyrics below are the original line-level text with all source timestamps intentionally removed. Keep every lyric line intact: do not split, merge, rewrite, or evenly distribute lines. For each line, find the onset of its first clearly audible sung syllable in the attached audio. Return start_seconds as a precise decimal number in seconds; retain millisecond-level precision when the audio supports it and do not round to whole seconds or tenths. Use unmatched only when that complete lyric line is genuinely absent from the entire target audio. Preserve the exact line order and copy the corresponding id from this ordered id list: {}. Return exactly one result for every line.\n\n--- BEGIN ORIGINAL LYRICS ---\n{}\n--- END ORIGINAL LYRICS ---",
        serde_json::to_string(&ids).expect("IDs must serialize"),
        lyric_lines.join("\n")
    ))
}

fn alignment_schema() -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "properties": {
            "segments": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "properties": {
                        "id": {"type": "integer"},
                        "status": {"type": "string", "enum": ["matched", "unmatched"]},
                        "start_seconds": {
                            "type": ["number", "null"],
                            "description": "Precise onset of the first clearly audible sung syllable, in seconds from the start of the attached audio. Use decimals rather than rounding."
                        },
                        "confidence": {"type": ["number", "null"], "minimum": 0, "maximum": 1}
                    },
                    "required": ["id", "status", "start_seconds", "confidence"]
                }
            }
        },
        "required": ["segments"]
    })
}

fn invalid<T>(message: impl Into<String>) -> Result<T, AlignmentError> {
    Err(AlignmentError::Invalid(message.into()))
}
