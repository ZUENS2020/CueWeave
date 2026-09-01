# CueWeave

CueWeave transfers song metadata and lyrics to another vocal or mix, then
rebuilds the lyric timing against the target audio.

- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [UI completion audit and acceptance baseline](docs/UI_COMPLETION_AUDIT.md)

## Development

```sh
cargo test --workspace --all-targets
swift build --package-path apps/macos
./scripts/check-budget.sh P2
```

Build the self-contained macOS app (macOS 14 or newer):

```sh
./scripts/package-macos.sh
open dist/CueWeave.app
```

CueWeave keeps source lyric timestamps out of the project, sends the complete
normalized lyric block to the selected model without automatically splitting
lines on spaces, aligns only against the target MP3, and writes a tagged copy
without re-encoding its MPEG payload.

## MVP workflow

1. Open CueWeave and create a project from the original NCM and target MP3.
2. Fetch lyrics by the NCM music ID or import text/LRC/YRC manually.
3. Choose AI Studio or OpenRouter in Settings, add the corresponding API key,
   run Gemini alignment, then adjust Final times with
   Mark, six timing buttons, or the `1/2/3 + Left/Right` chords. Space plays and
   pauses; Return selects the playing lyric; Tab selects the next lyric after
   the playhead. The timeline has no draggable
   Final marker, and local signal analysis never changes timing.
   Plain Left/Right moves the playhead by 1% of the currently visible time span. Playback
   speed uses AVAudioUnitTimePitch presets from 0.50× to 2.00× without changing pitch.
4. Review metadata, choose LRC/USLT/SYLT and bilingual options, then export a
   new MP3. The target file is never overwritten.

Provider settings and both API keys are stored locally at
`~/Library/Application Support/CueWeave/config.json` with owner-only
permissions. CueWeave does not access macOS Keychain.

The inline providers default to `gemini-3.7-flash` on AI Studio and
`google/gemini-3.7-flash` on OpenRouter. They accept target MP3 files up to
14 MiB. Larger files can
still use the complete offline timing and export workflow.
