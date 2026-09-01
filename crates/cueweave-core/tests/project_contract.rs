use cueweave_core::{
    AlignmentPoint, CURRENT_SCHEMA_VERSION, MetadataValues, ReviewState, SegmentId, SongProject,
    SourceInfo, TargetAudio,
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
fn user_confirmed_final_is_not_overwritten() {
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
            ReviewState::AutoAccepted,
        )
        .unwrap();

    let timing = &project.lyrics.lines[0].segments[0].timing;
    assert!(!changed);
    assert_eq!(timing.gemini.unwrap().time_ms, 8_390);
    assert_eq!(timing.final_point.unwrap().time_ms, 8_430);
    assert_eq!(timing.review, ReviewState::UserConfirmed);
}

#[test]
fn split_and_merge_preserve_the_surviving_id_and_clear_timing() {
    let mut project = ready_project();
    let first = project.lyrics.lines[0].segments[0].id;
    project.set_user_final(first, 8_430).unwrap();
    let split_at = "朝".len();
    let new_id = project.split_segment(first, split_at).unwrap();
    assert_ne!(new_id, first);
    assert_eq!(project.lyrics.lines[0].segments[0].id, first);
    assert!(
        project.lyrics.lines[0].segments[0]
            .timing
            .final_point
            .is_none()
    );

    let merged = project.merge_with_next(first, "").unwrap();
    assert_eq!(merged, first);
    assert_eq!(project.lyrics.lines[0].segments[0].text, "朝焼けに");
}

#[test]
fn status_is_derived_from_project_content() {
    let mut project = ready_project();
    let ids: Vec<_> = project.lyrics.lines[0]
        .segments
        .iter()
        .map(|segment| segment.id)
        .collect();
    project.set_user_final(ids[0], 8_430).unwrap();
    project.set_user_final(ids[1], 10_750).unwrap();

    let status = project.status();
    assert!(status.source_loaded);
    assert!(status.target_loaded);
    assert!(status.metadata_ready);
    assert!(status.lyrics_ready);
    assert!(status.alignment_ready);
    assert!(status.export_ready);
    assert_eq!(status.review_count, 0);
}

#[test]
fn export_is_not_ready_until_target_duration_is_known() {
    let mut project = ready_project();
    let ids: Vec<_> = project.lyrics.lines[0]
        .segments
        .iter()
        .map(|segment| segment.id)
        .collect();
    project.set_user_final(ids[0], 8_430).unwrap();
    project.set_user_final(ids[1], 10_750).unwrap();
    project.target.as_mut().unwrap().duration_ms = None;

    assert!(!project.status().export_ready);
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
