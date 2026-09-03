use crate::{Credit, CreditId, Cue, ProjectError, SongProject};

pub const CREDIT_SAFETY_MARGIN_MS: u64 = 500;
const CREDIT_MIN_INTERVAL_MS: u64 = 1_500;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CreditLayout {
    Arranged,
    IntroTooShort,
}

pub fn assign_credit_ids(credits: &mut [Credit]) -> Result<(), ProjectError> {
    let mut next = credits.iter().map(|credit| credit.id.0).max().unwrap_or(0);
    for credit in credits {
        if credit.id.0 == 0 {
            next = next
                .checked_add(1)
                .ok_or_else(|| ProjectError::Invariant("id space exhausted".into()))?;
            credit.id = CreditId(next);
        }
    }
    Ok(())
}

pub fn sync_credit_cues(project: &mut SongProject) {
    let ids: Vec<_> = project
        .lyrics
        .credits
        .iter()
        .map(|credit| credit.id)
        .collect();
    project.timeline.retain(|cue| match cue {
        Cue::Credit { credit_id, .. } => ids.contains(credit_id),
        _ => true,
    });
    let existing: Vec<_> = project
        .timeline
        .iter()
        .filter_map(|cue| match cue {
            Cue::Credit { credit_id, .. } => Some(*credit_id),
            _ => None,
        })
        .collect();
    let mut insert_at = 0;
    for id in ids {
        if existing.contains(&id) {
            continue;
        }
        project.timeline.insert(
            insert_at,
            Cue::Credit {
                credit_id: id,
                time_ms: 0,
            },
        );
        insert_at += 1;
    }
}

pub fn sort_credit_cues(project: &mut SongProject) {
    let mut credits = Vec::new();
    let mut rest = Vec::new();
    for cue in project.timeline.drain(..) {
        match cue {
            Cue::Credit { .. } => credits.push(cue),
            other => rest.push(other),
        }
    }
    credits.sort_by_key(|cue| match cue {
        Cue::Credit { time_ms, credit_id } => (*time_ms, credit_id.0),
        _ => (0, 0),
    });
    credits.append(&mut rest);
    project.timeline = credits;
}

pub fn credits_need_layout(project: &SongProject) -> bool {
    let times: Vec<u64> = project
        .timeline
        .iter()
        .filter_map(|cue| match cue {
            Cue::Credit { time_ms, .. } => Some(*time_ms),
            _ => None,
        })
        .collect();
    times.len() >= 2 && times.iter().all(|time| *time == 0)
}

pub fn first_lyric_time_ms(project: &SongProject) -> Option<u64> {
    project.lyrics.lines.iter().find_map(|line| {
        line.segments.iter().find_map(|segment| {
            segment
                .timing
                .final_point
                .or(segment.timing.gemini)
                .map(|point| point.time_ms)
        })
    })
}

pub fn layout_credit_cues(project: &mut SongProject) -> Result<CreditLayout, ProjectError> {
    assign_credit_ids(&mut project.lyrics.credits)?;
    sync_credit_cues(project);
    let count = project.lyrics.credits.len();
    if count == 0 {
        return Ok(CreditLayout::Arranged);
    }
    let Some(first_lyric) = first_lyric_time_ms(project) else {
        return Ok(CreditLayout::Arranged);
    };
    let available = first_lyric.saturating_sub(CREDIT_SAFETY_MARGIN_MS);
    if count >= 2 && available / (count as u64) < CREDIT_MIN_INTERVAL_MS {
        set_all_credit_times(project, 0);
        return Ok(CreditLayout::IntroTooShort);
    }
    if count == 1 || available == 0 {
        set_all_credit_times(project, 0);
        return Ok(CreditLayout::Arranged);
    }
    let interval = available / count as u64;
    let duration = project
        .target
        .as_ref()
        .and_then(|target| target.duration_ms);
    let ids: Vec<_> = project
        .lyrics
        .credits
        .iter()
        .map(|credit| credit.id)
        .collect();
    for (index, id) in ids.into_iter().enumerate() {
        let mut time = nice_time(index as u64 * interval);
        if let Some(duration) = duration {
            time = time.min(duration);
        }
        set_credit_time_raw(project, id, time);
    }
    sort_credit_cues(project);
    Ok(CreditLayout::Arranged)
}

pub fn add_credit(
    project: &mut SongProject,
    label: impl Into<String>,
    value: impl Into<String>,
) -> Result<CreditId, ProjectError> {
    let id = CreditId(next_credit_id(project)?);
    project.lyrics.credits.push(Credit {
        id,
        label: label.into(),
        value: value.into(),
    });
    sync_credit_cues(project);
    Ok(id)
}

pub fn set_credit_time(
    project: &mut SongProject,
    id: CreditId,
    time_ms: u64,
) -> Result<(), ProjectError> {
    if !project.lyrics.credits.iter().any(|credit| credit.id == id) {
        return Err(ProjectError::NotFound("credit", id.0));
    }
    if let Some(duration) = project
        .target
        .as_ref()
        .and_then(|target| target.duration_ms)
        && time_ms > duration
    {
        return Err(ProjectError::Invariant(format!(
            "credit {} is past target duration",
            id.0
        )));
    }
    sync_credit_cues(project);
    set_credit_time_raw(project, id, time_ms);
    sort_credit_cues(project);
    Ok(())
}

pub fn merge_credits(project: &mut SongProject) -> Result<(), ProjectError> {
    if project.lyrics.credits.len() < 2 {
        return Ok(());
    }
    let merged = project
        .lyrics
        .credits
        .iter()
        .map(Credit::display_text)
        .filter(|text| !text.is_empty())
        .collect::<Vec<_>>()
        .join(" / ");
    let id = project.lyrics.credits[0].id;
    project.lyrics.credits = vec![Credit {
        id,
        label: String::new(),
        value: merged,
    }];
    sync_credit_cues(project);
    set_credit_time_raw(project, id, 0);
    sort_credit_cues(project);
    Ok(())
}

pub fn credit_time_ms(project: &SongProject, id: CreditId) -> Option<u64> {
    project.timeline.iter().find_map(|cue| match cue {
        Cue::Credit { credit_id, time_ms } if *credit_id == id => Some(*time_ms),
        _ => None,
    })
}

fn set_all_credit_times(project: &mut SongProject, time_ms: u64) {
    for cue in &mut project.timeline {
        if let Cue::Credit { time_ms: slot, .. } = cue {
            *slot = time_ms;
        }
    }
}

fn set_credit_time_raw(project: &mut SongProject, id: CreditId, time_ms: u64) {
    for cue in &mut project.timeline {
        if let Cue::Credit {
            credit_id,
            time_ms: slot,
        } = cue
            && *credit_id == id
        {
            *slot = time_ms;
        }
    }
}

fn nice_time(ms: u64) -> u64 {
    ((ms + 250) / 500) * 500
}

fn next_credit_id(project: &SongProject) -> Result<u64, ProjectError> {
    project
        .lyrics
        .credits
        .iter()
        .map(|credit| credit.id.0)
        .max()
        .unwrap_or(0)
        .checked_add(1)
        .ok_or_else(|| ProjectError::Invariant("id space exhausted".into()))
}
