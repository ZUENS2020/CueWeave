use cueweave_core::{
    FrequencyScale, PcmAudio, builtin_audio_viz_adapter, list_audio_viz_adapters, spectrogram_tile,
    waveform_bins,
};
use std::f32::consts::PI;

fn sine(freq: f32, sample_rate: u32, duration_ms: u64) -> PcmAudio {
    let count = (u64::from(sample_rate) * duration_ms / 1_000) as usize;
    let samples = (0..count)
        .map(|index| (2.0 * PI * freq * index as f32 / sample_rate as f32).sin())
        .collect();
    PcmAudio {
        sample_rate,
        samples,
    }
}

#[test]
fn peak_and_rms_bins_describe_a_sine() {
    let pcm = sine(440.0, 16_000, 500);
    let bins = waveform_bins(&pcm.samples, 32);
    let peak = bins
        .iter()
        .map(|bin| bin.peak_max.max(bin.peak_min.abs()))
        .fold(0.0_f32, f32::max);
    let rms = bins.iter().map(|bin| bin.rms).fold(0.0_f32, f32::max);
    assert!(peak > 0.9);
    assert!((rms - std::f32::consts::FRAC_1_SQRT_2).abs() < 0.08);
}

#[test]
fn spectrogram_has_no_onset_or_snap_fields() {
    let encoded = serde_json::to_string(&serde_json::json!({
        "start_ms": 0,
        "end_ms": 10,
        "time_bins": 1,
        "frequency_bins": 1,
        "values": "AA=="
    }))
    .unwrap();
    assert!(!encoded.contains("onset"));
    assert!(!encoded.contains("snap"));
    assert!(!encoded.contains("suggested_time"));
}

#[test]
fn linear_spectrogram_peaks_near_the_sine() {
    let pcm = sine(1_000.0, 16_000, 800);
    let tile = spectrogram_tile(&pcm, 0, 800, FrequencyScale::Linear, 64, 48);
    assert_eq!(tile.frequency_bins, 64);
    assert!(!tile.values.is_empty());
    let mut strongest = 0usize;
    let mut peak = 0u8;
    for time in 0..tile.time_bins as usize {
        for freq in 0..tile.frequency_bins as usize {
            let value = tile.values[time * tile.frequency_bins as usize + freq];
            if value >= peak {
                peak = value;
                strongest = freq;
            }
        }
    }
    assert!(peak > 180);
    // 1000 Hz at 16 kHz Nyquist 8 kHz → about 1/8 of the linear axis.
    assert!((5..14).contains(&strongest));
}

#[test]
fn lists_seven_audio_viz_adapters_without_alignment_fields() {
    let adapters = list_audio_viz_adapters();
    assert_eq!(
        adapters
            .iter()
            .map(|adapter| adapter.id.as_str())
            .collect::<Vec<_>>(),
        [
            "peak",
            "rms",
            "peakRms",
            "bands",
            "specLinear",
            "specLog",
            "specMel"
        ]
    );
    assert_eq!(adapters[2].series, ["peak", "rms"]);
    assert_eq!(adapters[5].scale, Some(FrequencyScale::Log));
    assert!(builtin_audio_viz_adapter("peak").is_some());
    assert!(builtin_audio_viz_adapter("onset").is_none());
    let encoded = serde_json::to_string(&adapters).unwrap();
    assert!(!encoded.contains("onset"));
    assert!(!encoded.contains("snap"));
    assert!(!encoded.contains("suggested_time"));
}

#[test]
fn unknown_audio_viz_action_is_rejected() {
    let error = cueweave_core::run_audio_viz(&serde_json::json!({
        "action": "onset",
        "audio_path": "x.mp3",
        "cache_dir": "/tmp"
    }))
    .unwrap_err();
    assert!(error.to_string().contains("unknown audio_viz action"));
}
