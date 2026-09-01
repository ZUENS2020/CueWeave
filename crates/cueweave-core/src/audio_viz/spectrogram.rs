use super::PcmAudio;
use rustfft::{FftPlanner, num_complex::Complex};
use serde::{Deserialize, Serialize};
use std::f32::consts::PI;

pub const FFT_SIZE: usize = 2_048;
pub const HOP_SIZE: usize = 512;
const NYQUIST_FLOOR_HZ: f32 = 20.0;
const DB_FLOOR: f32 = -80.0;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FrequencyScale {
    Linear,
    #[default]
    Log,
    Mel,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SpectrogramTile {
    pub start_ms: u64,
    pub end_ms: u64,
    pub time_bins: u32,
    pub frequency_bins: u32,
    pub values: Vec<u8>,
}

pub fn spectrogram_tile(
    pcm: &PcmAudio,
    start_ms: u64,
    end_ms: u64,
    scale: FrequencyScale,
    frequency_bins: u32,
    max_time_bins: u32,
) -> SpectrogramTile {
    let frequency_bins = frequency_bins.clamp(8, 512);
    let nyquist = pcm.sample_rate as f32 / 2.0;
    let start = sample_index(pcm, start_ms);
    let end = sample_index(pcm, end_ms.max(start_ms.saturating_add(1))).max(start + 1);
    let slice = &pcm.samples[start.min(pcm.samples.len())..end.min(pcm.samples.len())];
    let magnitudes = stft_magnitudes(slice);
    let mapped: Vec<Vec<f32>> = magnitudes
        .iter()
        .map(|frame| {
            map_frequency(
                frame,
                pcm.sample_rate,
                nyquist,
                scale,
                frequency_bins as usize,
            )
        })
        .collect();
    let pooled = pool_time(mapped, max_time_bins.max(1) as usize);
    let values = to_db_bytes(&pooled);
    SpectrogramTile {
        start_ms,
        end_ms,
        time_bins: pooled.len() as u32,
        frequency_bins,
        values,
    }
}

fn sample_index(pcm: &PcmAudio, time_ms: u64) -> usize {
    let index = time_ms.saturating_mul(u64::from(pcm.sample_rate)) / 1_000;
    (index as usize).min(pcm.samples.len())
}

fn stft_magnitudes(samples: &[f32]) -> Vec<Vec<f32>> {
    let mut planner = FftPlanner::<f32>::new();
    let fft = planner.plan_fft_forward(FFT_SIZE);
    let window = hann(FFT_SIZE);
    let spectrum_bins = FFT_SIZE / 2;
    let mut frames = Vec::new();
    let mut offset = 0;
    while offset < samples.len() {
        let mut buffer = vec![Complex { re: 0.0, im: 0.0 }; FFT_SIZE];
        let available = (samples.len() - offset).min(FFT_SIZE);
        for index in 0..available {
            buffer[index].re = samples[offset + index] * window[index];
        }
        fft.process(&mut buffer);
        frames.push(
            buffer
                .iter()
                .take(spectrum_bins)
                .map(|bin| (bin.re * bin.re + bin.im * bin.im).sqrt())
                .collect(),
        );
        if offset + HOP_SIZE >= samples.len() {
            break;
        }
        offset += HOP_SIZE;
    }
    if frames.is_empty() {
        frames.push(vec![0.0; spectrum_bins]);
    }
    frames
}

fn map_frequency(
    spectrum: &[f32],
    sample_rate: u32,
    nyquist: f32,
    scale: FrequencyScale,
    display_bins: usize,
) -> Vec<f32> {
    match scale {
        FrequencyScale::Linear => pool_linear(spectrum, display_bins),
        FrequencyScale::Log => map_log(spectrum, sample_rate, nyquist, display_bins),
        FrequencyScale::Mel => map_mel(spectrum, sample_rate, nyquist, display_bins),
    }
}

fn pool_linear(spectrum: &[f32], display_bins: usize) -> Vec<f32> {
    let mut output = vec![0.0; display_bins];
    if spectrum.is_empty() {
        return output;
    }
    for (index, value) in spectrum.iter().enumerate() {
        let bin = index * display_bins / spectrum.len();
        output[bin.min(display_bins - 1)] = output[bin.min(display_bins - 1)].max(*value);
    }
    output
}

fn map_log(spectrum: &[f32], sample_rate: u32, nyquist: f32, display_bins: usize) -> Vec<f32> {
    let mut output = vec![0.0; display_bins];
    let floor = NYQUIST_FLOOR_HZ.min(nyquist / 4.0);
    let ratio = (nyquist / floor).max(1.000_1);
    #[allow(clippy::needless_range_loop)]
    for display in 0..display_bins {
        let low_hz = if display == 0 {
            floor
        } else {
            floor * ratio.powf((display as f32 - 1.0) / (display_bins as f32 - 1.0).max(1.0))
        };
        let high_hz = floor * ratio.powf(display as f32 / (display_bins as f32 - 1.0).max(1.0));
        output[display] = max_in_hz_range(spectrum, sample_rate, low_hz, high_hz);
    }
    output
}

fn map_mel(spectrum: &[f32], sample_rate: u32, nyquist: f32, display_bins: usize) -> Vec<f32> {
    let mut output = vec![0.0; display_bins];
    let points = display_bins + 2;
    let max_mel = hz_to_mel(nyquist);
    let mut edges = Vec::with_capacity(points);
    for index in 0..points {
        let mel = max_mel * index as f32 / (points - 1) as f32;
        edges.push(hz_to_bin(mel_to_hz(mel), sample_rate, spectrum.len()));
    }
    for display in 0..display_bins {
        let left = edges[display];
        let center = edges[display + 1];
        let right = edges[display + 2];
        let mut sum = 0.0;
        let mut weight = 0.0;
        #[allow(clippy::needless_range_loop)]
        for bin in left..=right.min(spectrum.len().saturating_sub(1)) {
            let scale = if bin <= center {
                if center == left {
                    1.0
                } else {
                    (bin - left) as f32 / (center - left).max(1) as f32
                }
            } else if right == center {
                1.0
            } else {
                (right - bin) as f32 / (right - center).max(1) as f32
            };
            sum += spectrum[bin] * scale;
            weight += scale;
        }
        output[display] = if weight > 0.0 { sum / weight } else { 0.0 };
    }
    output
}

fn pool_time(frames: Vec<Vec<f32>>, max_bins: usize) -> Vec<Vec<f32>> {
    if frames.len() <= max_bins {
        return frames;
    }
    let mut pooled = Vec::with_capacity(max_bins);
    for index in 0..max_bins {
        let start = index * frames.len() / max_bins;
        let end = ((index + 1) * frames.len() / max_bins).max(start + 1);
        let width = frames[0].len();
        let mut merged = vec![0.0_f32; width];
        for frame in &frames[start..end] {
            for (bin, value) in frame.iter().enumerate() {
                merged[bin] = merged[bin].max(*value);
            }
        }
        pooled.push(merged);
    }
    pooled
}

fn to_db_bytes(frames: &[Vec<f32>]) -> Vec<u8> {
    let peak = frames
        .iter()
        .flatten()
        .copied()
        .fold(0.0_f32, f32::max)
        .max(1.0e-12);
    let mut values = Vec::with_capacity(frames.len() * frames.first().map(Vec::len).unwrap_or(0));
    for frame in frames {
        for value in frame {
            let db = (20.0 * (value / peak).max(1.0e-12).log10()).clamp(DB_FLOOR, 0.0);
            let scaled = ((db - DB_FLOOR) / -DB_FLOOR) * 255.0;
            values.push(scaled.round().clamp(0.0, 255.0) as u8);
        }
    }
    values
}

fn max_in_hz_range(spectrum: &[f32], sample_rate: u32, low_hz: f32, high_hz: f32) -> f32 {
    let low = hz_to_bin(low_hz, sample_rate, spectrum.len());
    let high = hz_to_bin(high_hz, sample_rate, spectrum.len()).max(low);
    spectrum[low..=high.min(spectrum.len().saturating_sub(1))]
        .iter()
        .copied()
        .fold(0.0, f32::max)
}

fn hz_to_bin(hz: f32, sample_rate: u32, bins: usize) -> usize {
    if bins == 0 {
        return 0;
    }
    let nyquist = sample_rate as f32 / 2.0;
    ((hz.clamp(0.0, nyquist) / nyquist) * (bins.saturating_sub(1)) as f32).round() as usize
}

fn hz_to_mel(hz: f32) -> f32 {
    2595.0 * (1.0 + hz / 700.0).log10()
}

fn mel_to_hz(mel: f32) -> f32 {
    700.0 * (10.0_f32.powf(mel / 2595.0) - 1.0)
}

fn hann(size: usize) -> Vec<f32> {
    if size <= 1 {
        return vec![1.0; size];
    }
    (0..size)
        .map(|index| 0.5 - 0.5 * (2.0 * PI * index as f32 / (size - 1) as f32).cos())
        .collect()
}
