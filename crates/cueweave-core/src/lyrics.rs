use crate::{Credit, CreditId, LineId, ProjectError, SongProject};
use serde_json::Value;
use thiserror::Error;

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct NormalizedLyrics {
    pub credits: Vec<Credit>,
    pub lines: Vec<String>,
}

#[derive(Debug, Error)]
pub enum LyricsError {
    #[error("lyrics contain no usable text")]
    Empty,
    #[error(transparent)]
    Project(#[from] ProjectError),
}

pub fn normalize_lyrics(raw: &str) -> NormalizedLyrics {
    let mut normalized = NormalizedLyrics::default();
    for raw_line in raw.lines() {
        let Some(text) = normalize_line(raw_line) else {
            continue;
        };
        if let Some(credit) = parse_credit(&text) {
            if !normalized.credits.contains(&credit) {
                normalized.credits.push(credit);
            }
        } else if normalized.lines.last() != Some(&text) {
            normalized.lines.push(text);
        }
    }
    normalized
}

pub fn replace_project_lyrics(
    project: &mut SongProject,
    original: &str,
    translation: Option<&str>,
) -> Result<(), LyricsError> {
    let original = normalize_lyrics(original);
    if original.lines.is_empty() {
        return Err(LyricsError::Empty);
    }
    let translations = translation.map(normalize_lyrics).unwrap_or_default().lines;

    project.lyrics.credits = original.credits;
    crate::assign_credit_ids(&mut project.lyrics.credits)?;
    project.lyrics.lines.clear();
    project.timeline.clear();
    for (index, text) in original.lines.into_iter().enumerate() {
        let segments = segment_text(&text);
        let line_id = project.add_line(text, segments)?;
        if let Some(translation) = translations.get(index) {
            project
                .lyrics
                .lines
                .iter_mut()
                .find(|line| line.id == line_id)
                .expect("new lyric line must exist")
                .translation = Some(translation.clone());
        }
    }
    crate::sync_credit_cues(project);
    Ok(())
}

pub fn insert_project_lyrics(
    project: &mut SongProject,
    after_line_id: Option<LineId>,
    raw: &str,
) -> Result<Vec<LineId>, LyricsError> {
    let texts: Vec<String> = raw.lines().filter_map(normalize_line).collect();
    if texts.is_empty() {
        return Err(LyricsError::Empty);
    }
    let start = match after_line_id {
        None => 0,
        Some(id) => {
            project
                .lyrics
                .lines
                .iter()
                .position(|line| line.id == id)
                .ok_or(ProjectError::NotFound("line", id.0))?
                + 1
        }
    };
    let mut inserted = Vec::with_capacity(texts.len());
    for (offset, text) in texts.into_iter().enumerate() {
        let segments = segment_text(&text);
        inserted.push(project.insert_line_at(start + offset, text, segments)?);
    }
    Ok(inserted)
}

pub fn apply_line_translations(
    project: &mut SongProject,
    translation: &str,
) -> Result<usize, LyricsError> {
    if project.lyrics.lines.is_empty() {
        return Err(LyricsError::Empty);
    }
    let translations = normalize_translation_lines(translation);
    if translations.is_empty() {
        return Err(LyricsError::Empty);
    }
    let mut applied = 0;
    for (index, line) in project.lyrics.lines.iter_mut().enumerate() {
        if let Some(text) = translations.get(index) {
            line.translation = Some(text.clone());
            applied += 1;
        }
    }
    Ok(applied)
}

pub fn normalize_translation_lines(raw: &str) -> Vec<String> {
    raw.lines().filter_map(normalize_line).collect()
}

fn normalize_line(raw: &str) -> Option<String> {
    let mut text = raw.trim().trim_start_matches('\u{feff}').trim().to_owned();
    if text.is_empty() {
        return None;
    }
    if let Some(json_text) = json_credit_text(&text) {
        text = json_text;
    }
    while let Some(end) = text.strip_prefix('[').and_then(|rest| rest.find(']')) {
        let tag = &text[1..=end];
        if is_time_tag(tag) {
            text = text[end + 2..].trim_start().to_owned();
        } else if is_metadata_tag(tag) {
            return None;
        } else {
            break;
        }
    }
    text = strip_angle_timings(&text);
    text = strip_word_timings(&text).trim().to_owned();
    (!text.is_empty()).then_some(text)
}

fn is_time_tag(tag: &str) -> bool {
    let tag = tag.trim();
    tag.contains(':')
        && tag.chars().all(|character| {
            character.is_ascii_digit() || matches!(character, ':' | '.' | ',' | '-')
        })
        || tag.contains(',')
            && tag
                .chars()
                .all(|character| character.is_ascii_digit() || matches!(character, ',' | '-'))
}

fn is_metadata_tag(tag: &str) -> bool {
    let Some((name, _)) = tag.split_once(':') else {
        return false;
    };
    matches!(
        name.trim().to_ascii_lowercase().as_str(),
        "ar" | "al" | "ti" | "by" | "offset" | "re" | "ve"
    )
}

fn strip_word_timings(text: &str) -> String {
    let mut output = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find('(') {
        output.push_str(&rest[..start]);
        let Some(end) = rest[start + 1..].find(')') else {
            output.push_str(&rest[start..]);
            return output;
        };
        let inner = &rest[start + 1..start + 1 + end];
        if !inner.contains(',')
            || !inner
                .chars()
                .all(|character| character.is_ascii_digit() || matches!(character, ',' | '-'))
        {
            output.push('(');
            rest = &rest[start + 1..];
            continue;
        }
        rest = &rest[start + end + 2..];
    }
    output.push_str(rest);
    output
}

fn strip_angle_timings(text: &str) -> String {
    let mut output = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find('<') {
        output.push_str(&rest[..start]);
        let Some(end) = rest[start + 1..].find('>') else {
            output.push_str(&rest[start..]);
            return output;
        };
        let inner = &rest[start + 1..start + 1 + end];
        if !is_time_tag(inner) {
            output.push('<');
            rest = &rest[start + 1..];
            continue;
        }
        rest = &rest[start + end + 2..];
    }
    output.push_str(rest);
    output
}

fn json_credit_text(text: &str) -> Option<String> {
    let value: Value = serde_json::from_str(text).ok()?;
    let parts = value.get("c")?.as_array()?;
    let combined: String = parts
        .iter()
        .filter_map(|part| part.get("tx").and_then(Value::as_str))
        .collect();
    (!combined.trim().is_empty()).then(|| combined.trim().to_owned())
}

fn parse_credit(text: &str) -> Option<Credit> {
    const PREFIXES: &[&str] = &[
        "作词", "作詞", "作曲", "编曲", "編曲", "词", "詞", "曲", "Lyricist", "Composer",
        "Arranger",
    ];
    let (label, value) = text.split_once([':', '：'])?;
    PREFIXES
        .iter()
        .any(|prefix| label.trim().eq_ignore_ascii_case(prefix))
        .then(|| Credit {
            id: CreditId(0),
            label: label.trim().to_owned(),
            value: value.trim().to_owned(),
        })
        .filter(|credit| !credit.value.is_empty())
}

fn segment_text(text: &str) -> Vec<String> {
    vec![text.to_owned()]
}
