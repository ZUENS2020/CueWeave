use crate::{MediaFingerprint, MetadataValues, SongProject, SourceInfo, TargetAudio};
use aes::Aes128;
use aes::cipher::{BlockDecrypt, KeyInit, generic_array::GenericArray};
use base64::Engine;
use id3::{Error as Id3Error, ErrorKind as Id3ErrorKind, Tag, TagLike};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::Duration;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, TrackType};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use thiserror::Error;

const NCM_MAGIC: &[u8; 8] = b"CTENFDAM";
const META_KEY: [u8; 16] = [
    0x23, 0x31, 0x34, 0x6c, 0x6a, 0x6b, 0x5f, 0x21, 0x5c, 0x5d, 0x26, 0x30, 0x55, 0x3c, 0x27, 0x28,
];
const MAX_KEY_BYTES: u32 = 1_048_576;
const MAX_METADATA_BYTES: u32 = 2_097_152;
const MAX_COVER_BYTES: u32 = 20_971_520;

#[derive(Debug, Error)]
pub enum SourceError {
    #[error("source I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid source: {0}")]
    Invalid(String),
    #[error("source metadata JSON failed: {0}")]
    Json(#[from] serde_json::Error),
    #[error("MP3 metadata failed: {0}")]
    Id3(#[from] Id3Error),
}

#[derive(Clone, Debug, PartialEq)]
pub struct NcmInfo {
    pub music_id: Option<u64>,
    pub metadata: MetadataValues,
    pub cover_url: Option<String>,
    pub format: Option<String>,
    pub duration_ms: Option<u64>,
    pub cover: Option<CoverImage>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CoverImage {
    pub mime_type: String,
    pub data: Vec<u8>,
}

pub fn inspect_ncm(path: impl AsRef<Path>) -> Result<NcmInfo, SourceError> {
    let mut file = File::open(path)?;
    let mut magic = [0_u8; 8];
    file.read_exact(&mut magic)?;
    if &magic != NCM_MAGIC {
        return invalid("NCM magic does not match");
    }
    file.seek(SeekFrom::Current(2))?;

    let key_length = read_u32(&mut file)?;
    if key_length > MAX_KEY_BYTES {
        return invalid("key section is too large");
    }
    file.seek(SeekFrom::Current(i64::from(key_length)))?;

    let metadata_length = read_u32(&mut file)?;
    if metadata_length == 0 || metadata_length > MAX_METADATA_BYTES {
        return invalid("metadata section has an invalid size");
    }
    let mut encrypted_metadata = vec![0; metadata_length as usize];
    file.read_exact(&mut encrypted_metadata)?;
    let metadata = decrypt_metadata(encrypted_metadata)?;

    file.seek(SeekFrom::Current(9))?;
    let cover_length = read_u32(&mut file)?;
    if cover_length > MAX_COVER_BYTES {
        return invalid("cover section is too large");
    }
    let cover = if cover_length == 0 {
        None
    } else {
        let mut data = vec![0; cover_length as usize];
        file.read_exact(&mut data)?;
        Some(CoverImage {
            mime_type: image_mime(&data)?.to_owned(),
            data,
        })
    };

    metadata_to_info(&metadata, cover)
}

pub fn download_cover(url: &str) -> Result<CoverImage, SourceError> {
    let url = if let Some(rest) = url.strip_prefix("http://") {
        format!("https://{rest}")
    } else {
        url.to_owned()
    };
    let parsed = reqwest::Url::parse(&url)
        .map_err(|error| SourceError::Invalid(format!("cover URL failed: {error}")))?;
    let host = parsed.host_str().unwrap_or_default();
    if parsed.scheme() != "https"
        || !(host == "music.126.net"
            || host.ends_with(".music.126.net")
            || host == "music.163.com"
            || host.ends_with(".music.163.com"))
    {
        return invalid("cover URL is outside the NetEase HTTPS domains");
    }
    let response = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("CueWeave/0.1")
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|error| SourceError::Invalid(format!("cover client failed: {error}")))?
        .get(url)
        .send()
        .map_err(|error| SourceError::Invalid(format!("cover request failed: {error}")))?;
    if !response.status().is_success() {
        return invalid(format!("cover returned HTTP {}", response.status()));
    }
    if response
        .content_length()
        .is_some_and(|length| length > u64::from(MAX_COVER_BYTES))
    {
        return invalid("cover response is too large");
    }
    let data = response
        .bytes()
        .map_err(|error| SourceError::Invalid(format!("cover body failed: {error}")))?
        .to_vec();
    if data.len() > MAX_COVER_BYTES as usize {
        return invalid("cover response is too large");
    }
    Ok(CoverImage {
        mime_type: image_mime(&data)?.to_owned(),
        data,
    })
}

pub fn replace_target_audio(
    project: &mut SongProject,
    target_path: impl AsRef<Path>,
) -> Result<(), SourceError> {
    let target_path = target_path.as_ref();
    project.metadata.target = read_mp3_metadata(target_path)?;
    project.target = Some(TargetAudio {
        path: target_path.to_owned(),
        fingerprint: Some(media_fingerprint(target_path, true)?),
        duration_ms: read_mp3_duration(target_path)?,
    });
    for segment in project
        .lyrics
        .lines
        .iter_mut()
        .flat_map(|line| &mut line.segments)
    {
        segment.timing = crate::SegmentTiming::default();
    }
    Ok(())
}

pub fn read_mp3_metadata(path: impl AsRef<Path>) -> Result<MetadataValues, SourceError> {
    let tag = read_tag(path)?;
    Ok(metadata_from_tag(&tag))
}

pub fn read_mp3_duration(path: impl AsRef<Path>) -> Result<Option<u64>, SourceError> {
    let stream = MediaSourceStream::new(Box::new(File::open(path)?), Default::default());
    let mut hint = Hint::new();
    hint.with_extension("mp3");
    let Ok(format) = symphonia::default::get_probe().probe(
        &hint,
        stream,
        FormatOptions::default(),
        MetadataOptions::default(),
    ) else {
        return Ok(None);
    };
    let Some(track) = format.default_track(TrackType::Audio) else {
        return Ok(None);
    };
    let Some(time) = track
        .time_base
        .zip(track.duration)
        .and_then(|(time_base, duration)| time_base.calc_duration(duration))
    else {
        return Ok(None);
    };
    u64::try_from(time.as_millis())
        .map(Some)
        .map_err(|_| SourceError::Invalid("MP3 duration is outside the supported range".into()))
}

fn read_tag(path: impl AsRef<Path>) -> Result<Tag, SourceError> {
    let tag = match Tag::read_from_path(path) {
        Ok(tag) => tag,
        Err(Id3Error {
            kind: Id3ErrorKind::NoTag,
            ..
        }) => Tag::new(),
        Err(error) => return Err(SourceError::Id3(error)),
    };
    Ok(tag)
}

fn metadata_from_tag(tag: &Tag) -> MetadataValues {
    MetadataValues {
        title: tag.title().map(str::to_owned),
        artists: tag
            .artist()
            .map(|artist| vec![artist.to_owned()])
            .unwrap_or_default(),
        album_artist: tag.album_artist().map(str::to_owned),
        album: tag.album().map(str::to_owned),
        track: tag.track(),
        disc: tag.disc(),
        date: tag.date_recorded().map(|date| date.to_string()),
        composer: tag
            .get("TCOM")
            .and_then(|frame| frame.content().text())
            .map(str::to_owned),
        lyricist: tag
            .get("TEXT")
            .and_then(|frame| frame.content().text())
            .map(str::to_owned),
        cover_path: None,
    }
}

pub fn project_from_files(
    source_path: impl AsRef<Path>,
    target_path: impl AsRef<Path>,
    cover_path: Option<PathBuf>,
) -> Result<(SongProject, NcmInfo), SourceError> {
    let source_path = source_path.as_ref();
    let target_path = target_path.as_ref();
    let info = inspect_ncm(source_path)?;
    let target_metadata = read_mp3_metadata(target_path)?;
    let mut source_metadata = info.metadata.clone();
    source_metadata.cover_path = cover_path;
    let draft = merge_metadata(&source_metadata, &target_metadata);
    let project = SongProject {
        source: Some(SourceInfo {
            path: source_path.to_owned(),
            fingerprint: Some(media_fingerprint(source_path, false)?),
            music_id: info.music_id,
            cover_url: info.cover_url.clone(),
            format: info.format.clone(),
            duration_ms: info.duration_ms,
        }),
        target: Some(TargetAudio {
            path: target_path.to_owned(),
            fingerprint: Some(media_fingerprint(target_path, true)?),
            duration_ms: read_mp3_duration(target_path)?,
        }),
        metadata: crate::MetadataSet {
            source: source_metadata,
            target: target_metadata,
            draft,
        },
        ..SongProject::default()
    };
    Ok((project, info))
}

fn media_fingerprint(path: &Path, audio_payload: bool) -> Result<MediaFingerprint, SourceError> {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| SourceError::Invalid("media file name is not valid UTF-8".into()))?
        .to_owned();
    let size_bytes = std::fs::metadata(path)?.len();
    let sha256 = if audio_payload {
        crate::audio_payload_sha256(path)
            .map_err(|error| SourceError::Invalid(format!("audio fingerprint failed: {error}")))?
    } else {
        let mut file = File::open(path)?;
        let mut buffer = [0_u8; 65_536];
        let mut hasher = Sha256::new();
        loop {
            let read = file.read(&mut buffer)?;
            if read == 0 {
                break;
            }
            hasher.update(&buffer[..read]);
        }
        format!("{:x}", hasher.finalize())
    };
    Ok(MediaFingerprint {
        file_name,
        size_bytes,
        sha256,
    })
}

fn merge_metadata(source: &MetadataValues, target: &MetadataValues) -> MetadataValues {
    MetadataValues {
        title: source.title.clone().or_else(|| target.title.clone()),
        artists: if source.artists.is_empty() {
            target.artists.clone()
        } else {
            source.artists.clone()
        },
        album_artist: source
            .album_artist
            .clone()
            .or_else(|| target.album_artist.clone()),
        album: source.album.clone().or_else(|| target.album.clone()),
        track: source.track.or(target.track),
        disc: source.disc.or(target.disc),
        date: source.date.clone().or_else(|| target.date.clone()),
        composer: source.composer.clone().or_else(|| target.composer.clone()),
        lyricist: source.lyricist.clone().or_else(|| target.lyricist.clone()),
        cover_path: source
            .cover_path
            .clone()
            .or_else(|| target.cover_path.clone()),
    }
}

fn decrypt_metadata(mut encrypted: Vec<u8>) -> Result<Value, SourceError> {
    for byte in &mut encrypted {
        *byte ^= 0x63;
    }
    let encoded = encrypted
        .strip_prefix(b"163 key(Don't modify):")
        .ok_or_else(|| SourceError::Invalid("metadata prefix is missing".into()))?;
    let mut decrypted = base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .map_err(|error| SourceError::Invalid(format!("metadata base64 failed: {error}")))?;
    if decrypted.is_empty() || decrypted.len() % 16 != 0 {
        return invalid("metadata ciphertext is not AES block aligned");
    }
    let cipher = Aes128::new_from_slice(&META_KEY)
        .map_err(|_| SourceError::Invalid("metadata key is invalid".into()))?;
    for block in decrypted.chunks_exact_mut(16) {
        cipher.decrypt_block(GenericArray::from_mut_slice(block));
    }
    remove_pkcs7(&mut decrypted)?;
    let json = decrypted
        .strip_prefix(b"music:")
        .ok_or_else(|| SourceError::Invalid("decrypted metadata prefix is missing".into()))?;
    Ok(serde_json::from_slice(json)?)
}

fn remove_pkcs7(bytes: &mut Vec<u8>) -> Result<(), SourceError> {
    let padding = usize::from(
        *bytes
            .last()
            .ok_or_else(|| SourceError::Invalid("metadata is empty".into()))?,
    );
    if padding == 0 || padding > 16 || padding > bytes.len() {
        return invalid("metadata has invalid PKCS#7 padding");
    }
    if !bytes[bytes.len() - padding..]
        .iter()
        .all(|byte| usize::from(*byte) == padding)
    {
        return invalid("metadata PKCS#7 padding does not match");
    }
    bytes.truncate(bytes.len() - padding);
    Ok(())
}

fn metadata_to_info(metadata: &Value, cover: Option<CoverImage>) -> Result<NcmInfo, SourceError> {
    let artists = metadata
        .get("artist")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|artist| artist.get(0).and_then(Value::as_str).map(str::to_owned))
        .collect();
    let title = string_field(metadata, "musicName");
    if title.is_none() {
        return invalid("musicName is missing");
    }
    Ok(NcmInfo {
        music_id: u64_field(metadata, "musicId"),
        metadata: MetadataValues {
            title,
            artists,
            album: string_field(metadata, "album"),
            album_artist: None,
            track: None,
            disc: None,
            date: None,
            composer: None,
            lyricist: None,
            cover_path: None,
        },
        cover_url: string_field(metadata, "albumPic"),
        format: string_field(metadata, "format"),
        duration_ms: u64_field(metadata, "duration"),
        cover,
    })
}

fn string_field(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(str::to_owned)
}

fn u64_field(value: &Value, key: &str) -> Option<u64> {
    value
        .get(key)
        .and_then(|item| item.as_u64().or_else(|| item.as_str()?.parse().ok()))
}

fn read_u32(reader: &mut impl Read) -> Result<u32, SourceError> {
    let mut bytes = [0_u8; 4];
    reader.read_exact(&mut bytes)?;
    Ok(u32::from_le_bytes(bytes))
}

fn image_mime(data: &[u8]) -> Result<&'static str, SourceError> {
    if data.starts_with(b"\x89PNG\r\n\x1a\n") {
        Ok("image/png")
    } else if data.starts_with(b"\xff\xd8\xff") {
        Ok("image/jpeg")
    } else {
        invalid("cover is neither PNG nor JPEG")
    }
}

fn invalid<T>(message: impl Into<String>) -> Result<T, SourceError> {
    Err(SourceError::Invalid(message.into()))
}
