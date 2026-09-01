# CueWeave

CueWeave transfers song metadata and lyrics onto another vocal or mix, then rebuilds lyric timing against the target audio.

- [中文 README](README.md)
- [Cue Sheet player adapter contract](docs/CUE_SHEET.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [UI completion audit](docs/UI_COMPLETION_AUDIT.md)

License: [AGPL-3.0-only](LICENSE)

## What it does

```text
Original NCM (information source) + target MP3 (only timing authority)
  → metadata draft
  → fetch and normalize lyric text
  → optional translation (originals and timing stay untouched)
  → Gemini re-times against the target
  → human-confirmed Final
  → copy the target MP3, tags only, plus lyrics
```

Invariants:

- Lyric sources answer “what is sung”. Provider timestamps are destroyed before they enter the project.
- The target MP3 is the only timing authority.
- Gemini is the only automatic aligner. Waveform and band energy are visual only.
- Gemini suggestions and Final times are stored separately. Re-running Align does not overwrite confirmed Finals.
- Export copies the MPEG payload and SHA-256-checks it. No re-encode, no overwrite of the target file.
- Rust Core owns business rules. macOS and Windows GUIs display, play, and capture input.

**macOS 14+** and **Windows 11 x64** (WinUI 3) are supported.

## Workflow

1. **New project** from the original `.ncm` and target `.mp3`; save a `.cueweave` file.
2. **Source**: inspect the information source and timing authority. Replacing the target invalidates Gemini and Final while keeping lyrics and the metadata draft.
3. **Metadata**: Source / Target are read-only; only Draft is exported.
4. **Lyrics**: fetch by NetEase music ID, import text / LRC / YRC, or insert lines between existing ones. Timestamps are stripped.
5. **Translation** (optional): Gemini via the same Align key, import text, or edit per line. No audio upload.
6. **Alignment**: Run Gemini, then edit Finals on the timeline.
7. **Export**: choose LRC / USLT / SYLT and bilingual mode. **Export Final** writes a new MP3. **Save Cue Sheet** writes player-plugin JSON.

## Alignment shortcuts

A timeline click seeks only; it does not select a lyric. Select with a left-list row click, Return, or Tab.

| Key | Action |
| --- | --- |
| Space | Play / pause |
| Return | Select the playing lyric |
| Tab / ⇧Tab | Select the lyric after / before the playhead |
| ↑ / ↓ | Move selection |
| ← / → | Seek by 1% of the visible time span |
| 1 / 2 / 3 + ← / → | Nudge Final by 1 / 10 / 50 ms |
| Esc | Clear A-B loop |
| `=` / `-` | Playback rate 0.50×–2.00× (pitch preserved) |
| ⌘= / ⌘− (Windows: Ctrl+= / Ctrl+-) | Timeline zoom |
| A / B | Loop start / end |
| M | Stamp Final at the playhead |
| Delete | Clear Final |

**Follow** keeps the viewport on the playhead. **Next** (off by default) keeps selection on the lyric *after* the playhead (same as Tab). Manual selection turns Next off; only Tab (next lyric) keeps it on.

## Translation

1. **Translate with Gemini** — same OpenRouter / AI Studio key, model, and HTTP path as Align; text only; one request for the whole song, ordered by line ID.
2. **Import Text** — bind by line order; strip LRC; originals and timing unchanged.
3. **Per-line editing** on the Translation page.

The Alignment inspector shows translation read-only. Defaults: AI Studio `gemini-3.7-flash`, OpenRouter `google/gemini-3.7-flash`. Align uploads accept target MP3s up to 14 MiB; larger files can still be timed and exported offline.

## Export and player plugins

**Export Final** copies the target MP3 and writes ID3v2.4, then:

| Adapter | Kind | Role |
| --- | --- | --- |
| `lrc` | Sidecar `.lrc` | Synced lyrics (including Credit / Spacer) |
| `uslt` | Embedded ID3 | Static lyrics |
| `sylt` | Embedded ID3 | Synced lyrics |

Bilingual: `original_only`, or `bilingual` (a second LRC line at the same timestamp; a second USLT/SYLT frame — never `original / translation` on one line). `offset_ms` applies only at export.

Future player plugins must consume Cue Sheet JSON (`schema_version: 1`), not the `.cueweave` project file. See [docs/CUE_SHEET.md](docs/CUE_SHEET.md).

## API keys

Plain local JSON. Not Keychain / Credential Manager. Not stored in the project.

| Platform | Path |
| --- | --- |
| macOS | `~/Library/Application Support/CueWeave/config.json` (dir 700, file 600) |
| Windows | `%LOCALAPPDATA%\CueWeave\settings.json` |

## Interface language

Settings can follow the system, or lock to English or Simplified Chinese. Systems whose language code starts with `zh` default to Chinese. The choice is stored in the same local config file and applies immediately.

## Packaging

macOS (quit fully before reopening `dist/CueWeave.app`):

```sh
./scripts/package-macos.sh
open dist/CueWeave.app
```

Windows 11 x64 (run on Windows; over SSH use the repo script so rustup shims in `.cargo\bin` are not on PATH):

```powershell
.\scripts\package-windows.ps1
```

Publish directory:

`apps/windows/CueWeave.Windows/bin/Release/net10.0-windows10.0.26100.0/win-x64/publish\`

Open `CueWeave.Windows.exe` in an interactive desktop session. Starting it over SSH lands in Session 0.

## Development

```sh
cargo test --workspace --all-targets
./scripts/check-budget.sh P4
swift test --package-path apps/macos
./scripts/check-timeline-interaction.sh
```

Do not use `dotnet test` for the WinUI test project (MTP reports 0 tests). Run the exe:

```powershell
dotnet build apps\windows\CueWeave.Windows.Tests\CueWeave.Windows.Tests.csproj
.\apps\windows\CueWeave.Windows.Tests\bin\Debug\net10.0\CueWeave.Windows.Tests.exe
```

CLI:

```sh
cueweave-cli create song.cueweave source.ncm target.mp3
cueweave-cli translate song.cueweave
cueweave-cli cuesheet song.cueweave song.cuesheet.json
cueweave-cli export song.cueweave "song [CueWeave].mp3"
```

The GUI talks to Core through `cueweave-cli rpc`, protocol version 1.
