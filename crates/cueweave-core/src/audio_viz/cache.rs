use super::{
    AudioVizError, FrequencyScale, PcmAudio, SpectrogramTile, VISUALIZATION_VERSION, WaveformBin,
};
use std::fs;
use std::path::{Path, PathBuf};

const PCM_MAGIC: &[u8; 4] = b"CWAV";
const WAVE_MAGIC: &[u8; 4] = b"CWWV";
const SPEC_MAGIC: &[u8; 4] = b"CWSP";
const FORMAT: u32 = 1;

pub fn pcm(
    cache_dir: &Path,
    digest: &str,
    build: impl FnOnce() -> Result<PcmAudio, AudioVizError>,
) -> Result<PcmAudio, AudioVizError> {
    let path = root(cache_dir, digest).join("pcm.bin");
    if let Some(loaded) = read_pcm(&path)? {
        return Ok(loaded);
    }
    let pcm = build()?;
    write_pcm(&path, &pcm)?;
    Ok(pcm)
}

pub fn waveform(
    cache_dir: &Path,
    digest: &str,
    bin_count: usize,
    build: impl FnOnce() -> Result<Vec<WaveformBin>, AudioVizError>,
) -> Result<Vec<WaveformBin>, AudioVizError> {
    let path = root(cache_dir, digest).join(format!("wave-{bin_count}.bin"));
    if let Some(loaded) = read_waveform(&path, bin_count)? {
        return Ok(loaded);
    }
    let bins = build()?;
    write_waveform(&path, &bins)?;
    Ok(bins)
}

pub fn spectrogram(
    cache_dir: &Path,
    digest: &str,
    start_ms: u64,
    end_ms: u64,
    scale: FrequencyScale,
    frequency_bins: u32,
    build: impl FnOnce() -> Result<SpectrogramTile, AudioVizError>,
) -> Result<SpectrogramTile, AudioVizError> {
    let name = format!(
        "spec-{}-{}-{}-{frequency_bins}.bin",
        start_ms,
        end_ms,
        scale_name(scale)
    );
    let path = root(cache_dir, digest).join(name);
    if let Some(loaded) = read_spectrogram(&path)? {
        return Ok(loaded);
    }
    let tile = build()?;
    write_spectrogram(&path, &tile)?;
    Ok(tile)
}

fn root(cache_dir: &Path, digest: &str) -> PathBuf {
    cache_dir.join(digest).join(VISUALIZATION_VERSION)
}

fn read_pcm(path: &Path) -> Result<Option<PcmAudio>, AudioVizError> {
    let Some(bytes) = read_if_present(path)? else {
        return Ok(None);
    };
    if bytes.len() < 20 || &bytes[0..4] != PCM_MAGIC {
        return Ok(None);
    }
    let version = u32::from_le_bytes(bytes[4..8].try_into().unwrap());
    if version != FORMAT {
        return Ok(None);
    }
    let sample_rate = u32::from_le_bytes(bytes[8..12].try_into().unwrap());
    let count = u64::from_le_bytes(bytes[12..20].try_into().unwrap()) as usize;
    let expected = 20 + count * 4;
    if bytes.len() != expected {
        return Ok(None);
    }
    let mut samples = Vec::with_capacity(count);
    for chunk in bytes[20..].chunks_exact(4) {
        samples.push(f32::from_le_bytes(chunk.try_into().unwrap()));
    }
    Ok(Some(PcmAudio {
        sample_rate,
        samples,
    }))
}

fn write_pcm(path: &Path, pcm: &PcmAudio) -> Result<(), AudioVizError> {
    let mut bytes = Vec::with_capacity(20 + pcm.samples.len() * 4);
    bytes.extend_from_slice(PCM_MAGIC);
    bytes.extend_from_slice(&FORMAT.to_le_bytes());
    bytes.extend_from_slice(&pcm.sample_rate.to_le_bytes());
    bytes.extend_from_slice(&(pcm.samples.len() as u64).to_le_bytes());
    for sample in &pcm.samples {
        bytes.extend_from_slice(&sample.to_le_bytes());
    }
    write_atomic(path, &bytes)
}

fn read_waveform(path: &Path, bin_count: usize) -> Result<Option<Vec<WaveformBin>>, AudioVizError> {
    let Some(bytes) = read_if_present(path)? else {
        return Ok(None);
    };
    if bytes.len() < 8 || &bytes[0..4] != WAVE_MAGIC {
        return Ok(None);
    }
    let count = u32::from_le_bytes(bytes[4..8].try_into().unwrap()) as usize;
    if count != bin_count || bytes.len() != 8 + count * 12 {
        return Ok(None);
    }
    let mut bins = Vec::with_capacity(count);
    for chunk in bytes[8..].chunks_exact(12) {
        bins.push(WaveformBin {
            peak_min: f32::from_le_bytes(chunk[0..4].try_into().unwrap()),
            peak_max: f32::from_le_bytes(chunk[4..8].try_into().unwrap()),
            rms: f32::from_le_bytes(chunk[8..12].try_into().unwrap()),
        });
    }
    Ok(Some(bins))
}

fn write_waveform(path: &Path, bins: &[WaveformBin]) -> Result<(), AudioVizError> {
    let mut bytes = Vec::with_capacity(8 + bins.len() * 12);
    bytes.extend_from_slice(WAVE_MAGIC);
    bytes.extend_from_slice(&(bins.len() as u32).to_le_bytes());
    for bin in bins {
        bytes.extend_from_slice(&bin.peak_min.to_le_bytes());
        bytes.extend_from_slice(&bin.peak_max.to_le_bytes());
        bytes.extend_from_slice(&bin.rms.to_le_bytes());
    }
    write_atomic(path, &bytes)
}

fn read_spectrogram(path: &Path) -> Result<Option<SpectrogramTile>, AudioVizError> {
    let Some(bytes) = read_if_present(path)? else {
        return Ok(None);
    };
    if bytes.len() < 32 || &bytes[0..4] != SPEC_MAGIC {
        return Ok(None);
    }
    let start_ms = u64::from_le_bytes(bytes[4..12].try_into().unwrap());
    let end_ms = u64::from_le_bytes(bytes[12..20].try_into().unwrap());
    let time_bins = u32::from_le_bytes(bytes[20..24].try_into().unwrap());
    let frequency_bins = u32::from_le_bytes(bytes[24..28].try_into().unwrap());
    let count = u32::from_le_bytes(bytes[28..32].try_into().unwrap()) as usize;
    if bytes.len() != 32 + count {
        return Ok(None);
    }
    Ok(Some(SpectrogramTile {
        start_ms,
        end_ms,
        time_bins,
        frequency_bins,
        values: bytes[32..].to_vec(),
    }))
}

fn write_spectrogram(path: &Path, tile: &SpectrogramTile) -> Result<(), AudioVizError> {
    let mut bytes = Vec::with_capacity(32 + tile.values.len());
    bytes.extend_from_slice(SPEC_MAGIC);
    bytes.extend_from_slice(&tile.start_ms.to_le_bytes());
    bytes.extend_from_slice(&tile.end_ms.to_le_bytes());
    bytes.extend_from_slice(&tile.time_bins.to_le_bytes());
    bytes.extend_from_slice(&tile.frequency_bins.to_le_bytes());
    bytes.extend_from_slice(&(tile.values.len() as u32).to_le_bytes());
    bytes.extend_from_slice(&tile.values);
    write_atomic(path, &bytes)
}

fn read_if_present(path: &Path) -> Result<Option<Vec<u8>>, AudioVizError> {
    match fs::read(path) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), AudioVizError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, bytes)?;
    Ok(())
}

fn scale_name(scale: FrequencyScale) -> &'static str {
    match scale {
        FrequencyScale::Linear => "linear",
        FrequencyScale::Log => "log",
        FrequencyScale::Mel => "mel",
    }
}

#[cfg(test)]
mod tests {
    use crate::audio_viz::PcmAudio;

    #[test]
    fn pcm_cache_skips_rebuild() {
        let dir = tempfile::tempdir().unwrap();
        let pcm = PcmAudio {
            sample_rate: 8_000,
            samples: vec![0.25, -0.5, 0.75],
        };
        let first = super::pcm(dir.path(), "digest", || Ok(pcm.clone())).unwrap();
        let second = super::pcm(dir.path(), "digest", || panic!("rebuilt")).unwrap();
        assert_eq!(first, second);
        assert_eq!(second.samples, vec![0.25, -0.5, 0.75]);
    }
}
