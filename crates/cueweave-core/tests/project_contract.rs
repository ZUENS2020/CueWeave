use cueweave_core::{
    AlignmentPoint, BilingualMode, CURRENT_SCHEMA_VERSION, Cue, LineId, LyricsError,
    MetadataValues, ProjectError, SegmentId, SongProject, SourceInfo, TargetAudio,
    insert_project_lyrics, replace_project_lyrics,
};
use std::path::PathBuf;

fn ready_project() -> SongProject {
    let mut project = SongProject {
        source: Some(SourceInfo {
            path: PathBuf::from("source.ncm"),
            fingerprint: None,
            music_id: Some(42),
            cover_url: None,
            format: Some("mp3".into()),
            duration_ms: Some(60_000),
        }),
        target: Some(TargetAudio {
            path: PathBuf::from("target.mp3"),
            fingerprint: None,
            duration_ms: Some(60_000),
        }),
        ..SongProject::default()
    };
    project.metadata.draft = MetadataValues {
        title: Some("Song".into()),
        artists: vec!["Singer".into()],
        ..MetadataValues::default()
    };
    project
        .add_line("朝焼けに ほどける", ["朝焼けに".into(), "ほどける".into()])
        .unwrap();
    project
}

#[test]
fn project_json_round_trip_is_stable() {
    let project = ready_project();
    let json = project.to_json_pretty().unwrap();
    let decoded = SongProject::from_json(&json).unwrap();
    assert_eq!(decoded, project);
    assert!(!json.contains("source_timing"));
    assert!(!json.contains("source_start"));
}

#[test]
fn unknown_json_fields_are_ignored() {
    let json = SongProject::default().to_json_pretty().unwrap();
    let mut value: serde_json::Value = serde_json::from_str(&json).unwrap();
    value["future_field"] = serde_json::json!({"enabled": true});
    SongProject::from_json(&serde_json::to_string(&value).unwrap()).unwrap();
}

#[test]
fn schema_one_is_migrated_and_newer_schema_is_rejected() {
    let mut value = serde_json::to_value(ready_project()).unwrap();
    value["schema_version"] = serde_json::json!(1);
    let migrated = SongProject::from_json(&value.to_string()).unwrap();
    assert_eq!(migrated.schema_version, CURRENT_SCHEMA_VERSION);

    value["schema_version"] = serde_json::json!(CURRENT_SCHEMA_VERSION + 1);
    assert!(SongProject::from_json(&value.to_string()).is_err());
}

#[test]
fn project_save_is_atomic_and_media_paths_are_relative() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("中文 项目.cueweave");
    let media = directory.path().join("media");
    let mut project = ready_project();
    project.source.as_mut().unwrap().path = media.join("source.ncm");
    project.target.as_mut().unwrap().path = media.join("target.mp3");
    project.metadata.draft.cover_path = Some(media.join("cover.jpg"));

    for _ in 0..100 {
        project.save(&path).unwrap();
    }
    let json = std::fs::read_to_string(&path).unwrap();
    assert!(json.contains("media/source.ncm"));
    assert!(json.contains("media/target.mp3"));
    assert!(!json.contains(&directory.path().to_string_lossy().to_string()));
    let loaded = SongProject::load(&path).unwrap();
    assert_eq!(loaded.target.unwrap().path, media.join("target.mp3"));
}

#[test]
fn duplicate_segment_ids_are_rejected() {
    let mut project = ready_project();
    let duplicate = project.lyrics.lines[0].segments[0].id;
    project.lyrics.lines[0].segments[1].id = duplicate;
    let error = project.validate().unwrap_err().to_string();
    assert!(error.contains("duplicate segment id"));
}

#[test]
fn existing_final_is_not_overwritten_by_gemini() {
    let mut project = ready_project();
    let segment_id = project.lyrics.lines[0].segments[0].id;
    project.set_user_final(segment_id, 8_430).unwrap();
    let changed = project
        .apply_gemini_suggestion(
            segment_id,
            AlignmentPoint {
                time_ms: 8_390,
                confidence: Some(0.98),
            },
        )
        .unwrap();

    let timing = &project.lyrics.lines[0].segments[0].timing;
    assert!(!changed);
    assert_eq!(timing.gemini.unwrap().time_ms, 8_390);
    assert_eq!(timing.final_point.unwrap().time_ms, 8_430);
}

#[test]
fn legacy_review_field_is_ignored_and_not_rewritten() {
    let mut value = serde_json::to_value(ready_project()).unwrap();
    value["lyrics"]["lines"][0]["segments"][0]["timing"]["review"] =
        serde_json::json!("needs_review");
    let project = SongProject::from_json(&value.to_string()).unwrap();
    let json = project.to_json_pretty().unwrap();
    assert!(!json.contains("\"review\""));
}

#[test]
fn out_of_order_or_out_of_range_final_points_are_rejected() {
    let mut project = ready_project();
    let ids: Vec<SegmentId> = project.lyrics.lines[0]
        .segments
        .iter()
        .map(|segment| segment.id)
        .collect();
    project.set_user_final(ids[0], 50_000).unwrap();
    project.set_user_final(ids[1], 49_000).unwrap();
    assert!(
        project
            .validate()
            .unwrap_err()
            .to_string()
            .contains("out of order")
    );

    project.set_user_final(ids[1], 61_000).unwrap();
    assert!(
        project
            .validate()
            .unwrap_err()
            .to_string()
            .contains("past target duration")
    );
}

#[test]
fn insert_lyrics_keeps_neighbor_ids_finals_and_timeline_order() {
    let mut project = SongProject::default();
    replace_project_lyrics(&mut project, "first\nthird", None).unwrap();
    let first_id = project.lyrics.lines[0].id;
    let third_id = project.lyrics.lines[1].id;
    let first_segment = project.lyrics.lines[0].segments[0].id;
    project.set_user_final(first_segment, 1_200).unwrap();
    project.lyrics.lines[0].translation = Some("第一句".into());

    let inserted =
        insert_project_lyrics(&mut project, Some(first_id), "[00:08.45]second\nsecond b").unwrap();
    assert_eq!(inserted.len(), 2);
    assert_eq!(
        project
            .lyrics
            .lines
            .iter()
            .map(|line| line.original.as_str())
            .collect::<Vec<_>>(),
        ["first", "second", "second b", "third"]
    );
    assert_eq!(project.lyrics.lines[0].id, first_id);
    assert_eq!(project.lyrics.lines[3].id, third_id);
    assert_eq!(
        project.lyrics.lines[0].translation.as_deref(),
        Some("第一句")
    );
    assert_eq!(
        project.lyrics.lines[0].segments[0]
            .timing
            .final_point
            .unwrap()
            .time_ms,
        1_200
    );
    assert!(
        project.lyrics.lines[1].segments[0]
            .timing
            .final_point
            .is_none()
    );
    let lyric_ids: Vec<_> = project
        .timeline
        .iter()
        .filter_map(|cue| match cue {
            Cue::Lyric { line_id } => Some(*line_id),
            _ => None,
        })
        .collect();
    assert_eq!(
        lyric_ids,
        vec![first_id, inserted[0], inserted[1], third_id]
    );
    project.validate().unwrap();
}

#[test]
fn insert_lyrics_at_start_and_rejects_empty_or_unknown_anchor() {
    let mut project = SongProject::default();
    replace_project_lyrics(&mut project, "only", None).unwrap();
    assert!(matches!(
        insert_project_lyrics(&mut project, None, " \n[ar:skip]\n"),
        Err(LyricsError::Empty)
    ));
    assert!(matches!(
        insert_project_lyrics(&mut project, Some(LineId(999)), "x"),
        Err(LyricsError::Project(ProjectError::NotFound("line", 999)))
    ));
    insert_project_lyrics(&mut project, None, "intro").unwrap();
    assert_eq!(project.lyrics.lines[0].original, "intro");
    assert_eq!(project.lyrics.lines[1].original, "only");
}

#[test]
fn bilingual_mode_accepts_legacy_combined_alias() {
    let mode: BilingualMode = serde_json::from_str("\"combined\"").unwrap();
    assert_eq!(mode, BilingualMode::Bilingual);
    assert_eq!(serde_json::to_string(&mode).unwrap(), "\"bilingual\"");
}
