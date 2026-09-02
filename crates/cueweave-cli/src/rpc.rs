use cueweave_core::{
    CreditId, CreditLayout, LineId, SegmentId, SongProject, apply_line_translations, export_mp3,
    fetch_netease_lyrics, insert_project_lyrics, layout_credit_cues, list_audio_viz_adapters,
    list_export_adapters, merge_credits, render_cuesheet_json, replace_project_lyrics,
    replace_target_audio, run_audio_viz, set_credit_time,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::error::Error;
use std::fs;
use std::io::{Read, Write};
use std::path::Path;

pub(crate) const RPC_PROTOCOL_VERSION: u32 = 1;

#[derive(Deserialize)]
struct RpcRequest {
    protocol_version: u32,
    request_id: String,
    command: String,
    #[serde(default)]
    payload: Value,
}

#[derive(Serialize)]
pub(crate) struct RpcResponse {
    pub(crate) request_id: String,
    pub(crate) ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) error: Option<RpcError>,
}

#[derive(Serialize)]
pub(crate) struct RpcError {
    pub(crate) code: &'static str,
    pub(crate) message: String,
}

pub(crate) fn run_rpc() -> Result<(), Box<dyn Error>> {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input)?;
    let response = rpc_response(input.trim_start_matches('\u{feff}'));
    let stdout = std::io::stdout();
    let mut output = stdout.lock();
    serde_json::to_writer(&mut output, &response)?;
    output.write_all(b"\n")?;
    output.flush()?;
    Ok(())
}

pub(crate) fn rpc_response(input: &str) -> RpcResponse {
    let input = input.trim_start_matches('\u{feff}').trim();
    let request: RpcRequest = match serde_json::from_str(input) {
        Ok(request) => request,
        Err(error) => return rpc_failure(String::new(), "invalid_request", error.to_string()),
    };
    let request_id = request.request_id.clone();
    if request.protocol_version != RPC_PROTOCOL_VERSION {
        return rpc_failure(
            request_id,
            "unsupported_protocol",
            format!("RPC protocol {} is unsupported", request.protocol_version),
        );
    }
    match dispatch_rpc(request) {
        Ok(result) => RpcResponse {
            request_id,
            ok: true,
            result: Some(result),
            error: None,
        },
        Err((code, message)) => rpc_failure(request_id, code, message),
    }
}

fn dispatch_rpc(request: RpcRequest) -> Result<Value, (&'static str, String)> {
    let run = || -> Result<Value, Box<dyn Error>> {
        let payload = &request.payload;
        match request.command.as_str() {
            "ping" => Ok(json!({"protocol_version": RPC_PROTOCOL_VERSION})),
            "new" => {
                SongProject::default().save(payload_path(payload, "project_path")?)?;
                Ok(Value::Null)
            }
            "create" => {
                crate::create_project_file(
                    payload_path(payload, "project_path")?,
                    payload_path(payload, "source_path")?,
                    payload_path(payload, "target_path")?,
                )?;
                Ok(Value::Null)
            }
            "load_project" => Ok(serde_json::to_value(SongProject::load(payload_path(
                payload,
                "project_path",
            )?)?)?),
            "save_project" => {
                let json = payload
                    .get("project")
                    .ok_or("payload.project is required")?;
                let project = SongProject::from_json(&json.to_string())?;
                if payload.get("project_path").is_some() {
                    project.save(payload_path(payload, "project_path")?)?;
                }
                Ok(Value::Null)
            }
            "set_final" => {
                let path = payload_path(payload, "project_path")?;
                let mut project = SongProject::load(path)?;
                let id = SegmentId(
                    payload
                        .get("segment_id")
                        .and_then(Value::as_u64)
                        .ok_or("payload.segment_id is required")?,
                );
                match payload.get("time_ms") {
                    None | Some(Value::Null) => project.clear_user_final(id)?,
                    Some(value) => project.set_user_final(
                        id,
                        value.as_u64().ok_or("payload.time_ms must be a number")?,
                    )?,
                }
                project.save(path)?;
                Ok(Value::Null)
            }
            "credits" => {
                let path = payload_path(payload, "project_path")?;
                let mut project = SongProject::load(path)?;
                let result = match payload_text(payload, "action")? {
                    "layout" => json!({
                        "status": match layout_credit_cues(&mut project)? {
                            CreditLayout::Arranged => "arranged",
                            CreditLayout::IntroTooShort => "intro_too_short",
                        }
                    }),
                    "merge" => {
                        merge_credits(&mut project)?;
                        Value::Null
                    }
                    "set_time" => {
                        set_credit_time(
                            &mut project,
                            CreditId(
                                payload
                                    .get("credit_id")
                                    .and_then(Value::as_u64)
                                    .ok_or("payload.credit_id is required")?,
                            ),
                            payload
                                .get("time_ms")
                                .and_then(Value::as_u64)
                                .ok_or("payload.time_ms must be a number")?,
                        )?;
                        Value::Null
                    }
                    other => return Err(format!("unknown credits action: {other}").into()),
                };
                project.save(path)?;
                Ok(result)
            }
            "validate" => {
                SongProject::load(payload_path(payload, "project_path")?)?;
                Ok(json!({"valid": true}))
            }
            "retarget" => {
                let path = payload_path(payload, "project_path")?;
                let mut project = SongProject::load(path)?;
                replace_target_audio(&mut project, payload_path(payload, "target_path")?)?;
                project.save(path)?;
                Ok(Value::Null)
            }
            "replace_lyrics" => {
                let path = payload_path(payload, "project_path")?;
                let mut project = SongProject::load(path)?;
                replace_project_lyrics(
                    &mut project,
                    payload_text(payload, "original")?,
                    payload.get("translation").and_then(Value::as_str),
                )?;
                project.save(path)?;
                Ok(Value::Null)
            }
            "insert_lyrics" => {
                let path = payload_path(payload, "project_path")?;
                let mut project = SongProject::load(path)?;
                let after = match payload.get("after_line_id") {
                    None | Some(Value::Null) => None,
                    Some(value) => Some(LineId(
                        value
                            .as_u64()
                            .ok_or("payload.after_line_id must be a number")?,
                    )),
                };
                let inserted =
                    insert_project_lyrics(&mut project, after, payload_text(payload, "text")?)?;
                project.save(path)?;
                Ok(json!({
                    "inserted": inserted.iter().map(|id| id.0).collect::<Vec<_>>()
                }))
            }
            "fetch_lyrics" => {
                let path = payload_path(payload, "project_path")?;
                let mut project = SongProject::load(path)?;
                let music_id = project
                    .source
                    .as_ref()
                    .and_then(|source| source.music_id)
                    .ok_or("project has no NetEase musicId")?;
                let lyrics = fetch_netease_lyrics(music_id)?;
                replace_project_lyrics(
                    &mut project,
                    &lyrics.original,
                    lyrics.translation.as_deref(),
                )?;
                project.save(path)?;
                Ok(Value::Null)
            }
            "replace_translations" => {
                let path = payload_path(payload, "project_path")?;
                let mut project = SongProject::load(path)?;
                let applied =
                    apply_line_translations(&mut project, payload_text(payload, "translation")?)?;
                project.save(path)?;
                Ok(json!({
                    "applied": applied,
                    "lines": project.lyrics.lines.len(),
                }))
            }
            "translate" => {
                crate::translate_project_with_config(
                    payload_path(payload, "project_path")?,
                    payload_text(payload, "provider")?,
                    payload_text(payload, "api_key")?.to_owned(),
                    payload
                        .get("model")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    payload.get("target_language").and_then(Value::as_str),
                )?;
                Ok(Value::Null)
            }
            "align" => {
                let ids = payload
                    .get("segment_ids")
                    .and_then(Value::as_array)
                    .map(|ids| {
                        ids.iter()
                            .map(|id| {
                                id.as_u64()
                                    .map(SegmentId)
                                    .ok_or("segment_ids must contain integers")
                            })
                            .collect::<Result<Vec<_>, _>>()
                    })
                    .transpose()?;
                crate::align_project_with_config(
                    payload_path(payload, "project_path")?,
                    ids.as_deref().filter(|ids| !ids.is_empty()),
                    payload_text(payload, "provider")?,
                    payload_text(payload, "api_key")?.to_owned(),
                    payload
                        .get("model")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                )?;
                Ok(Value::Null)
            }
            "restore_gemini" => {
                let path = payload_path(payload, "project_path")?;
                let mut project = SongProject::load(path)?;
                project.restore_gemini_timeline();
                project.save(path)?;
                Ok(Value::Null)
            }
            "export" => {
                let result = export_mp3(
                    &SongProject::load(payload_path(payload, "project_path")?)?,
                    payload_path(payload, "output_path")?,
                    payload_bool(payload, "overwrite"),
                )?;
                Ok(
                    json!({"mp3": result.mp3_path, "lrc": result.lrc_path, "audio_sha256": result.audio_sha256}),
                )
            }
            "audio_viz" => Ok(run_audio_viz(payload)?),
            "list_audio_viz_adapters" => Ok(json!({ "adapters": list_audio_viz_adapters() })),
            "list_export_adapters" => Ok(serde_json::to_value(list_export_adapters())?),
            "export_cuesheet" => {
                let output = payload_path(payload, "output_path")?;
                fs::write(
                    output,
                    render_cuesheet_json(&SongProject::load(payload_path(
                        payload,
                        "project_path",
                    )?)?)?,
                )?;
                Ok(json!({"cuesheet": output}))
            }
            _ => Err(format!("unknown RPC command: {}", request.command).into()),
        }
    };
    run().map_err(|error| {
        let message = error.to_string();
        let code = if message.contains("unknown RPC command") {
            "unknown_command"
        } else if message.contains("HTTP 401") || message.contains("HTTP 403") {
            "authentication"
        } else if message.contains("HTTP 429") || message.to_lowercase().contains("quota") {
            "quota"
        } else if message.contains("already exists") {
            "already_exists"
        } else {
            "core_error"
        };
        (code, message)
    })
}

fn payload_text<'a>(payload: &'a Value, field: &str) -> Result<&'a str, Box<dyn Error>> {
    payload
        .get(field)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("payload.{field} is required").into())
}

fn payload_bool(payload: &Value, field: &str) -> bool {
    payload.get(field).and_then(Value::as_bool).unwrap_or(false)
}

fn payload_path<'a>(payload: &'a Value, field: &str) -> Result<&'a Path, Box<dyn Error>> {
    payload_text(payload, field).map(Path::new)
}

fn rpc_failure(request_id: String, code: &'static str, message: String) -> RpcResponse {
    RpcResponse {
        request_id,
        ok: false,
        result: None,
        error: Some(RpcError { code, message }),
    }
}
