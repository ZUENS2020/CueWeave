use super::{AudioVizError, PcmAudio};
use std::fs::File;
use std::path::Path;
use symphonia::core::codecs::audio::AudioDecoderOptions;
use symphonia::core::errors::Error;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, TrackType};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;

pub fn decode_mono_pcm(path: impl AsRef<Path>) -> Result<PcmAudio, AudioVizError> {
    let path = path.as_ref();
    let stream = MediaSourceStream::new(Box::new(File::open(path)?), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|ext| ext.to_str()) {
        hint.with_extension(ext);
    }
    let mut format = symphonia::default::get_probe()
        .probe(
            &hint,
            stream,
            FormatOptions::default(),
            MetadataOptions::default(),
        )
        .map_err(|error| AudioVizError::Decode(error.to_string()))?;
    let (track_id, params) = {
        let track = format
            .default_track(TrackType::Audio)
            .ok_or_else(|| AudioVizError::Decode("no audio track".into()))?;
        let params = track
            .codec_params
            .as_ref()
            .and_then(|params| params.audio())
            .cloned()
            .ok_or_else(|| AudioVizError::Decode("audio codec parameters missing".into()))?;
        (track.id, params)
    };
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(&params, &AudioDecoderOptions::default())
        .map_err(|error| AudioVizError::Decode(error.to_string()))?;
    let mut samples = Vec::new();
    let mut sample_rate = 0;
    loop {
        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,
            Ok(None) => break,
            Err(Error::ResetRequired) => break,
            Err(Error::IoError(error)) if error.kind() == std::io::ErrorKind::UnexpectedEof => {
                break;
            }
            Err(Error::DecodeError(_)) | Err(Error::IoError(_)) => continue,
            Err(error) => return Err(AudioVizError::Decode(error.to_string())),
        };
        if packet.track_id != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(Error::DecodeError(_) | Error::IoError(_)) => continue,
            Err(error) => return Err(AudioVizError::Decode(error.to_string())),
        };
        sample_rate = decoded.spec().rate();
        let channels = decoded.spec().channels().count().max(1);
        let mut interleaved = vec![0.0; decoded.samples_interleaved()];
        decoded.copy_to_slice_interleaved(&mut interleaved);
        for frame in interleaved.chunks(channels) {
            let sum: f32 = frame.iter().copied().sum();
            samples.push(sum / channels as f32);
        }
    }
    if sample_rate == 0 || samples.is_empty() {
        return Err(AudioVizError::Decode("decoded audio is empty".into()));
    }
    Ok(PcmAudio {
        sample_rate,
        samples,
    })
}
