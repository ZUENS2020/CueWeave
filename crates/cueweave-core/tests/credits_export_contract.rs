use cueweave_core::{
    CreditLayout, Cue, ExportCueEvent, ExportFormat, LrcAdapter, PlayerExportAdapter, SongProject,
    UsltAdapter, add_credit, build_export_cue_sheet, build_openrouter_request, credit_time_ms,
    layout_credit_cues, merge_credits, replace_project_lyrics, set_credit_time,
};
use std::path::PathBuf;

fn timed_project() -> SongProject {
    let mut project = SongProject {
        target: Some(cueweave_core::TargetAudio {
            path: PathBuf::from("target.mp3"),
            fingerprint: None,
            duration_ms: Some(180_000),
        }),
        ..SongProject::default()
    };
    replace_project_lyrics(
        &mut project,
        "作词：MOMIKEN\n作曲：UZ\n朝焼けに ほどける\n抱えたまま行こう 君と",
        None,
    )
    .unwrap();
    project
}

#[test]
fn schema_two_credits_gain_ids_and_timeline_cues() {
    let json = r#"{
        "schema_version": 2,
        "lyrics": {
            "credits": [{"label": "作词", "value": "MOMIKEN"}, {"label": "作曲", "value": "UZ"}],
            "lines": []
        },
        "timeline": [{"type": "credit", "time_ms": 0, "text": "作词：MOMIKEN"}]
    }"#;
    let project = SongProject::from_json(json).unwrap();
    assert_eq!(project.schema_version, 3);
    assert_eq!(project.lyrics.credits[0].id.0, 1);
    assert_eq!(project.lyrics.credits[1].id.0, 2);
    let times: Vec<_> = project
        .timeline
        .iter()
        .filter_map(|cue| match cue {
            Cue::Credit { credit_id, time_ms } => Some((credit_id.0, *time_ms)),
            _ => None,
        })
        .collect();
    assert_eq!(times, vec![(1, 0), (2, 0)]);
}

#[test]
fn credit_layout_spaces_intro_before_first_lyric() {
    let mut project = timed_project();
    let first = project.lyrics.lines[0].segments[0].id;
    project.set_user_final(first, 8_346).unwrap();
    assert_eq!(
        layout_credit_cues(&mut project).unwrap(),
        CreditLayout::Arranged
    );
    assert_eq!(
        credit_time_ms(&project, project.lyrics.credits[0].id),
        Some(0)
    );
    assert_eq!(
        credit_time_ms(&project, project.lyrics.credits[1].id),
        Some(4_000)
    );
}

#[test]
fn short_intro_keeps_overlapping_credits() {
    let mut project = timed_project();
    add_credit(&mut project, "编曲", "somebody").unwrap();
    let first = project.lyrics.lines[0].segments[0].id;
    project.set_user_final(first, 2_200).unwrap();
    assert_eq!(
        layout_credit_cues(&mut project).unwrap(),
        CreditLayout::IntroTooShort
    );
    assert!(
        project
            .timeline
            .iter()
            .filter_map(|cue| match cue {
                Cue::Credit { time_ms, .. } => Some(*time_ms),
                _ => None,
            })
            .all(|time| time == 0)
    );
}

#[test]
fn credit_content_change_does_not_rebuild_cues() {
    let mut project = timed_project();
    let first = project.lyrics.lines[0].segments[0].id;
    project.set_user_final(first, 8_346).unwrap();
    layout_credit_cues(&mut project).unwrap();
    let id = project.lyrics.credits[0].id;
    set_credit_time(&mut project, id, 1_200).unwrap();
    project.lyrics.credits[0].label = "作詞".into();
    let sheet = build_export_cue_sheet(&project).unwrap();
    assert!(matches!(
        &sheet.events[0],
        ExportCueEvent::Credit { time_ms: 1_200, text } if text == "作詞：MOMIKEN"
    ));
}

#[test]
fn export_offset_applies_to_credits() {
    let mut project = timed_project();
    let first = project.lyrics.lines[0].segments[0].id;
    project.set_user_final(first, 8_346).unwrap();
    layout_credit_cues(&mut project).unwrap();
    project.export.offset_ms = 20;
    let sheet = build_export_cue_sheet(&project).unwrap();
    assert!(matches!(
        &sheet.events[0],
        ExportCueEvent::Credit { time_ms: 20, .. }
    ));
    assert!(matches!(
        &sheet.events[1],
        ExportCueEvent::Credit { time_ms: 4_020, .. }
    ));
}

#[test]
fn lrc_follows_credit_times() {
    let mut project = timed_project();
    let first = project.lyrics.lines[0].segments[0].id;
    project.set_user_final(first, 8_346).unwrap();
    layout_credit_cues(&mut project).unwrap();
    let lrc = String::from_utf8(
        LrcAdapter
            .write_sidecar(&build_export_cue_sheet(&project).unwrap())
            .unwrap(),
    )
    .unwrap();
    assert!(lrc.contains("[00:00.000]作词：MOMIKEN"));
    assert!(lrc.contains("[00:04.000]作曲：UZ"));
    assert!(lrc.contains("[00:08.346]朝焼けに ほどける"));
}

#[test]
fn uslt_only_includes_timed_lyric_events() {
    let mut project = SongProject::default();
    let mut original = String::new();
    for index in 1..=51 {
        original.push_str(&format!("line {index}\n"));
    }
    replace_project_lyrics(
        &mut project,
        &original,
        Some(&{
            let mut translated = String::new();
            for index in 1..=51 {
                translated.push_str(&format!("译 {index}\n"));
            }
            translated
        }),
    )
    .unwrap();
    project.target = Some(cueweave_core::TargetAudio {
        path: PathBuf::from("target.mp3"),
        fingerprint: None,
        duration_ms: Some(200_000),
    });
    for index in 0..38 {
        let id = project.lyrics.lines[index].segments[0].id;
        project
            .set_user_final(id, 1_000 + index as u64 * 1_000)
            .unwrap();
    }
    project.export.formats = vec![ExportFormat::Uslt];
    project.export.bilingual = cueweave_core::BilingualMode::Bilingual;
    let sheet = build_export_cue_sheet(&project).unwrap();
    let lyric_events = sheet
        .events
        .iter()
        .filter(|event| matches!(event, ExportCueEvent::Lyric { .. }))
        .count();
    assert_eq!(lyric_events, 38);
    let mut tag = id3::Tag::new();
    UsltAdapter.embed(&mut tag, &sheet).unwrap();
    let lyrics: Vec<_> = tag.lyrics().collect();
    let original = lyrics
        .iter()
        .find(|frame| frame.lang == "und")
        .unwrap()
        .text
        .lines()
        .count();
    let translated = lyrics
        .iter()
        .find(|frame| frame.lang == "zho")
        .unwrap()
        .text
        .lines()
        .count();
    assert_eq!(original, 38);
    assert_eq!(translated, 38);
    assert!(!lyrics[0].text.contains("line 39"));
    let mut tag = id3::Tag::new();
    cueweave_core::SyltAdapter.embed(&mut tag, &sheet).unwrap();
    let synced: Vec<_> = tag.synchronised_lyrics().collect();
    let original_frames = synced
        .iter()
        .find(|frame| frame.lang == "und")
        .unwrap()
        .content
        .len();
    let translated_frames = synced
        .iter()
        .find(|frame| frame.lang == "zho")
        .unwrap()
        .content
        .len();
    assert_eq!(original_frames, 38);
    assert_eq!(translated_frames, 38);
}

#[test]
fn unmatched_line_joins_export_after_manual_final() {
    let mut project = timed_project();
    let last = project.lyrics.lines[1].segments[0].id;
    assert!(
        build_export_cue_sheet(&project)
            .unwrap()
            .events
            .iter()
            .all(|event| !matches!(event, ExportCueEvent::Lyric { line_id: 2, .. }))
    );
    project.set_user_final(last, 12_000).unwrap();
    assert!(
        build_export_cue_sheet(&project)
            .unwrap()
            .events
            .iter()
            .any(|event| matches!(event, ExportCueEvent::Lyric { line_id: 2, .. }))
    );
    project.clear_user_final(last).unwrap();
    assert!(
        build_export_cue_sheet(&project)
            .unwrap()
            .events
            .iter()
            .all(|event| !matches!(event, ExportCueEvent::Lyric { line_id: 2, .. }))
    );
}

#[test]
fn merge_credits_collapses_to_one_cue() {
    let mut project = timed_project();
    merge_credits(&mut project).unwrap();
    assert_eq!(project.lyrics.credits.len(), 1);
    assert_eq!(
        project.lyrics.credits[0].display_text(),
        "作词：MOMIKEN / 作曲：UZ"
    );
    assert_eq!(
        project
            .timeline
            .iter()
            .filter(|cue| matches!(cue, Cue::Credit { .. }))
            .count(),
        1
    );
}

#[test]
fn alignment_prompt_omits_credits() {
    let mut project = timed_project();
    project.target.as_mut().unwrap().duration_ms = Some(30_000);
    let request = build_openrouter_request(&project, "AAAA".into(), "model").unwrap();
    let prompt = request.to_string();
    assert!(!prompt.contains("作词"));
    assert!(!prompt.contains("MOMIKEN"));
    assert!(prompt.contains("朝焼けに ほどける"));
}
