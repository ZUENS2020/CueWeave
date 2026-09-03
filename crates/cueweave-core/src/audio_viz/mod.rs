mod adapter;
mod cache;
mod decode;
mod spectrogram;
mod waveform;

use crate::audio_payload_sha256;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::PathBuf;
use thiserror::Error;

pub use adapter::{
    AudioVizAdapter, AudioVizAdapterInfo, AudioVizSurface, builtin_audio_viz_adapters,
    list_audio_viz_adapters,
};
pub use spectrogram::{FFT_SIZE, FrequencyScale, HOP_SIZE, SpectrogramTile, spectrogram_tile};
pub use waveform::{WaveformBin, waveform_bins};

pub const VISUALIZATION_VERSION: &str = "v1";
const DEFAULT_WAVEFORM_BINS: usize = 4_096;
const DEFAULT_FREQUENCY_BINS: u32 = 128;
const MAX_TIME_BINS: u32 = 1_024;

#[derive(Debug, Error)]
pub enum AudioVizError {
    #[error("audio visualization I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid visualization request: {0}")]
    Invalid(String),
    #[error("audio decode failed: {0}")]
    Decode(String),
}

#[derive(Clone, Debug, PartialEq)]
pub struct PcmAudio {
    pub sample_rate: u32,
    pub samples: Vec<f32>,
}

impl PcmAudio {
    pub fn duration_ms(&self) -> u64 {
        if self.sample_rate == 0 || self.samples.is_empty() {
            return 0;
        }
        (self.samples.len() as u64 * 1_000) / u64::from(self.sample_rate)
    }
}

#[derive(Clone, Debug, Deserialize)]
struct AudioVizRequest {
    action: String,
    audio_path: PathBuf,
    #[serde(default)]
    sha256: Option<String>,
    cache_dir: PathBuf,
    #[serde(default)]
    waveform_bins: Option<usize>,
    #[serde(default)]
    start_ms: Option<u64>,
    #[serde(default)]
    end_ms: Option<u64>,
    #[serde(default)]
    scale: Option<FrequencyScale>,
    #[serde(default)]
    frequency_bins: Option<u32>,
}

#[derive(Clone, Debug, Serialize)]
struct WaveformResponse {
    sample_rate: u32,
    duration_ms: u64,
    peak_min: Vec<f32>,
    peak_max: Vec<f32>,
    rms: Vec<f32>,
}

#[derive(Clone, Debug, Serialize)]
struct SpectrogramResponse {
    start_ms: u64,
    end_ms: u64,
    time_bins: u32,
    frequency_bins: u32,
    values: String,
}

pub fn run_audio_viz(payload: &Value) -> Result<Value, AudioVizError> {
    let request: AudioVizRequest = serde_json::from_value(payload.clone())
        .map_err(|error| AudioVizError::Invalid(error.to_string()))?;
    match request.action.as_str() {
        "prepare" | "waveform" => serde_json::to_value(prepare(&request)?)
            .map_err(|error| AudioVizError::Invalid(error.to_string())),
        "spectrogram" => serde_json::to_value(spectrogram(&request)?)
            .map_err(|error| AudioVizError::Invalid(error.to_string())),
        other => Err(AudioVizError::Invalid(format!(
            "unknown audio_viz action: {other}"
        ))),
    }
}

fn prepare(request: &AudioVizRequest) -> Result<WaveformResponse, AudioVizError> {
    let pcm = load_pcm(request)?;
    let bin_count = request
        .waveform_bins
        .unwrap_or(DEFAULT_WAVEFORM_BINS)
        .max(1);
    let bins = cache::waveform(&request.cache_dir, &digest(request)?, bin_count, || {
        Ok(waveform_bins(&pcm.samples, bin_count))
    })?;
    Ok(WaveformResponse {
        sample_rate: pcm.sample_rate,
        duration_ms: pcm.duration_ms(),
        peak_min: bins.iter().map(|bin| bin.peak_min).collect(),
        peak_max: bins.iter().map(|bin| bin.peak_max).collect(),
        rms: bins.iter().map(|bin| bin.rms).collect(),
    })
}

fn spectrogram(request: &AudioVizRequest) -> Result<SpectrogramResponse, AudioVizError> {
    let pcm = load_pcm(request)?;
    let duration = pcm.duration_ms();
    let start_ms = request.start_ms.unwrap_or(0).min(duration);
    let end_ms = request
        .end_ms
        .unwrap_or(duration)
        .clamp(start_ms.saturating_add(1), duration.max(1));
    let scale = request.scale.unwrap_or(FrequencyScale::Log);
    let frequency_bins = request
        .frequency_bins
        .unwrap_or(DEFAULT_FREQUENCY_BINS)
        .clamp(16, 512);
    let tile = cache::spectrogram(
        &request.cache_dir,
        &digest(request)?,
        start_ms,
        end_ms,
        scale,
        frequency_bins,
        || {
            Ok(spectrogram_tile(
                &pcm,
                start_ms,
                end_ms,
                scale,
                frequency_bins,
                MAX_TIME_BINS,
            ))
        },
    )?;
    Ok(SpectrogramResponse {
        start_ms: tile.start_ms,
        end_ms: tile.end_ms,
        time_bins: tile.time_bins,
        frequency_bins: tile.frequency_bins,
        values: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &tile.values),
    })
}

fn load_pcm(request: &AudioVizRequest) -> Result<PcmAudio, AudioVizError> {
    cache::pcm(&request.cache_dir, &digest(request)?, || {
        decode::decode_mono_pcm(&request.audio_path)
    })
}

fn digest(request: &AudioVizRequest) -> Result<String, AudioVizError> {
    if let Some(sha) = request
        .sha256
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return Ok(sha.to_owned());
    }
    audio_payload_sha256(&request.audio_path)
        .map_err(|error| AudioVizError::Invalid(error.to_string()))
}
