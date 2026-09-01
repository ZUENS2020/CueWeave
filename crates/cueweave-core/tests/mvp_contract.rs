use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};
use base64::Engine;
use cueweave_core::{
    AlignmentItem, AlignmentResponse, BilingualMode, CUESHEET_SCHEMA_VERSION, ExportFormat,
    LrcAdapter, MatchStatus, MetadataValues, PlayerExportAdapter, ReviewState, SegmentId,
    SongProject, SourceInfo, TargetAudio, apply_alignment_response,
    apply_alignment_response_selected, apply_line_translations, apply_translation_response,
    audio_payload_sha256, build_ai_studio_request, build_export_cue_sheet,
    build_openrouter_request, build_openrouter_translation_request, decode_netease_payload,
    download_cover, export_mp3, inspect_ncm, list_export_adapters, normalize_lyrics,
    parse_ai_studio_envelope, parse_alignment_response, parse_openrouter_envelope,
    parse_translation_response, render_cuesheet_json, replace_project_lyrics, replace_target_audio,
};
use id3::{Tag, TagLike, Version};
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const META_KEY: [u8; 16] = [
    0x23, 0x31, 0x34, 0x6c, 0x6a, 0x6b, 0x5f, 0x21, 0x5c, 0x5d, 0x26, 0x30, 0x55, 0x3c, 0x27, 0x28,
];

fn temp_path(extension: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "cueweave-test-{}-{nonce}.{extension}",
        std::process::id()
    ))
}

fn timed_project(target: PathBuf) -> SongProject {
    let mut project = SongProject {
        source: Some(SourceInfo {
            path: PathBuf::from("source.ncm"),
            fingerprint: None,
            music_id: Some(42),
            cover_url: None,
            format: Some("mp3".into()),
            duration_ms: Some(30_000),
        }),
        target: Some(TargetAudio {
            path: target,
            fingerprint: None,
            duration_ms: Some(30_000),
        }),
        ..SongProject::default()
    };
    project.metadata.draft = MetadataValues {
        title: Some("Beyond".into()),
        artists: vec!["Singer".into()],
        album: Some("Album".into()),
        ..MetadataValues::default()
    };
    project
        .add_line("朝焼けに ほどける", ["朝焼けに".into(), "ほどける".into()])
        .unwrap();
    project
}

fn write_fake_mp3(path: &PathBuf) {
    let payload = [
        b"ID3".as_slice(),
        &[4, 0, 0, 0, 0, 0, 0],
        &[0xff, 0xfb, 0x90, 0x64],
        &[0x55; 2048],
    ]
    .concat();
    fs::write(path, payload).unwrap();
}

#[test]
fn lyric_normalizer_destroys_line_and_word_timestamps() {
    let raw = r#"
[ar:ignored]
[00:00.000]作词：MOMIKEN
[00:08.450]<00:08.450>朝焼けに (8450,300,0)ほどける
[10750,500](10750,250,0)僕らの
[00:12.000]僕らの
"#;
    let lyrics = normalize_lyrics(raw);
    assert_eq!(lyrics.credits[0].label, "作词");
    assert_eq!(lyrics.lines, ["朝焼けに ほどける", "僕らの"]);
    assert!(lyrics.lines.iter().all(|line| !line.contains("8450,")));
}

#[test]
fn netease_payload_can_only_enter_project_as_plain_text() {
    let payload = r#"{
        "code": 200,
        "lrc": {"lyric": "[00:08.45]朝焼けに\n[00:10.75]ほどける"},
        "tlyric": {"lyric": "[00:08.45]在朝霞中\n[00:10.75]逐渐舒展"}
    }"#;
    let lyrics = decode_netease_payload(payload).unwrap();
    let mut project = SongProject::default();
    replace_project_lyrics(
        &mut project,
        &lyrics.original,
        lyrics.translation.as_deref(),
    )
    .unwrap();
    let json = project.to_json_pretty().unwrap();
    assert_eq!(project.lyrics.lines[0].original, "朝焼けに");
    assert_eq!(
        project.lyrics.lines[0].translation.as_deref(),
        Some("在朝霞中")
    );
    assert!(!json.contains("00:08"));
    assert!(!json.contains("source_timing"));
}

#[test]
fn imported_lyrics_keep_each_original_line_as_one_segment() {
    let mut project = SongProject::default();
    replace_project_lyrics(&mut project, "朝焼けに ほどける\n僕らのシルエット", None).unwrap();
    assert_eq!(project.lyrics.lines.len(), 2);
    assert_eq!(project.lyrics.lines[0].segments.len(), 1);
    assert_eq!(
        project.lyrics.lines[0].segments[0].text,
        "朝焼けに ほどける"
    );
}

#[test]
fn translations_bind_by_line_order_and_leave_originals_untouched() {
    let mut project = SongProject::default();
    replace_project_lyrics(&mut project, "朝焼けに\nほどける\n僕らの", None).unwrap();
    let original_ids: Vec<_> = project.lyrics.lines.iter().map(|line| line.id).collect();
    let applied =
        apply_line_translations(&mut project, "[00:08.45]在朝霞中\n[00:10.75]逐渐舒展").unwrap();
    assert_eq!(applied, 2);
    assert_eq!(project.lyrics.lines[0].original, "朝焼けに");
    assert_eq!(
        project.lyrics.lines[0].translation.as_deref(),
        Some("在朝霞中")
    );
    assert_eq!(
        project.lyrics.lines[1].translation.as_deref(),
        Some("逐渐舒展")
    );
    assert_eq!(project.lyrics.lines[2].translation, None);
    assert_eq!(
        project
            .lyrics
            .lines
            .iter()
            .map(|line| line.id)
            .collect::<Vec<_>>(),
        original_ids
    );
}

#[test]
fn gemini_translation_json_must_cover_every_line_id_in_order() {
    let mut project = SongProject::default();
    replace_project_lyrics(&mut project, "朝焼けに\nほどける", None).unwrap();
    let first = project.lyrics.lines[0].id;
    let second = project.lyrics.lines[1].id;
    let json = format!(
        r#"{{"lines":[{{"id":{},"translation":"在朝霞中"}},{{"id":{},"translation":"逐渐舒展"}}]}}"#,
        first.0, second.0
    );
    let response = parse_translation_response(&json, &project).unwrap();
    apply_translation_response(&mut project, &response).unwrap();
    assert_eq!(
        project.lyrics.lines[0].translation.as_deref(),
        Some("在朝霞中")
    );
    assert_eq!(
        project.lyrics.lines[1].translation.as_deref(),
        Some("逐渐舒展")
    );

    let swapped = format!(
        r#"{{"lines":[{{"id":{},"translation":"逐渐舒展"}},{{"id":{},"translation":"在朝霞中"}}]}}"#,
        second.0, first.0
    );
    assert!(parse_translation_response(&swapped, &project).is_err());

    let request =
        build_openrouter_translation_request(&project, "google/gemini-3.7-flash", None).unwrap();
    let encoded = request.to_string();
    assert!(!encoded.contains("input_audio"));
    assert!(encoded.contains("cueweave_translation"));
    assert!(encoded.contains(&first.0.to_string()));
    assert!(encoded.contains("complete original lyric"));
    assert!(encoded.contains("朝焼けに\\nほどける"));
}

#[test]
fn synthetic_ncm_header_yields_metadata_and_cover_without_audio_decryption() {
    let path = temp_path("ncm");
    let metadata = serde_json::json!({
        "musicId": 3425431142_u64,
        "musicName": "Beyond",
        "artist": [["Singer", 1]],
        "album": "Beyond",
        "albumPic": "https://example.invalid/cover.jpg",
        "format": "mp3",
        "duration": 212847
    });
    let encrypted = encrypt_ncm_metadata(&metadata.to_string());
    let cover = b"\x89PNG\r\n\x1a\n";
    let mut bytes = b"CTENFDAM".to_vec();
    bytes.extend_from_slice(&[0, 0]);
    bytes.extend_from_slice(&0_u32.to_le_bytes());
    bytes.extend_from_slice(&(encrypted.len() as u32).to_le_bytes());
    bytes.extend_from_slice(&encrypted);
    bytes.extend_from_slice(&[0; 9]);
    bytes.extend_from_slice(&(cover.len() as u32).to_le_bytes());
    bytes.extend_from_slice(cover);
    bytes.extend_from_slice(b"encrypted audio is intentionally ignored");
    fs::write(&path, bytes).unwrap();

    let info = inspect_ncm(&path).unwrap();
    assert_eq!(info.music_id, Some(3425431142));
    assert_eq!(info.metadata.title.as_deref(), Some("Beyond"));
    assert_eq!(info.metadata.artists, ["Singer"]);
    assert_eq!(info.cover.unwrap().mime_type, "image/png");
    fs::remove_file(path).unwrap();
}

#[test]
fn cover_download_rejects_non_netease_hosts_before_network_access() {
    assert!(download_cover("https://example.com/cover.jpg").is_err());
}

#[test]
fn alignment_validator_requires_every_id_once_and_in_order() {
    let project = timed_project(PathBuf::from("target.mp3"));
    let valid = r#"{"segments":[
        {"id":1,"status":"matched","start_seconds":8.450,"confidence":0.98},
        {"id":2,"status":"uncertain","start_seconds":10.750,"confidence":0.7}
    ]}"#;
    assert!(parse_alignment_response(valid, &project).is_ok());

    let missing = r#"{"segments":[{"id":1,"status":"matched","start_seconds":8.450}]}"#;
    assert!(parse_alignment_response(missing, &project).is_err());
    let out_of_order = r#"{"segments":[
        {"id":1,"status":"matched","start_seconds":12.000,"confidence":0.9},
        {"id":2,"status":"matched","start_seconds":11.000,"confidence":0.9}
    ]}"#;
    assert!(parse_alignment_response(out_of_order, &project).is_err());
    let swapped_ids = r#"{"segments":[
        {"id":2,"status":"matched","start_seconds":8.450,"confidence":0.9},
        {"id":1,"status":"matched","start_seconds":10.750,"confidence":0.9}
    ]}"#;
    assert!(parse_alignment_response(swapped_ids, &project).is_err());
}

#[test]
fn openrouter_contract_carries_mp3_and_strict_schema_without_source_timing() {
    let mut project = timed_project(PathBuf::from("target.mp3"));
    project.merge_with_next(SegmentId(1), " ").unwrap();
    let request =
        build_openrouter_request(&project, "base64-audio".into(), "google/gemini-3.7-flash")
            .unwrap();
    assert_eq!(
        request.pointer("/messages/0/content/1/input_audio/format"),
        Some(&serde_json::json!("mp3"))
    );
    assert_eq!(
        request.pointer("/response_format/type"),
        Some(&serde_json::json!("json_schema"))
    );
    assert_eq!(
        request.pointer("/response_format/json_schema/schema/type"),
        Some(&serde_json::json!("object"))
    );
    assert_eq!(
        request.pointer(
            "/response_format/json_schema/schema/properties/segments/items/properties/start_seconds/type"
        ),
        Some(&serde_json::json!(["number", "null"]))
    );
    assert_eq!(
        request.pointer("/provider/require_parameters"),
        Some(&serde_json::json!(true))
    );
    assert_eq!(request.pointer("/temperature"), Some(&serde_json::json!(0)));
    let prompt = request
        .pointer("/messages/0/content/0/text")
        .and_then(serde_json::Value::as_str)
        .unwrap();
    assert!(prompt.contains("朝焼けに ほどける"));
    assert!(!prompt.contains("\"text\":\"朝焼けに\""));
    assert!(!request.to_string().contains("source_timing"));

    let alignment = r#"{"segments":[
        {"id":1,"status":"matched","start_seconds":8.450,"confidence":0.98}
    ]}"#;
    let envelope = serde_json::json!({
        "choices": [{"message": {"content": alignment}}]
    });
    let response = parse_openrouter_envelope(&envelope.to_string(), &project).unwrap();
    assert_eq!(response.segments[0].start_ms, Some(8_450));
}

#[test]
fn ai_studio_contract_uses_live_mime_enum_and_shared_validator() {
    let mut project = timed_project(PathBuf::from("target.mp3"));
    project.merge_with_next(SegmentId(1), " ").unwrap();
    let request = build_ai_studio_request(&project, "base64-audio".into()).unwrap();
    assert_eq!(
        request.pointer("/contents/0/parts/1/inlineData/mimeType"),
        Some(&serde_json::json!("audio/mpeg"))
    );
    assert_eq!(
        request.pointer("/generationConfig/responseFormat/text/mimeType"),
        Some(&serde_json::json!("APPLICATION_JSON"))
    );
    assert_eq!(
        request.pointer("/generationConfig/temperature"),
        Some(&serde_json::json!(0))
    );
    assert!(!request.to_string().contains("source_timing"));

    let alignment = r#"{"segments":[
        {"id":1,"status":"matched","start_seconds":8.450,"confidence":0.98}
    ]}"#;
    let envelope = serde_json::json!({
        "candidates": [{"content": {"parts": [{"text": alignment}]}}]
    });
    let response = parse_ai_studio_envelope(&envelope.to_string(), &project).unwrap();
    assert_eq!(response.segments[0].start_ms, Some(8_450));
}

#[test]
fn alignment_application_marks_confidence_and_unmatched_without_guessing() {
    let mut project = timed_project(PathBuf::from("target.mp3"));
    let response = AlignmentResponse {
        segments: vec![
            AlignmentItem {
                id: SegmentId(1),
                status: MatchStatus::Matched,
                start_ms: Some(8_450),
                confidence: Some(0.98),
            },
            AlignmentItem {
                id: SegmentId(2),
                status: MatchStatus::Unmatched,
                start_ms: None,
                confidence: None,
            },
        ],
    };
    apply_alignment_response(&mut project, &response).unwrap();
    assert_eq!(
        project.lyrics.lines[0].segments[0].timing.review,
        ReviewState::NeedsReview
    );
    assert_eq!(
        project.lyrics.lines[0].segments[1].timing.review,
        ReviewState::Unmatched
    );
    assert!(
        project.lyrics.lines[0].segments[1]
            .timing
            .final_point
            .is_none()
    );
}

#[test]
fn selection_alignment_changes_only_selected_segments() {
    let mut project = timed_project(PathBuf::from("target.mp3"));
    project.set_user_final(SegmentId(2), 12_000).unwrap();
    let preserved = project.lyrics.lines[0].segments[1].timing.clone();
    let response = AlignmentResponse {
        segments: vec![
            AlignmentItem {
                id: SegmentId(1),
                status: MatchStatus::Matched,
                start_ms: Some(8_450),
                confidence: Some(0.98),
            },
            AlignmentItem {
                id: SegmentId(2),
                status: MatchStatus::Matched,
                start_ms: Some(10_750),
                confidence: Some(0.95),
            },
        ],
    };
    apply_alignment_response_selected(&mut project, &response, &[SegmentId(1)]).unwrap();
    assert_eq!(
        project.lyrics.lines[0].segments[0]
            .timing
            .gemini
            .unwrap()
            .time_ms,
        8_450
    );
    assert_eq!(project.lyrics.lines[0].segments[1].timing, preserved);
}

#[test]
fn replacing_target_preserves_draft_and_invalidates_every_timing_layer() {
    let original = temp_path("mp3");
    let replacement = temp_path("replacement.mp3");
    write_fake_mp3(&original);
    write_fake_mp3(&replacement);
    let mut project = timed_project(original.clone());
    project.set_user_final(SegmentId(1), 8_450).unwrap();
    replace_target_audio(&mut project, &replacement).unwrap();

    assert_eq!(project.target.as_ref().unwrap().path, replacement);
    assert_eq!(project.metadata.draft.title.as_deref(), Some("Beyond"));
    assert!(
        project
            .lyrics
            .lines
            .iter()
            .flat_map(|line| &line.segments)
            .all(|segment| segment.timing == Default::default())
    );
    fs::remove_file(original).unwrap();
    fs::remove_file(replacement).unwrap();
}

#[test]
fn mp3_export_preserves_audio_payload_and_writes_lyrics() {
    let input = temp_path("mp3");
    let output = temp_path("final.mp3");
    let lrc = output.with_extension("lrc");
    write_fake_mp3(&input);
    let mut existing = Tag::new();
    existing.set_text("TCOM", "Old composer");
    existing.write_to_path(&input, Version::Id3v24).unwrap();
    let before = audio_payload_sha256(&input).unwrap();
    let mut project = timed_project(input.clone());
    project.export.formats = vec![ExportFormat::Lrc, ExportFormat::Uslt, ExportFormat::Sylt];
    project.export.bilingual = BilingualMode::Combined;
    project.lyrics.lines[0].translation = Some("在朝霞中舒展".into());
    project.set_user_final(SegmentId(1), 8_450).unwrap();
    project.set_user_final(SegmentId(2), 10_750).unwrap();

    let result = export_mp3(&project, &output).unwrap();
    assert_eq!(result.audio_sha256, before);
    assert_eq!(audio_payload_sha256(&input).unwrap(), before);
    let tag = Tag::read_from_path(&output).unwrap();
    assert_eq!(tag.title(), Some("Beyond"));
    assert!(tag.get("TCOM").is_none());
    assert_eq!(tag.lyrics().count(), 1);
    assert_eq!(tag.synchronised_lyrics().count(), 1);
    assert!(
        fs::read_to_string(&lrc)
            .unwrap()
            .contains("朝焼けに ほどける / 在朝霞中舒展")
    );

    fs::remove_file(input).unwrap();
    fs::remove_file(output).unwrap();
    fs::remove_file(lrc).unwrap();
}

#[test]
fn export_cue_sheet_is_the_player_adapter_contract() {
    let input = temp_path("mp3");
    write_fake_mp3(&input);
    let mut project = timed_project(input.clone());
    project.export.bilingual = BilingualMode::Combined;
    project.lyrics.lines[0].translation = Some("在朝霞中舒展".into());
    project.set_user_final(SegmentId(1), 8_450).unwrap();
    project.set_user_final(SegmentId(2), 10_750).unwrap();

    let sheet = build_export_cue_sheet(&project).unwrap();
    assert_eq!(sheet.schema_version, CUESHEET_SCHEMA_VERSION);
    assert_eq!(sheet.metadata.title.as_deref(), Some("Beyond"));
    assert_eq!(sheet.lines.len(), 1);
    assert_eq!(sheet.lines[0].start_ms, Some(8_450));
    assert!(sheet.lines[0].text.contains("在朝霞中舒展"));
    let json = render_cuesheet_json(&project).unwrap();
    assert!(json.contains("\"schema_version\": 1"));
    let lrc = String::from_utf8(LrcAdapter.write_sidecar(&sheet).unwrap()).unwrap();
    assert!(lrc.contains("[00:08.450]"));
    let adapters = list_export_adapters();
    assert_eq!(
        adapters
            .iter()
            .map(|adapter| adapter.id.as_str())
            .collect::<Vec<_>>(),
        ["lrc", "uslt", "sylt"]
    );
    fs::remove_file(input).unwrap();
}

fn encrypt_ncm_metadata(json: &str) -> Vec<u8> {
    let mut plaintext = format!("music:{json}").into_bytes();
    let padding = 16 - plaintext.len() % 16;
    plaintext.extend(std::iter::repeat_n(padding as u8, padding));
    let cipher = Aes128::new_from_slice(&META_KEY).unwrap();
    for block in plaintext.chunks_exact_mut(16) {
        cipher.encrypt_block(GenericArray::from_mut_slice(block));
    }
    let mut encoded = b"163 key(Don't modify):".to_vec();
    encoded.extend_from_slice(
        base64::engine::general_purpose::STANDARD
            .encode(plaintext)
            .as_bytes(),
    );
    for byte in &mut encoded {
        *byte ^= 0x63;
    }
    encoded
}
