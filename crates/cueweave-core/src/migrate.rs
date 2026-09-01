use crate::{CURRENT_SCHEMA_VERSION, ProjectError};
use serde_json::{Value, json};

pub fn migrate_project_value(value: &mut Value) -> Result<(), ProjectError> {
    let version = value
        .get("schema_version")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    if version == 0 {
        return Err(ProjectError::UnsupportedSchema(0));
    }
    if version <= 2 {
        migrate_credits_v3(value);
        value["schema_version"] = json!(CURRENT_SCHEMA_VERSION);
    }
    Ok(())
}

fn migrate_credits_v3(value: &mut Value) {
    let Some(credits) = value
        .pointer_mut("/lyrics/credits")
        .and_then(Value::as_array_mut)
    else {
        return;
    };
    let mut next_id = credits
        .iter()
        .filter_map(|credit| credit.get("id").and_then(Value::as_u64))
        .max()
        .unwrap_or(0);
    let mut by_text = Vec::new();
    for credit in credits.iter_mut() {
        let id = credit.get("id").and_then(Value::as_u64).unwrap_or(0);
        let assigned = if id == 0 {
            next_id += 1;
            credit["id"] = json!(next_id);
            next_id
        } else {
            id
        };
        let label = credit
            .get("label")
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim();
        let value_text = credit
            .get("value")
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim();
        let text = if label.is_empty() {
            value_text.to_owned()
        } else {
            format!("{label}：{value_text}")
        };
        by_text.push((text, assigned));
    }
    let credit_ids: Vec<u64> = credits
        .iter()
        .filter_map(|credit| credit.get("id").and_then(Value::as_u64))
        .collect();
    let Some(timeline) = value.get_mut("timeline").and_then(Value::as_array_mut) else {
        return;
    };
    let mut kept = Vec::new();
    let mut seen = Vec::new();
    for cue in timeline.drain(..) {
        let Some(kind) = cue.get("type").and_then(Value::as_str) else {
            kept.push(cue);
            continue;
        };
        if kind != "credit" {
            kept.push(cue);
            continue;
        }
        let Some(credit_id) = cue
            .get("credit_id")
            .and_then(Value::as_u64)
            .or_else(|| {
                let text = cue.get("text").and_then(Value::as_str)?.trim();
                by_text
                    .iter()
                    .find(|(display, _)| display == text)
                    .map(|(_, id)| *id)
            })
            .filter(|id| credit_ids.contains(id))
        else {
            continue;
        };
        if seen.contains(&credit_id) {
            continue;
        }
        seen.push(credit_id);
        let time_ms = cue.get("time_ms").and_then(Value::as_u64).unwrap_or(0);
        kept.push(json!({
            "type": "credit",
            "credit_id": credit_id,
            "time_ms": time_ms,
        }));
    }
    let mut missing = Vec::new();
    for id in credit_ids {
        if !seen.contains(&id) {
            missing.push(json!({
                "type": "credit",
                "credit_id": id,
                "time_ms": 0,
            }));
        }
    }
    missing.append(&mut kept);
    *timeline = missing;
}
