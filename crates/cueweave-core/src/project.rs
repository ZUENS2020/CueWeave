use crate::{
    AlignmentPoint, CURRENT_SCHEMA_VERSION, Cue, LineId, LyricLine, LyricSegment, SegmentId,
    SegmentTiming, SongProject,
};
use std::collections::HashSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use tempfile::NamedTempFile;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ProjectError {
    #[error("project I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("project JSON failed: {0}")]
    Json(#[from] serde_json::Error),
    #[error("unsupported project schema version {0}")]
    UnsupportedSchema(u32),
    #[error("invalid project: {0}")]
    Invariant(String),
    #[error("{0} {1} was not found")]
    NotFound(&'static str, u64),
}

impl SongProject {
    pub fn from_json(json: &str) -> Result<Self, ProjectError> {
        let mut value: serde_json::Value = serde_json::from_str(json)?;
        crate::migrate::migrate_project_value(&mut value)?;
        let mut project: Self = serde_json::from_value(value)?;
        crate::assign_credit_ids(&mut project.lyrics.credits)?;
        crate::sync_credit_cues(&mut project);
        crate::sort_credit_cues(&mut project);
        project.validate()?;
        Ok(project)
    }

    pub fn to_json_pretty(&self) -> Result<String, ProjectError> {
        self.validate()?;
        Ok(serde_json::to_string_pretty(self)?)
    }

    pub fn load(path: impl AsRef<Path>) -> Result<Self, ProjectError> {
        let path = path.as_ref();
        let mut project = Self::from_json(&fs::read_to_string(path)?)?;
        project.resolve_paths(project_directory(path));
        Ok(project)
    }

    pub fn save(&self, path: impl AsRef<Path>) -> Result<(), ProjectError> {
        let path = path.as_ref();
        let directory = project_directory(path);
        let mut portable = self.clone();
        portable.make_paths_relative(directory);
        let mut temporary = NamedTempFile::new_in(directory)?;
        temporary.write_all(portable.to_json_pretty()?.as_bytes())?;
        temporary.as_file().sync_all()?;
        temporary
            .persist(path)
            .map_err(|error| ProjectError::Io(error.error))?;
        Ok(())
    }

    fn resolve_paths(&mut self, directory: &Path) {
        if let Some(source) = &mut self.source {
            resolve_path(&mut source.path, directory);
        }
        if let Some(target) = &mut self.target {
            resolve_path(&mut target.path, directory);
        }
        for metadata in [
            &mut self.metadata.source,
            &mut self.metadata.target,
            &mut self.metadata.draft,
        ] {
            if let Some(path) = &mut metadata.cover_path {
                resolve_path(path, directory);
            }
        }
    }

    fn make_paths_relative(&mut self, directory: &Path) {
        if let Some(source) = &mut self.source {
            make_path_relative(&mut source.path, directory);
        }
        if let Some(target) = &mut self.target {
            make_path_relative(&mut target.path, directory);
        }
        for metadata in [
            &mut self.metadata.source,
            &mut self.metadata.target,
            &mut self.metadata.draft,
        ] {
            if let Some(path) = &mut metadata.cover_path {
                make_path_relative(path, directory);
            }
        }
    }

    pub fn validate(&self) -> Result<(), ProjectError> {
        if self.schema_version != CURRENT_SCHEMA_VERSION {
            return Err(ProjectError::UnsupportedSchema(self.schema_version));
        }

        let mut line_ids = HashSet::new();
        let mut segment_ids = HashSet::new();
        let mut credit_ids = HashSet::new();
        let mut previous_final = None;
        let duration_ms = self.target.as_ref().and_then(|target| target.duration_ms);

        for credit in &self.lyrics.credits {
            if credit.id.0 == 0 || !credit_ids.insert(credit.id) {
                return invariant(format!("duplicate credit id {}", credit.id.0));
            }
        }

        for line in &self.lyrics.lines {
            if !line_ids.insert(line.id) {
                return invariant(format!("duplicate line id {}", line.id.0));
            }
            if line.original.trim().is_empty() {
                return invariant(format!("line {} has empty text", line.id.0));
            }
            for segment in &line.segments {
                if !segment_ids.insert(segment.id) {
                    return invariant(format!("duplicate segment id {}", segment.id.0));
                }
                if segment.text.trim().is_empty() {
                    return invariant(format!("segment {} has empty text", segment.id.0));
                }
                validate_timing(segment, duration_ms, &mut previous_final)?;
            }
        }

        for cue in &self.timeline {
            match cue {
                Cue::Lyric { line_id } if !line_ids.contains(line_id) => {
                    return invariant(format!("cue references missing line {}", line_id.0));
                }
                Cue::Credit { credit_id, time_ms } => {
                    if !credit_ids.contains(credit_id) {
                        return invariant(format!("cue references missing credit {}", credit_id.0));
                    }
                    if duration_ms.is_some_and(|duration| *time_ms > duration) {
                        return invariant(format!(
                            "credit {} is past target duration",
                            credit_id.0
                        ));
                    }
                }
                _ => {}
            }
        }

        Ok(())
    }

    pub fn add_line(
        &mut self,
        original: impl Into<String>,
        segments: impl IntoIterator<Item = String>,
    ) -> Result<LineId, ProjectError> {
        self.insert_line_at(self.lyrics.lines.len(), original, segments)
    }

    pub fn insert_line_at(
        &mut self,
        index: usize,
        original: impl Into<String>,
        segments: impl IntoIterator<Item = String>,
    ) -> Result<LineId, ProjectError> {
        let original = original.into();
        let segment_texts: Vec<_> = segments.into_iter().collect();
        if original.trim().is_empty() || segment_texts.is_empty() {
            return invariant("a lyric line requires text and at least one segment");
        }
        if index > self.lyrics.lines.len() {
            return invariant("lyric insert index is out of range");
        }

        let line_id = LineId(next_id(self.lyrics.lines.iter().map(|line| line.id.0))?);
        let mut next_segment = next_id(
            self.lyrics
                .lines
                .iter()
                .flat_map(|line| line.segments.iter().map(|segment| segment.id.0)),
        )?;
        let mut new_segments = Vec::with_capacity(segment_texts.len());
        for text in segment_texts {
            if text.trim().is_empty() {
                return invariant("a lyric segment cannot be empty");
            }
            new_segments.push(LyricSegment {
                id: SegmentId(next_segment),
                text,
                timing: SegmentTiming::default(),
            });
            next_segment = next_segment
                .checked_add(1)
                .ok_or_else(|| ProjectError::Invariant("segment id space exhausted".into()))?;
        }
        let after_id = index
            .checked_sub(1)
            .and_then(|previous| self.lyrics.lines.get(previous).map(|line| line.id));
        self.lyrics.lines.insert(
            index,
            LyricLine {
                id: line_id,
                original,
                translation: None,
                segments: new_segments,
            },
        );
        let insert_at = match after_id {
            None => self
                .timeline
                .iter()
                .position(|cue| matches!(cue, Cue::Lyric { .. }))
                .unwrap_or(self.timeline.len()),
            Some(id) => self
                .timeline
                .iter()
                .position(|cue| matches!(cue, Cue::Lyric { line_id } if *line_id == id))
                .map_or(self.timeline.len(), |position| position + 1),
        };
        self.timeline.insert(insert_at, Cue::Lyric { line_id });
        Ok(line_id)
    }

    pub fn set_user_final(
        &mut self,
        segment_id: SegmentId,
        time_ms: u64,
    ) -> Result<(), ProjectError> {
        let segment = self.segment_mut(segment_id)?;
        segment.timing.final_point = Some(AlignmentPoint {
            time_ms,
            confidence: None,
        });
        Ok(())
    }

    pub fn clear_user_final(&mut self, segment_id: SegmentId) -> Result<(), ProjectError> {
        self.segment_mut(segment_id)?.timing.final_point = None;
        Ok(())
    }

    pub fn apply_gemini_suggestion(
        &mut self,
        segment_id: SegmentId,
        point: AlignmentPoint,
    ) -> Result<bool, ProjectError> {
        let segment = self.segment_mut(segment_id)?;
        segment.timing.gemini = Some(point);
        if segment.timing.final_point.is_some() {
            return Ok(false);
        }
        segment.timing.final_point = Some(point);
        Ok(true)
    }

    pub fn restore_gemini_timeline(&mut self) {
        for segment in self
            .lyrics
            .lines
            .iter_mut()
            .flat_map(|line| &mut line.segments)
        {
            segment.timing.final_point = segment.timing.gemini;
        }
    }

    fn segment_mut(&mut self, id: SegmentId) -> Result<&mut LyricSegment, ProjectError> {
        self.lyrics
            .lines
            .iter_mut()
            .flat_map(|line| &mut line.segments)
            .find(|segment| segment.id == id)
            .ok_or(ProjectError::NotFound("segment", id.0))
    }
}

fn project_directory(path: &Path) -> &Path {
    path.parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."))
}

fn resolve_path(path: &mut PathBuf, directory: &Path) {
    let text = path.to_string_lossy();
    let foreign_absolute =
        text.starts_with('/') || text.as_bytes().get(1) == Some(&b':') || text.starts_with("\\\\");
    if path.is_relative() && !foreign_absolute {
        *path = directory.join(&*path);
    }
}

fn make_path_relative(path: &mut PathBuf, directory: &Path) {
    if let Ok(relative) = path.strip_prefix(directory) {
        *path = relative.to_owned();
    }
}

fn validate_timing(
    segment: &LyricSegment,
    duration_ms: Option<u64>,
    previous_final: &mut Option<u64>,
) -> Result<(), ProjectError> {
    for point in [segment.timing.gemini, segment.timing.final_point]
        .into_iter()
        .flatten()
    {
        if let Some(confidence) = point.confidence
            && (!confidence.is_finite() || !(0.0..=1.0).contains(&confidence))
        {
            return invariant(format!("segment {} has invalid confidence", segment.id.0));
        }
        if duration_ms.is_some_and(|duration| point.time_ms > duration) {
            return invariant(format!("segment {} is past target duration", segment.id.0));
        }
    }

    if let Some(point) = segment.timing.final_point {
        if previous_final.is_some_and(|previous| point.time_ms < previous) {
            return invariant(format!("segment {} is out of order", segment.id.0));
        }
        *previous_final = Some(point.time_ms);
    }
    Ok(())
}

fn next_id(ids: impl Iterator<Item = u64>) -> Result<u64, ProjectError> {
    ids.max()
        .unwrap_or(0)
        .checked_add(1)
        .ok_or_else(|| ProjectError::Invariant("id space exhausted".into()))
}

fn invariant<T>(message: impl Into<String>) -> Result<T, ProjectError> {
    Err(ProjectError::Invariant(message.into()))
}
