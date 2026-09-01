use cueweave_core::{
    AiStudioConfig, OpenRouterConfig, SegmentId, SongProject, align_with_ai_studio,
    align_with_openrouter, apply_alignment_response, apply_alignment_response_selected,
    apply_line_translations, apply_translation_response, download_cover, export_mp3,
    fetch_netease_lyrics, inspect_ncm, list_export_adapters, project_from_files,
    render_cuesheet_json, render_lrc, replace_project_lyrics, replace_target_audio,
    translate_with_ai_studio, translate_with_openrouter,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::error::Error;
use std::ffi::OsString;
use std::fs;
use std::io::{Read, Write};
use std::path::Path;

const RPC_PROTOCOL_VERSION: u32 = 1;

#[derive(Deserialize)]
struct RpcRequest {
    protocol_version: u32,
    request_id: String,
    command: String,
    #[serde(default)]
    payload: Value,
}

#[derive(Serialize)]
struct RpcResponse {
    request_id: String,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<RpcError>,
}

#[derive(Serialize)]
struct RpcError {
    code: &'static str,
    message: String,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("cueweave: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    let arguments: Vec<_> = std::env::args_os().skip(1).collect();
    let Some(command) = arguments.first().and_then(|argument| argument.to_str()) else {
        return usage();
    };

    match (command, &arguments[1..]) {
        ("rpc", []) => run_rpc()?,
        ("new", [output]) => SongProject::default().save(output)?,
        ("create", [project_path, source_path, target_path]) => {
            create_project_file(project_path, source_path, target_path)?;
        }
        ("inspect-ncm", [input]) => {
            let info = inspect_ncm(input)?;
            println!(
                "{}",
                serde_json::to_string_pretty(&serde_json::json!({
                    "music_id": info.music_id,
                    "metadata": info.metadata,
                    "cover_url": info.cover_url,
                    "format": info.format,
                    "duration_ms": info.duration_ms,
                    "embedded_cover_bytes": info.cover.as_ref().map_or(0, |cover| cover.data.len()),
                }))?
            );
        }
        ("validate", [input]) => {
            let project = SongProject::load(input)?;
            println!("{}", serde_json::to_string_pretty(&project.status())?);
        }
        ("round-trip", [input, output]) => SongProject::load(input)?.save(output)?,
        ("lyrics", [project_path, original_path]) => {
            replace_lyrics(project_path, original_path, None)?;
        }
        ("lyrics", [project_path, original_path, translation_path]) => {
            replace_lyrics(project_path, original_path, Some(translation_path))?;
        }
        ("translations", [project_path, translation_path]) => {
            let mut project = SongProject::load(project_path)?;
            apply_line_translations(&mut project, &fs::read_to_string(translation_path)?)?;
            project.save(project_path)?;
        }
        ("fetch-lyrics", [project_path]) => {
            let mut project = SongProject::load(project_path)?;
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
            project.save(project_path)?;
        }
        ("set-duration", [project_path, duration]) => {
            let mut project = SongProject::load(project_path)?;
            let target = project
                .target
                .as_mut()
                .ok_or("project has no target audio")?;
            target.duration_ms = Some(parse_u64(duration, "duration")?);
            project.save(project_path)?;
        }
        ("retarget", [project_path, target_path]) => {
            let mut project = SongProject::load(project_path)?;
            replace_target_audio(&mut project, target_path)?;
            project.save(project_path)?;
        }
        ("set-final", [project_path, segment_id, time_ms]) => {
            let mut project = SongProject::load(project_path)?;
            project.set_user_final(
                cueweave_core::SegmentId(parse_u64(segment_id, "segment id")?),
                parse_u64(time_ms, "time")?,
            )?;
            project.save(project_path)?;
        }
        ("align", [project_path]) => {
            align_project(project_path, None)?;
        }
        ("align-selected", [project_path, ids]) => {
            let selected = parse_ids(ids)?;
            align_project(project_path, Some(&selected))?;
        }
        ("restore-gemini", [project_path]) => {
            let mut project = SongProject::load(project_path)?;
            project.restore_gemini_timeline();
            project.save(project_path)?;
        }
        ("translate", [project_path]) => {
            translate_project(project_path, None)?;
        }
        ("lrc", [project_path, output]) => {
            fs::write(output, render_lrc(&SongProject::load(project_path)?)?)?;
        }
        ("cuesheet", [project_path, output]) => {
            fs::write(
                output,
                render_cuesheet_json(&SongProject::load(project_path)?)?,
            )?;
        }
        ("export", [project_path, output]) => {
            let result = export_mp3(&SongProject::load(project_path)?, output)?;
            println!(
                "{}",
                serde_json::to_string_pretty(&serde_json::json!({
                    "mp3": result.mp3_path,
                    "lrc": result.lrc_path,
                    "audio_sha256": result.audio_sha256,
                }))?
            );
        }
        _ => return usage(),
    }
    Ok(())
}

fn replace_lyrics(
    project_path: &OsString,
    original_path: &OsString,
    translation_path: Option<&OsString>,
) -> Result<(), Box<dyn Error>> {
    let mut project = SongProject::load(project_path)?;
    let original = fs::read_to_string(original_path)?;
    let translation = translation_path.map(fs::read_to_string).transpose()?;
    replace_project_lyrics(&mut project, &original, translation.as_deref())?;
    project.save(project_path)?;
    Ok(())
}

fn parse_u64(value: &OsString, name: &str) -> Result<u64, Box<dyn Error>> {
    value
        .to_str()
        .ok_or_else(|| format!("{name} is not UTF-8"))?
        .parse()
        .map_err(|_| format!("invalid {name}").into())
}

fn parse_ids(value: &OsString) -> Result<Vec<SegmentId>, Box<dyn Error>> {
    let text = value.to_str().ok_or("segment IDs are not UTF-8")?;
    text.split(',')
        .map(|id| {
            id.parse::<u64>()
                .map(SegmentId)
                .map_err(|_| format!("invalid segment ID: {id}").into())
        })
        .collect()
}

fn align_project(
    project_path: &OsString,
    selected: Option<&[SegmentId]>,
) -> Result<(), Box<dyn Error>> {
    let provider =
        std::env::var("CUEWEAVE_ALIGNMENT_PROVIDER").unwrap_or_else(|_| "openrouter".into());
    let (api_key, model) = match provider.as_str() {
        "openrouter" => (
            std::env::var("OPENROUTER_API_KEY").map_err(|_| "OPENROUTER_API_KEY is not set")?,
            std::env::var("OPENROUTER_MODEL").ok(),
        ),
        "ai_studio" => (
            std::env::var("GEMINI_API_KEY").map_err(|_| "GEMINI_API_KEY is not set")?,
            std::env::var("GEMINI_MODEL").ok(),
        ),
        _ => return Err(format!("unsupported alignment provider: {provider}").into()),
    };
    align_project_with_config(project_path, selected, &provider, api_key, model)
}

fn align_project_with_config(
    project_path: impl AsRef<Path>,
    selected: Option<&[SegmentId]>,
    provider: &str,
    api_key: String,
    model: Option<String>,
) -> Result<(), Box<dyn Error>> {
    let project_path = project_path.as_ref();
    let mut project = SongProject::load(project_path)?;
    let response = match provider {
        "openrouter" => {
            let mut config = OpenRouterConfig::new(api_key);
            if let Some(model) = model {
                config.model = model;
            }
            align_with_openrouter(&project, &config)?
        }
        "ai_studio" => {
            let mut config = AiStudioConfig::new(api_key);
            if let Some(model) = model {
                config.model = model;
            }
            align_with_ai_studio(&project, &config)?
        }
        _ => return Err(format!("unsupported alignment provider: {provider}").into()),
    };
    if let Some(ids) = selected {
        apply_alignment_response_selected(&mut project, &response, ids)?;
    } else {
        apply_alignment_response(&mut project, &response)?;
    }
    project.save(project_path)?;
    Ok(())
}

fn translate_project(
    project_path: &OsString,
    target_language: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    let provider =
        std::env::var("CUEWEAVE_ALIGNMENT_PROVIDER").unwrap_or_else(|_| "openrouter".into());
    let (api_key, model) = match provider.as_str() {
        "openrouter" => (
            std::env::var("OPENROUTER_API_KEY").map_err(|_| "OPENROUTER_API_KEY is not set")?,
            std::env::var("OPENROUTER_MODEL").ok(),
        ),
        "ai_studio" => (
            std::env::var("GEMINI_API_KEY").map_err(|_| "GEMINI_API_KEY is not set")?,
            std::env::var("GEMINI_MODEL").ok(),
        ),
        _ => return Err(format!("unsupported alignment provider: {provider}").into()),
    };
    translate_project_with_config(project_path, &provider, api_key, model, target_language)
}

fn translate_project_with_config(
    project_path: impl AsRef<Path>,
    provider: &str,
    api_key: String,
    model: Option<String>,
    target_language: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    let project_path = project_path.as_ref();
    let mut project = SongProject::load(project_path)?;
    let response = match provider {
        "openrouter" => {
            let mut config = OpenRouterConfig::new(api_key);
            if let Some(model) = model {
                config.model = model;
            }
            translate_with_openrouter(&project, &config, target_language)?
        }
        "ai_studio" => {
            let mut config = AiStudioConfig::new(api_key);
            if let Some(model) = model {
                config.model = model;
            }
            translate_with_ai_studio(&project, &config, target_language)?
        }
        _ => return Err(format!("unsupported alignment provider: {provider}").into()),
    };
    apply_translation_response(&mut project, &response)?;
    project.save(project_path)?;
    Ok(())
}

fn create_project_file(
    project_path: impl AsRef<Path>,
    source_path: impl AsRef<Path>,
    target_path: impl AsRef<Path>,
) -> Result<(), Box<dyn Error>> {
    let project_path = project_path.as_ref();
    let (mut project, info) = project_from_files(source_path, target_path, None)?;
    let cover = info.cover.or_else(|| {
        info.cover_url
            .as_deref()
            .and_then(|url| download_cover(url).ok())
    });
    if let Some(cover) = cover {
        let extension = if cover.mime_type == "image/png" {
            "cover.png"
        } else {
            "cover.jpg"
        };
        let cover_path = project_path.with_extension(extension);
        fs::write(&cover_path, cover.data)?;
        project.metadata.source.cover_path = Some(cover_path.clone());
        project.metadata.draft.cover_path = Some(cover_path);
    }
    project.save(project_path)?;
    Ok(())
}

fn run_rpc() -> Result<(), Box<dyn Error>> {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input)?;
    let response = rpc_response(&input);
    let stdout = std::io::stdout();
    let mut output = stdout.lock();
    serde_json::to_writer(&mut output, &response)?;
    output.write_all(b"\n")?;
    Ok(())
}

fn rpc_response(input: &str) -> RpcResponse {
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
                create_project_file(
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
                let project = SongProject::from_json(
                    &payload
                        .get("project")
                        .ok_or("payload.project is required")?
                        .to_string(),
                )?;
                project.save(payload_path(payload, "project_path")?)?;
                Ok(Value::Null)
            }
            "validate" => Ok(serde_json::to_value(
                SongProject::load(payload_path(payload, "project_path")?)?.status(),
            )?),
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
                translate_project_with_config(
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
                align_project_with_config(
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
                )?;
                Ok(
                    json!({"mp3": result.mp3_path, "lrc": result.lrc_path, "audio_sha256": result.audio_sha256}),
                )
            }
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

fn usage<T>() -> Result<T, Box<dyn Error>> {
    Err("usage: cueweave-cli <rpc|new|create|inspect-ncm|validate|round-trip|lyrics|translations|fetch-lyrics|retarget|set-duration|set-final|align|align-selected|translate|restore-gemini|lrc|cuesheet|export> ...".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rpc_ping_and_protocol_errors_use_one_envelope() {
        let ping = rpc_response(
            r#"{"protocol_version":1,"request_id":"p1","command":"ping","payload":{}}"#,
        );
        assert!(ping.ok);
        assert_eq!(ping.request_id, "p1");

        let unsupported =
            rpc_response(r#"{"protocol_version":2,"request_id":"p2","command":"ping"}"#);
        assert!(!unsupported.ok);
        assert_eq!(unsupported.error.unwrap().code, "unsupported_protocol");
    }

    #[test]
    fn rpc_never_echoes_api_keys_in_errors() {
        let response = rpc_response(
            r#"{"protocol_version":1,"request_id":"secret","command":"missing","payload":{"api_key":"never-print-this"}}"#,
        );
        let json = serde_json::to_string(&response).unwrap();
        assert!(!json.contains("never-print-this"));
        assert!(json.contains("unknown_command"));
    }
}
