use crate::{
    AlignmentPoint, CURRENT_SCHEMA_VERSION, Cue, LineId, LyricLine, LyricSegment, ProjectStatus,
    ReviewState, SegmentId, SegmentTiming, SongProject,
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
        let mut project: Self = serde_json::from_str(json)?;
        if project.schema_version == 1 {
            project.schema_version = CURRENT_SCHEMA_VERSION;
        }
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

    pub fn status(&self) -> ProjectStatus {
        let segments: Vec<_> = self
            .lyrics
            .lines
            .iter()
            .flat_map(|line| &line.segments)
            .collect();
        let metadata_ready = self
            .metadata
            .draft
            .title
            .as_ref()
            .is_some_and(|title| !title.trim().is_empty())
            && self
                .metadata
                .draft
                .artists
                .iter()
                .any(|artist| !artist.trim().is_empty());
        let lyrics_ready = !self.lyrics.lines.is_empty()
            && self.lyrics.lines.iter().all(|line| {
                !line.original.trim().is_empty()
                    && !line.segments.is_empty()
                    && line
                        .segments
                        .iter()
                        .all(|segment| !segment.text.trim().is_empty())
            });
        let alignment_ready = !segments.is_empty()
            && segments.iter().all(|segment| {
                segment.timing.final_point.is_some()
                    || segment.timing.review == ReviewState::Ignored
            });
        let review_count = segments
            .iter()
            .filter(|segment| {
                matches!(
                    segment.timing.review,
                    ReviewState::Pending | ReviewState::NeedsReview | ReviewState::Unmatched
                )
            })
            .count();
        let target_has_duration = self
            .target
            .as_ref()
            .and_then(|target| target.duration_ms)
            .is_some_and(|duration| duration > 0);

        ProjectStatus {
            source_loaded: self.source.is_some(),
            target_loaded: self.target.is_some(),
            metadata_ready,
            lyrics_ready,
            alignment_ready,
            review_count,
            export_ready: target_has_duration && metadata_ready && lyrics_ready && alignment_ready,
        }
    }

    pub fn validate(&self) -> Result<(), ProjectError> {
        if self.schema_version != CURRENT_SCHEMA_VERSION {
            return Err(ProjectError::UnsupportedSchema(self.schema_version));
        }

        let mut line_ids = HashSet::new();
        let mut segment_ids = HashSet::new();
        let mut previous_final = None;
        let duration_ms = self.target.as_ref().and_then(|target| target.duration_ms);

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
            if let Cue::Lyric { line_id } = cue
                && !line_ids.contains(line_id)
            {
                return invariant(format!("cue references missing line {}", line_id.0));
            }
        }

        Ok(())
    }

    pub fn add_line(
        &mut self,
        original: impl Into<String>,
        segments: impl IntoIterator<Item = String>,
    ) -> Result<LineId, ProjectError> {
        let original = original.into();
        let segment_texts: Vec<_> = segments.into_iter().collect();
        if original.trim().is_empty() || segment_texts.is_empty() {
            return invariant("a lyric line requires text and at least one segment");
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
        self.lyrics.lines.push(LyricLine {
            id: line_id,
            original,
            translation: None,
            segments: new_segments,
        });
        self.timeline.push(Cue::Lyric { line_id });
        Ok(line_id)
    }

    pub fn split_segment(
        &mut self,
        segment_id: SegmentId,
        byte_index: usize,
    ) -> Result<SegmentId, ProjectError> {
        let new_id = SegmentId(next_id(self.segment_ids())?);
        let (line_index, segment_index) = self.segment_position(segment_id)?;
        let segment = &self.lyrics.lines[line_index].segments[segment_index];
        if !segment.text.is_char_boundary(byte_index) {
            return invariant("split point is not a UTF-8 character boundary");
        }
        let left = segment.text[..byte_index].trim_end().to_owned();
        let right = segment.text[byte_index..].trim_start().to_owned();
        if left.is_empty() || right.is_empty() {
            return invariant("split must leave text on both sides");
        }

        let line = &mut self.lyrics.lines[line_index];
        line.segments[segment_index].text = left;
        line.segments[segment_index].timing = SegmentTiming::default();
        line.segments.insert(
            segment_index + 1,
            LyricSegment {
                id: new_id,
                text: right,
                timing: SegmentTiming::default(),
            },
        );
        Ok(new_id)
    }

    pub fn merge_with_next(
        &mut self,
        segment_id: SegmentId,
        joiner: &str,
    ) -> Result<SegmentId, ProjectError> {
        let (line_index, segment_index) = self.segment_position(segment_id)?;
        let line = &mut self.lyrics.lines[line_index];
        if segment_index + 1 >= line.segments.len() {
            return invariant("segment has no next sibling to merge");
        }
        let right = line.segments.remove(segment_index + 1);
        let left = &mut line.segments[segment_index];
        left.text.push_str(joiner);
        left.text.push_str(&right.text);
        left.timing = SegmentTiming::default();
        Ok(left.id)
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
        segment.timing.review = ReviewState::UserConfirmed;
        Ok(())
    }

    pub fn apply_gemini_suggestion(
        &mut self,
        segment_id: SegmentId,
        point: AlignmentPoint,
        review: ReviewState,
    ) -> Result<bool, ProjectError> {
        if matches!(review, ReviewState::UserConfirmed | ReviewState::Pending) {
            return invariant("automatic suggestions require an automatic review state");
        }
        let segment = self.segment_mut(segment_id)?;
        segment.timing.gemini = Some(point);
        if segment.timing.review == ReviewState::UserConfirmed {
            return Ok(false);
        }
        segment.timing.final_point = Some(point);
        segment.timing.review = review;
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
            segment.timing.review = if segment.timing.final_point.is_some() {
                ReviewState::NeedsReview
            } else {
                ReviewState::Unmatched
            };
        }
    }

    fn segment_ids(&self) -> impl Iterator<Item = u64> + '_ {
        self.lyrics
            .lines
            .iter()
            .flat_map(|line| line.segments.iter().map(|segment| segment.id.0))
    }

    fn segment_position(&self, id: SegmentId) -> Result<(usize, usize), ProjectError> {
        self.lyrics
            .lines
            .iter()
            .enumerate()
            .find_map(|(line_index, line)| {
                line.segments
                    .iter()
                    .position(|segment| segment.id == id)
                    .map(|segment_index| (line_index, segment_index))
            })
            .ok_or(ProjectError::NotFound("segment", id.0))
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

    if segment.timing.review == ReviewState::UserConfirmed && segment.timing.final_point.is_none() {
        return invariant(format!(
            "user-confirmed segment {} has no final point",
            segment.id.0
        ));
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
