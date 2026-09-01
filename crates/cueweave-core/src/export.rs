use crate::{
    ExportAdapterKind, ExportFormat, MetadataValues, PlayerExportAdapter, SongProject,
    build_export_cue_sheet, builtin_player_adapter,
};
use id3::frame::{Picture, PictureType};
use id3::{Error as Id3Error, ErrorKind as Id3ErrorKind, Tag, TagLike, Version};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use tempfile::NamedTempFile;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ExportError {
    #[error("invalid export: {0}")]
    Invalid(String),
    #[error("export I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("ID3 export failed: {0}")]
    Id3(#[from] Id3Error),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ExportResult {
    pub mp3_path: PathBuf,
    pub lrc_path: Option<PathBuf>,
    pub audio_sha256: String,
}

pub fn render_lrc(project: &SongProject) -> Result<String, ExportError> {
    let bytes = crate::LrcAdapter.write_sidecar(&build_export_cue_sheet(project)?)?;
    String::from_utf8(bytes).map_err(|error| ExportError::Invalid(error.to_string()))
}

pub fn export_mp3(
    project: &SongProject,
    output: impl AsRef<Path>,
    overwrite: bool,
) -> Result<ExportResult, ExportError> {
    project
        .validate()
        .map_err(|error| ExportError::Invalid(error.to_string()))?;
    let target = project
        .target
        .as_ref()
        .ok_or_else(|| ExportError::Invalid("target audio is missing".into()))?;
    let output = output.as_ref();
    if output == target.path {
        return invalid("output must not overwrite the target audio");
    }
    if output.exists() && !overwrite {
        return invalid("output already exists");
    }
    let directory = output
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let temporary = NamedTempFile::new_in(directory)?;
    let lrc_output = output.with_extension("lrc");
    fs::copy(&target.path, temporary.path())?;

    let mut tag = match Tag::read_from_path(temporary.path()) {
        Ok(tag) => tag,
        Err(Id3Error {
            kind: Id3ErrorKind::NoTag,
            ..
        }) => Tag::new(),
        Err(error) => return Err(ExportError::Id3(error)),
    };
    apply_metadata(&mut tag, &project.metadata.draft)?;
    let sheet = build_export_cue_sheet(project)?;
    apply_player_tags(&mut tag, project, &sheet)?;
    tag.write_to_path(temporary.path(), Version::Id3v24)?;

    let source_hash = audio_payload_sha256(&target.path)?;
    let output_hash = audio_payload_sha256(temporary.path())?;
    if source_hash != output_hash {
        return invalid("MPEG audio payload changed while writing tags");
    }

    let mut lrc_temporary = if project.export.formats.contains(&ExportFormat::Lrc) {
        if lrc_output.exists() && !overwrite {
            return invalid("LRC output already exists");
        }
        let mut file = NamedTempFile::new_in(directory)?;
        file.write_all(&crate::LrcAdapter.write_sidecar(&sheet)?)?;
        file.as_file().sync_all()?;
        Some(file)
    } else {
        None
    };
    temporary.as_file().sync_all()?;
    persist_output(temporary, output, overwrite)?;
    if let Some(file) = lrc_temporary.take()
        && let Err(error) = persist_output(file, &lrc_output, overwrite)
    {
        let _ = fs::remove_file(output);
        return Err(error);
    }
    Ok(ExportResult {
        mp3_path: output.to_owned(),
        lrc_path: project
            .export
            .formats
            .contains(&ExportFormat::Lrc)
            .then_some(lrc_output),
        audio_sha256: output_hash,
    })
}

pub fn audio_payload_sha256(path: impl AsRef<Path>) -> Result<String, ExportError> {
    let mut file = File::open(path)?;
    Tag::skip(&mut file)?;
    let start = file.stream_position()?;
    let file_length = file.seek(SeekFrom::End(0))?;
    let end = if file_length >= 128 {
        file.seek(SeekFrom::End(-128))?;
        let mut marker = [0_u8; 3];
        file.read_exact(&mut marker)?;
        if &marker == b"TAG" {
            file_length - 128
        } else {
            file_length
        }
    } else {
        file_length
    };
    if start >= end {
        return invalid("MP3 has no audio payload");
    }
    file.seek(SeekFrom::Start(start))?;
    let mut remaining = end - start;
    let mut buffer = [0_u8; 65_536];
    let mut hasher = Sha256::new();
    while remaining > 0 {
        let chunk = buffer.len().min(remaining as usize);
        let read = file.read(&mut buffer[..chunk])?;
        if read == 0 {
            return invalid("MP3 audio payload ended unexpectedly");
        }
        hasher.update(&buffer[..read]);
        remaining -= read as u64;
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn apply_metadata(tag: &mut Tag, metadata: &MetadataValues) -> Result<(), ExportError> {
    set_optional_text(tag, "TIT2", metadata.title.as_deref());
    tag.remove("TPE1");
    if !metadata.artists.is_empty() {
        tag.set_artist(metadata.artists.join(" / "));
    }
    set_optional_text(tag, "TPE2", metadata.album_artist.as_deref());
    set_optional_text(tag, "TALB", metadata.album.as_deref());
    set_optional_text(tag, "TDRC", metadata.date.as_deref());
    set_optional_text(tag, "TCOM", metadata.composer.as_deref());
    set_optional_text(tag, "TEXT", metadata.lyricist.as_deref());
    tag.remove("TRCK");
    if let Some(track) = metadata.track {
        tag.set_track(track);
    }
    tag.remove("TPOS");
    if let Some(disc) = metadata.disc {
        tag.set_disc(disc);
    }
    if let Some(path) = &metadata.cover_path {
        let data = fs::read(path)?;
        let mime_type = if data.starts_with(b"\x89PNG\r\n\x1a\n") {
            "image/png"
        } else if data.starts_with(b"\xff\xd8\xff") {
            "image/jpeg"
        } else {
            return invalid("cover is neither PNG nor JPEG");
        };
        tag.remove_all_pictures();
        tag.add_frame(Picture {
            mime_type: mime_type.into(),
            picture_type: PictureType::CoverFront,
            description: String::new(),
            data,
        });
    }
    Ok(())
}

fn apply_player_tags(
    tag: &mut Tag,
    project: &SongProject,
    sheet: &crate::ExportCueSheet,
) -> Result<(), ExportError> {
    tag.remove("USLT");
    tag.remove("SYLT");
    for format in &project.export.formats {
        let Some(adapter) = builtin_player_adapter(format.adapter_id()) else {
            continue;
        };
        if adapter.info().kind != ExportAdapterKind::EmbeddedTag {
            continue;
        }
        adapter.embed(tag, sheet)?;
    }
    Ok(())
}

fn set_optional_text(tag: &mut Tag, id: &str, value: Option<&str>) {
    tag.remove(id);
    if let Some(value) = value.filter(|value| !value.trim().is_empty()) {
        tag.set_text(id, value);
    }
}

fn persist_output(file: NamedTempFile, dest: &Path, overwrite: bool) -> Result<(), ExportError> {
    let result = if overwrite {
        file.persist(dest)
    } else {
        file.persist_noclobber(dest)
    };
    result
        .map(|_| ())
        .map_err(|error| ExportError::Io(error.error))
}

fn invalid<T>(message: impl Into<String>) -> Result<T, ExportError> {
    Err(ExportError::Invalid(message.into()))
}
