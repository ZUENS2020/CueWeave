use serde::Deserialize;
use std::time::Duration;
use thiserror::Error;

const NETEASE_LYRIC_URL: &str = "https://music.163.com/api/song/lyric";
const MAX_LYRIC_RESPONSE: u64 = 5 * 1024 * 1024;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NeteaseLyrics {
    pub original: String,
    pub translation: Option<String>,
}

#[derive(Debug, Error)]
pub enum NeteaseError {
    #[error("NetEase request failed: {0}")]
    Http(#[from] reqwest::Error),
    #[error("NetEase returned HTTP {0}")]
    Status(u16),
    #[error("invalid NetEase lyrics: {0}")]
    Invalid(String),
}

pub fn fetch_netease_lyrics(music_id: u64) -> Result<NeteaseLyrics, NeteaseError> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("CueWeave/0.1")
        .build()?;
    let response = client
        .get(NETEASE_LYRIC_URL)
        .header("Referer", "https://music.163.com/")
        .query(&[
            ("id", music_id.to_string()),
            ("lv", "-1".into()),
            ("tv", "-1".into()),
            ("rv", "-1".into()),
            ("kv", "-1".into()),
        ])
        .send()?;
    if !response.status().is_success() {
        return Err(NeteaseError::Status(response.status().as_u16()));
    }
    if response
        .content_length()
        .is_some_and(|length| length > MAX_LYRIC_RESPONSE)
    {
        return Err(NeteaseError::Invalid("response is too large".into()));
    }
    let body = response.bytes()?;
    if body.len() > MAX_LYRIC_RESPONSE as usize {
        return Err(NeteaseError::Invalid("response is too large".into()));
    }
    let text = std::str::from_utf8(&body)
        .map_err(|error| NeteaseError::Invalid(format!("response UTF-8 failed: {error}")))?;
    decode_netease_payload(text)
}

pub fn decode_netease_payload(json: &str) -> Result<NeteaseLyrics, NeteaseError> {
    let payload: LyricsPayload = serde_json::from_str(json)
        .map_err(|error| NeteaseError::Invalid(format!("JSON failed: {error}")))?;
    if payload.code != 200 {
        return Err(NeteaseError::Invalid(format!("API code {}", payload.code)));
    }
    let original = payload
        .lrc
        .and_then(|lyrics| lyrics.lyric)
        .filter(|lyrics| !lyrics.trim().is_empty())
        .ok_or_else(|| NeteaseError::Invalid("original lyric text is missing".into()))?;
    let translation = payload
        .tlyric
        .and_then(|lyrics| lyrics.lyric)
        .filter(|lyrics| !lyrics.trim().is_empty());
    Ok(NeteaseLyrics {
        original,
        translation,
    })
}

#[derive(Deserialize)]
struct LyricsPayload {
    code: i64,
    #[serde(default)]
    lrc: Option<LyricText>,
    #[serde(default)]
    tlyric: Option<LyricText>,
}

#[derive(Deserialize)]
struct LyricText {
    #[serde(default)]
    lyric: Option<String>,
}
