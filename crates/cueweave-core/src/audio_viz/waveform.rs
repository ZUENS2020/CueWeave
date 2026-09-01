#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WaveformBin {
    pub peak_min: f32,
    pub peak_max: f32,
    pub rms: f32,
}

pub fn waveform_bins(samples: &[f32], bin_count: usize) -> Vec<WaveformBin> {
    let bin_count = bin_count.max(1);
    if samples.is_empty() {
        return vec![
            WaveformBin {
                peak_min: 0.0,
                peak_max: 0.0,
                rms: 0.0,
            };
            bin_count
        ];
    }
    let mut bins = vec![
        WaveformBin {
            peak_min: 0.0,
            peak_max: 0.0,
            rms: 0.0,
        };
        bin_count
    ];
    let mut sums = vec![0.0_f64; bin_count];
    let mut counts = vec![0_u32; bin_count];
    let last = samples.len().saturating_sub(1) as u64;
    for (index, sample) in samples.iter().copied().enumerate() {
        let bin = if last == 0 {
            0
        } else {
            ((index as u64 * bin_count as u64) / (last + 1)).min(bin_count as u64 - 1) as usize
        };
        let slot = &mut bins[bin];
        if counts[bin] == 0 {
            slot.peak_min = sample;
            slot.peak_max = sample;
        } else {
            slot.peak_min = slot.peak_min.min(sample);
            slot.peak_max = slot.peak_max.max(sample);
        }
        sums[bin] += f64::from(sample * sample);
        counts[bin] += 1;
    }
    for (index, slot) in bins.iter_mut().enumerate() {
        if counts[index] > 0 {
            slot.rms = (sums[index] / f64::from(counts[index])).sqrt() as f32;
        }
    }
    bins
}
