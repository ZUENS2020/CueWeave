use crate::{
    AiStudioConfig, DEFAULT_AI_STUDIO_MODEL, LineId, OpenRouterConfig, SongProject,
    alignment::{add_legacy_generation_temperature, add_legacy_temperature},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashSet;
use std::time::Duration;
use thiserror::Error;

const INLINE_REQUEST_LIMIT: usize = 19 * 1024 * 1024;
const DEFAULT_TARGET_LANGUAGE: &str = "Simplified Chinese";

#[derive(Debug, Error)]
pub enum TranslationError {
    #[error("invalid translation: {0}")]
    Invalid(String),
    #[error("translation provider request failed: {0}")]
    Http(#[from] reqwest::Error),
    #[error("{name} HTTP {status}: {message}")]
    Provider {
        name: &'static str,
        status: u16,
        message: String,
    },
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct TranslationItem {
    pub id: LineId,
    pub translation: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct TranslationResponse {
    pub lines: Vec<TranslationItem>,
}

#[derive(Deserialize)]
struct ProviderTranslationResponse {
    lines: Vec<TranslationItem>,
}

pub fn translate_with_openrouter(
    project: &SongProject,
    config: &OpenRouterConfig,
    target_language: Option<&str>,
) -> Result<TranslationResponse, TranslationError> {
    if config.api_key.trim().is_empty() {
        return invalid("API key is empty");
    }
    if config.model.trim().is_empty() || config.model.len() > 200 {
        return invalid("OpenRouter model name is invalid");
    }
    let request = build_openrouter_translation_request(project, &config.model, target_language)?;
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
        return Err(TranslationError::Provider {
            name: "OpenRouter",
            status: status.as_u16(),
            message: body,
        });
    }
    parse_openrouter_translation_envelope(&body, project)
}

pub fn translate_with_ai_studio(
    project: &SongProject,
    config: &AiStudioConfig,
    target_language: Option<&str>,
) -> Result<TranslationResponse, TranslationError> {
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
    let request =
        build_ai_studio_translation_request_for_model(project, target_language, &config.model)?;
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
        return Err(TranslationError::Provider {
            name: "AI Studio",
            status: status.as_u16(),
            message: body,
        });
    }
    parse_ai_studio_translation_envelope(&body, project)
}

pub fn build_openrouter_translation_request(
    project: &SongProject,
    model: &str,
    target_language: Option<&str>,
) -> Result<Value, TranslationError> {
    let prompt = translation_prompt(project, target_language)?;
    let mut request = json!({
        "model": model,
        "messages": [{
            "role": "user",
            "content": [{"type": "text", "text": prompt}]
        }],
        "response_format": {
            "type": "json_schema",
            "json_schema": {
                "name": "cueweave_translation",
                "strict": true,
                "schema": translation_schema()
            }
        },
        "provider": {"require_parameters": true},
        "stream": false
    });
    add_legacy_temperature(&mut request, model);
    Ok(request)
}

pub fn build_ai_studio_translation_request(
    project: &SongProject,
    target_language: Option<&str>,
) -> Result<Value, TranslationError> {
    build_ai_studio_translation_request_for_model(project, target_language, DEFAULT_AI_STUDIO_MODEL)
}

pub fn build_ai_studio_translation_request_for_model(
    project: &SongProject,
    target_language: Option<&str>,
    model: &str,
) -> Result<Value, TranslationError> {
    let prompt = translation_prompt(project, target_language)?;
    let mut request = json!({
        "contents": [{
            "role": "user",
            "parts": [{"text": prompt}]
        }],
        "generationConfig": {
            "responseFormat": {
                "text": {
                    "mimeType": "APPLICATION_JSON",
                    "schema": translation_schema()
                }
            }
        }
    });
    add_legacy_generation_temperature(&mut request, model);
    Ok(request)
}

pub fn parse_openrouter_translation_envelope(
    json: &str,
    project: &SongProject,
) -> Result<TranslationResponse, TranslationError> {
    let envelope: Value = serde_json::from_str(json).map_err(|error| {
        TranslationError::Invalid(format!("OpenRouter envelope JSON failed: {error}"))
    })?;
    let text = envelope
        .pointer("/choices/0/message/content")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            TranslationError::Invalid("OpenRouter returned no structured text".into())
        })?;
    parse_translation_response(text, project)
}

pub fn parse_ai_studio_translation_envelope(
    json: &str,
    project: &SongProject,
) -> Result<TranslationResponse, TranslationError> {
    let envelope: Value = serde_json::from_str(json).map_err(|error| {
        TranslationError::Invalid(format!("AI Studio envelope JSON failed: {error}"))
    })?;
    let text = envelope
        .pointer("/candidates/0/content/parts/0/text")
        .and_then(Value::as_str)
        .ok_or_else(|| TranslationError::Invalid("AI Studio returned no structured text".into()))?;
    parse_translation_response(text, project)
}

pub fn parse_translation_response(
    json: &str,
    project: &SongProject,
) -> Result<TranslationResponse, TranslationError> {
    let provider: ProviderTranslationResponse = serde_json::from_str(json)
        .map_err(|error| TranslationError::Invalid(format!("translation JSON failed: {error}")))?;
    let response = TranslationResponse {
        lines: provider.lines,
    };
    validate_translation_response(&response, project)?;
    Ok(response)
}

pub fn validate_translation_response(
    response: &TranslationResponse,
    project: &SongProject,
) -> Result<(), TranslationError> {
    let expected: Vec<_> = project.lyrics.lines.iter().map(|line| line.id).collect();
    let expected_set: HashSet<_> = expected.iter().copied().collect();
    let mut seen = HashSet::new();
    for (index, item) in response.lines.iter().enumerate() {
        if !expected_set.contains(&item.id) {
            return invalid(format!("unknown line id {}", item.id.0));
        }
        if expected.get(index) != Some(&item.id) {
            return invalid(format!("line {} is in the wrong ID order", item.id.0));
        }
        if !seen.insert(item.id) {
            return invalid(format!("duplicate line id {}", item.id.0));
        }
        if item.translation.chars().count() > 2_000 {
            return invalid(format!("line {} translation is too long", item.id.0));
        }
    }
    if seen.len() != expected.len() {
        let missing: Vec<_> = expected
            .into_iter()
            .filter(|id| !seen.contains(id))
            .map(|id| id.0)
            .collect();
        return invalid(format!("missing line ids {missing:?}"));
    }
    Ok(())
}

pub fn apply_translation_response(
    project: &mut SongProject,
    response: &TranslationResponse,
) -> Result<(), TranslationError> {
    validate_translation_response(response, project)?;
    for item in &response.lines {
        let line = project
            .lyrics
            .lines
            .iter_mut()
            .find(|line| line.id == item.id)
            .expect("validated line must exist");
        let trimmed = item.translation.trim();
        line.translation = (!trimmed.is_empty()).then(|| trimmed.to_owned());
    }
    Ok(())
}

fn translation_prompt(
    project: &SongProject,
    target_language: Option<&str>,
) -> Result<String, TranslationError> {
    let language = target_language
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(DEFAULT_TARGET_LANGUAGE);
    if language.chars().count() > 80 {
        return invalid("target language is too long");
    }
    let mut ids = Vec::new();
    let mut lyric_lines = Vec::new();
    for line in &project.lyrics.lines {
        ids.push(line.id.0);
        lyric_lines.push(line.original.as_str());
    }
    if lyric_lines.is_empty() {
        return invalid("lyrics contain no lines");
    }
    let song = song_context(project);
    Ok(format!(
        "{song}The block below is the complete original lyric, sent as one song in a single request. Read every line before translating anything. Understand the narrative, recurring images, pronouns, and how later lines refer back to earlier ones. Then translate the whole song into {language} as a coherent lyric, not as isolated sentences. Keep the same number of lines and the same order. Do not merge, split, rewrite, or omit lines. Do not add translator notes, romanization, pronunciation, or commentary. Prefer a natural singable lyric over a word-for-word gloss, and keep names, images, and tone consistent across the song. If a line is already in {language}, copy it unchanged. Preserve the exact line order and copy the corresponding id from this ordered id list: {}. Return exactly one translation for every line.\n\n--- BEGIN ORIGINAL LYRICS ---\n{}\n--- END ORIGINAL LYRICS ---",
        serde_json::to_string(&ids).expect("IDs must serialize"),
        lyric_lines.join("\n")
    ))
}

fn song_context(project: &SongProject) -> String {
    let title = project
        .metadata
        .draft
        .title
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let artists: Vec<_> = project
        .metadata
        .draft
        .artists
        .iter()
        .map(|artist| artist.trim())
        .filter(|artist| !artist.is_empty())
        .collect();
    match (title, artists.is_empty()) {
        (Some(title), false) => format!("Song: {title} by {}.\n\n", artists.join(", ")),
        (Some(title), true) => format!("Song: {title}.\n\n"),
        (None, false) => format!("Song by {}.\n\n", artists.join(", ")),
        (None, true) => String::new(),
    }
}

fn translation_schema() -> Value {
    json!({
        "type": "object",
        "additionalProperties": false,
        "properties": {
            "lines": {
                "type": "array",
                "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "properties": {
                        "id": {"type": "integer"},
                        "translation": {"type": "string"}
                    },
                    "required": ["id", "translation"]
                }
            }
        },
        "required": ["lines"]
    })
}

fn ensure_request_size(request: &Value, provider: &str) -> Result<(), TranslationError> {
    if request.to_string().len() > INLINE_REQUEST_LIMIT {
        return invalid(format!(
            "{provider} inline request exceeds the 19 MiB safety limit"
        ));
    }
    Ok(())
}

fn invalid<T>(message: impl Into<String>) -> Result<T, TranslationError> {
    Err(TranslationError::Invalid(message.into()))
}
