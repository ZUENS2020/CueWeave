use super::FrequencyScale;
use serde::{Deserialize, Serialize};

/// How a visualization adapter should be drawn. Unknown surfaces are skipped.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioVizSurface {
    Waveform,
    Spectrogram,
    Bands,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AudioVizAdapterInfo {
    pub id: String,
    pub title: String,
    pub detail: String,
    pub surface: AudioVizSurface,
    #[serde(default)]
    pub series: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scale: Option<FrequencyScale>,
}

/// In-process visualization adapter. Future waveforms register here; there is
/// no dylib / WASM loader. Adapters never emit onset, snap, or suggested times.
pub trait AudioVizAdapter: Send + Sync {
    fn info(&self) -> AudioVizAdapterInfo;
}

#[derive(Clone, Copy)]
struct BuiltinVizAdapter {
    id: &'static str,
    title: &'static str,
    detail: &'static str,
    surface: AudioVizSurface,
    series: &'static [&'static str],
    scale: Option<FrequencyScale>,
}

impl AudioVizAdapter for BuiltinVizAdapter {
    fn info(&self) -> AudioVizAdapterInfo {
        AudioVizAdapterInfo {
            id: self.id.into(),
            title: self.title.into(),
            detail: self.detail.into(),
            surface: self.surface,
            series: self
                .series
                .iter()
                .map(|value| (*value).to_string())
                .collect(),
            scale: self.scale,
        }
    }
}

const PEAK: BuiltinVizAdapter = BuiltinVizAdapter {
    id: "peak",
    title: "Peak",
    detail: "Peak envelope",
    surface: AudioVizSurface::Waveform,
    series: &["peak"],
    scale: None,
};
const RMS: BuiltinVizAdapter = BuiltinVizAdapter {
    id: "rms",
    title: "RMS",
    detail: "RMS envelope",
    surface: AudioVizSurface::Waveform,
    series: &["rms"],
    scale: None,
};
const PEAK_RMS: BuiltinVizAdapter = BuiltinVizAdapter {
    id: "peakRms",
    title: "Peak + RMS",
    detail: "Peak envelope with RMS overlay",
    surface: AudioVizSurface::Waveform,
    series: &["peak", "rms"],
    scale: None,
};
const BANDS: BuiltinVizAdapter = BuiltinVizAdapter {
    id: "bands",
    title: "Band Energy",
    detail: "Low / mid / high energy",
    surface: AudioVizSurface::Bands,
    series: &[],
    scale: None,
};
const SPEC_LINEAR: BuiltinVizAdapter = BuiltinVizAdapter {
    id: "specLinear",
    title: "Spec · Linear",
    detail: "Linear STFT",
    surface: AudioVizSurface::Spectrogram,
    series: &[],
    scale: Some(FrequencyScale::Linear),
};
const SPEC_LOG: BuiltinVizAdapter = BuiltinVizAdapter {
    id: "specLog",
    title: "Spec · Log",
    detail: "Log-frequency STFT",
    surface: AudioVizSurface::Spectrogram,
    series: &[],
    scale: Some(FrequencyScale::Log),
};
const SPEC_MEL: BuiltinVizAdapter = BuiltinVizAdapter {
    id: "specMel",
    title: "Spec · Mel",
    detail: "Mel spectrogram",
    surface: AudioVizSurface::Spectrogram,
    series: &[],
    scale: Some(FrequencyScale::Mel),
};

pub fn builtin_audio_viz_adapters() -> Vec<Box<dyn AudioVizAdapter>> {
    vec![
        Box::new(PEAK),
        Box::new(RMS),
        Box::new(PEAK_RMS),
        Box::new(BANDS),
        Box::new(SPEC_LINEAR),
        Box::new(SPEC_LOG),
        Box::new(SPEC_MEL),
    ]
}

pub fn builtin_audio_viz_adapter(id: &str) -> Option<Box<dyn AudioVizAdapter>> {
    builtin_audio_viz_adapters()
        .into_iter()
        .find(|adapter| adapter.info().id == id)
}

pub fn list_audio_viz_adapters() -> Vec<AudioVizAdapterInfo> {
    builtin_audio_viz_adapters()
        .into_iter()
        .map(|adapter| adapter.info())
        .collect()
}
