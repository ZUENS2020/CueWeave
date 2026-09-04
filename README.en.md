# CueWeave

CueWeave transfers song metadata and lyrics onto another vocal or mix, then rebuilds lyric timing against the target audio.

- [中文 README](README.md)
- [Cue Sheet player plugin contract](docs/CUE_SHEET.md)
- [Audio visualization adapters](docs/AUDIO_VIZ.md)
- [UI changes and pending acceptance](docs/UI_INTERACTION_OFFLINE_2026-09-04.md)
- [CI builds and releases](docs/CI_RELEASE.md)
- [Suzuka-inspired icon and native resources](apps/shared/branding/README.md)

License: [AGPL-3.0-only](LICENSE)

**macOS 14+** and **Windows 11 x64** (WinUI 3) are supported.

## Download

Current release **v0.2.0**: [GitHub Releases](https://github.com/ZUENS2020/CueWeave/releases/latest)

Choose the ZIP matching your processor. Unzip and run; no extra .NET / Rust / Swift install.

| OS | File | How to run |
| --- | --- | --- |
| macOS 14+ Apple Silicon | `CueWeave-0.2.0-macos-arm64.zip` | Unzip to get `CueWeave.app`. |
| macOS 14+ Intel | `CueWeave-0.2.0-macos-x86_64.zip` | Unzip to get `CueWeave.app`. |
| Windows 11 x64 | `CueWeave-0.2.0-windows-x64.zip` | Unzip to get a `CueWeave` folder, then run `CueWeave.Windows.exe` inside it. Do not copy the exe out of that folder. |

CI builds include SHA-256 checksums. macOS is ad-hoc signed and not notarized; Windows is not trusted-code-signed. OS security prompts may appear.
CI is not interactive device acceptance; see the [release notes](docs/RELEASE_v0.2.0.md).

## What it does

```text
Original NCM (information source) + target MP3 (only timing authority)
  → metadata draft
  → fetch and normalize lyric text
  → optional translation (originals and timing stay untouched)
  → Gemini re-times against the target
  → manually adjusted Final times
  → copy the target MP3, tags only, plus lyrics / Cue Sheet
```

Invariants:

- Lyric sources answer “what is sung”. Provider timestamps are destroyed before they enter the project.
- The target MP3 is the only timing authority.
- Gemini is the only automatic aligner. Waveform, spectrogram, and band energy are visual only.
- Gemini suggestions and Final times are stored separately. Re-running Align does not overwrite manually set Finals; there is no per-line review state.
- Export copies the MPEG payload and SHA-256-checks it. No re-encode, and the target audio file is never overwritten.
- Rust Core owns business rules. macOS and Windows GUIs display, play, and capture input.

## Workflow

1. **New project** from the original `.ncm` and target `.mp3`; save a `.cueweave` file.
2. **Source**: inspect the information source and timing authority. Replacing the target invalidates Gemini and Final while keeping lyrics and the metadata draft.
3. **Metadata**: Source / Target are read-only; only Draft is exported.
4. **Lyrics**: fetch by NetEase music ID, import text, or insert lines. Timestamps are stripped.
5. **Translation** (optional): Gemini via the same Align key, import text, or edit per line. No audio upload.
6. **Alignment**: Run Gemini, then edit Finals on the timeline. Credits can auto-layout in the intro or be stamped by hand.
7. **Export**: choose LRC / USLT / SYLT and bilingual mode. **Export Final** writes a new MP3. **Save Cue Sheet** writes player-plugin JSON.

## Importing lyrics

All three Lyrics-page entry points share one normalizer:

| Entry | Effect |
| --- | --- |
| Fetch by NetEase music ID | Keep `lrc` / `tlyric` text only; timestamps are gone before the project is written |
| **Import Text…** | Replace originals, credits, and the timeline |
| **Insert** | Insert at the start, or after a chosen row; existing IDs and Finals stay |

UTF-8, optional BOM. Blank lines are ignored. Consecutive identical sung lines collapse into one.

### What is stripped

| Form | Example | Result |
| --- | --- | --- |
| LRC line time | `[00:08.450]`, `[00:08.45]` | Drop the tag, keep the words |
| Enhanced LRC inline time | `<00:08.450>` | Dropped |
| YRC / NetEase word-line header | `[10750,500]` (start ms, duration) | Dropped |
| YRC word parens | `(8450,300,0)` | Dropped |
| LRC file headers | `[ar:]` `[al:]` `[ti:]` `[by:]` `[offset:]` `[re:]` `[ve:]` | Whole line discarded |
| NetEase JSON glyph blocks | `{"c":[{"tx":"朝焼けに"}]}` | Join every `tx` |

**No** source timing is stored. Every later timestamp is a Final on the target MP3.

### Credit lines

After timestamps are stripped, a line `Label：Name` or `Label:Name` becomes a Credit (not a sung line) when the label is one of:

`作词` `作詞` `作曲` `编曲` `編曲` `词` `詞` `曲` `Lyricist` `Composer` `Arranger`

**Insert** does not split credits; those lines are inserted as ordinary lyrics.

### Examples

Plain text:

```text
朝焼けに ほどける
僕らのシルエット
```

LRC (times are discarded):

```text
[ar:Example]
[00:00.000]作词：MOMIKEN
[00:08.450]朝焼けに ほどける
[00:10.750]僕らのシルエット
```

Mixed YRC / enhanced LRC:

```text
[00:08.450]<00:08.450>朝焼けに (8450,300,0)ほどける
[10750,500](10750,250,0)僕らの
```

The project keeps two sung lines (`朝焼けに ほどける`, `僕らの`) plus credit `作词：MOMIKEN`. Each line is currently one segment.

### CLI

```sh
cueweave-cli lyrics song.cueweave original.txt
cueweave-cli lyrics song.cueweave original.txt translation.txt
```

## Importing translations

1. **Translate with Gemini** — same OpenRouter / AI Studio key, model, and HTTP path as Align; text only; one request for the whole song, ordered by line ID.
2. **Import Text…** — bind by the current original **line order**.
3. **Per-line editing**.

The Alignment inspector shows translation read-only.

Same cleaning as lyrics: UTF-8, LRC/YRC tags stripped, blank lines ignored.

Does **not** change originals, Finals, the timeline, or credits. Extra translation lines are dropped; originals without a matching line stay untranslated.

```text
[00:08.45]在朝霞中舒展
[00:10.75]我们的剪影
```

If the project has three originals, only the first two get translations.

```sh
cueweave-cli translations song.cueweave translation.txt
```

Defaults: AI Studio `gemini-3.7-flash`, OpenRouter `google/gemini-3.7-flash`. Align uploads accept target MP3s up to 14 MiB; larger files can still be timed and exported offline.

## Keyboard shortcuts

Timeline keys apply on the **Alignment** page while the timeline has focus. They do not apply inside a text field — click empty timeline space to leave the field.

A timeline click seeks only; it does not select a lyric. Select with a left-list row click, Return, or Tab.

### File and edit

| Action | macOS | Windows |
| --- | --- | --- |
| New / Open / Save | ⌘N / ⌘O / ⌘S | Ctrl+N / Ctrl+O / Ctrl+S |
| Undo / Redo | ⌘Z / ⇧⌘Z | Ctrl+Z / Ctrl+Shift+Z (or Ctrl+Y) |

### Alignment

| Key | Action |
| --- | --- |
| Space | Play / pause |
| Return | Select the playing lyric |
| Tab / ⇧Tab | Select the lyric after / before the playhead |
| N | Toggle “keep next lyric selected” (toolbar Next) |
| ↑ / ↓ | Move selection |
| ← / → | Seek by 1% of the visible time span |
| Home / End | Jump to start / end |
| 1 + ← / → | Nudge Final by 1 ms |
| 2 + ← / → | Nudge Final by 10 ms |
| 3 + ← / → | Nudge Final by 50 ms |
| `,` / `.` | Nudge Final by 1 ms |
| M | Stamp Final at the playhead |
| Delete (Backspace on Windows too) | Clear Final |
| A / B | Loop start / end |
| Esc | Clear A-B loop |
| `=` / `-` | Playback rate 0.50×–2.00× (pitch preserved) |
| ⌘= / ⌘− (Windows: Ctrl+= / Ctrl+-) | Timeline zoom |
| Pinch, or Ctrl+wheel on Windows | Timeline zoom |

**Follow** keeps the viewport on the playhead. **Next** (off by default, shortcut **N**) keeps selection on the lyric *after* the playhead (same as Tab). Manual selection turns Next off; only Tab (next lyric) keeps it on.

Lyric inspector: **Play two seconds before**, **Use Gemini**. Credits can still be stamped on the timeline.

## Export

**Export Final** copies the target MP3, writes ID3v2.4, optionally writes lyrics, then SHA-256-checks that the MPEG payload did not change.

Default name: `{title} [CueWeave].mp3`. A matching `.lrc` is written beside it when LRC is enabled.

| Option | Meaning |
| --- | --- |
| Overwrite existing output | On by default. Replaces the chosen MP3 and matching LRC. The save panel also confirms Replace when the file already exists |
| Protects target audio | The output path must not be the project’s target MP3 |
| Export offset | Applied only to export times and the Cue Sheet, not to Finals in the project |

| Built-in adapter | Kind | Content |
| --- | --- | --- |
| `lrc` | Sidecar `.lrc` | Synced lines from Cue Sheet `events` (including Credit / Spacer) |
| `uslt` | ID3 USLT | Concatenates `lyric` events only (Game Size omits unsung full-length lyrics) |
| `sylt` | ID3 SYLT | Synced tags from the same `events` |

Bilingual:

- `original_only` — original text only.
- `bilingual` — a second LRC line at the same timestamp; a second USLT/SYLT frame (original `lang=und`, translation `lang=zho`, description `translation`). Never `original / translation` on one line.

Lines without a Final still appear in Cue Sheet `lines` (`start_ms: null`) but do not emit a `lyric` event, so they are omitted from LRC / USLT / SYLT. Export is not disabled for missing Finals.

```sh
cueweave-cli export song.cueweave "song [CueWeave].mp3"
cueweave-cli export song.cueweave "song [CueWeave].mp3" --overwrite
```

## Player plugins

Do **not** read `.cueweave` or re-parse Finals.

The stable input is **Cue Sheet JSON** (`schema_version: 1`):

| Entry | Command |
| --- | --- |
| Export page | Save Cue Sheet… |
| CLI | `cueweave-cli cuesheet song.cueweave song.cuesheet.json` |
| RPC | `export_cuesheet` |

Times in the JSON already include `offset_ms`. A plugin only renders that snapshot as KRC, TTML, NetEase, Apple Music, Aegisub, or any other player format.

There is **no** dylib / WASM loader. In-process Rust adapters implement `PlayerExportAdapter`; out-of-process tools read the JSON. Fields, event types, and adapter duties: [docs/CUE_SHEET.md](docs/CUE_SHEET.md).

## Audio visualization

The two generic audio lanes pick a builtin adapter (Peak / RMS / Peak+RMS / Band Energy / three spectrograms). Display only; it does not change timing. New waveforms implement `AudioVizAdapter` and appear in RPC `list_audio_viz_adapters`; the GUI dispatches on `surface` + `series`. Contract: [docs/AUDIO_VIZ.md](docs/AUDIO_VIZ.md).

## API keys

Plain local JSON. Not Keychain / Credential Manager. Not stored in the project.

| Platform | Path |
| --- | --- |
| macOS | `~/Library/Application Support/CueWeave/config.json` (dir 700, file 600) |
| Windows | `%LOCALAPPDATA%\CueWeave\settings.json` |

## Interface language

Settings can follow the system, or lock to English or Simplified Chinese. Systems whose language code starts with `zh` default to Chinese. The choice is stored in the same local config file and applies immediately.

## Packaging

[GitHub Actions CI](https://github.com/ZUENS2020/CueWeave/actions/workflows/ci.yml) is the default for builds, tests and packages; version tags publish only after all checks pass.
No personal Mac or Windows acceptance host needs to be online. See [CI builds and releases](docs/CI_RELEASE.md); local commands below remain a maintenance fallback.

macOS (quit fully before reopening `dist/CueWeave.app`):

```sh
./scripts/package-macos.sh
open dist/CueWeave.app
```

Windows 11 x64 (run on Windows; over SSH use the repo script so rustup shims in `.cargo\bin` are not on PATH):

```powershell
.\scripts\package-windows.ps1
```

Publish output is self-contained (.NET runtime, Windows App SDK, and `cueweave-cli.exe` are inside the folder; users do not install extra runtimes):

- Folder: `dist/CueWeave-windows-x64\` (run `CueWeave.Windows.exe` here for desktop checks)
- Zip: `dist/CueWeave-windows-x64.zip` (extracts to one `CueWeave` folder; do not copy the exe out)

Open `CueWeave.Windows.exe` in an interactive desktop session. Starting it over SSH lands in Session 0.

The macOS `.app` likewise bundles the Swift binary, `cueweave-cli`, and `l10n.json`. Versions are locked by `Cargo.lock`, `apps/macos/Package.resolved`, and `apps/windows/**/packages.lock.json`; builds use `--locked`.

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

```sh
cueweave-cli create song.cueweave source.ncm target.mp3
cueweave-cli translate song.cueweave
cueweave-cli cuesheet song.cueweave song.cuesheet.json
cueweave-cli export song.cueweave "song [CueWeave].mp3" --overwrite
```

The GUI talks to Core through `cueweave-cli rpc`, protocol version 1.

Internal notes: [implementation plan](docs/IMPLEMENTATION_PLAN.md), [UI completion audit](docs/UI_COMPLETION_AUDIT.md).
