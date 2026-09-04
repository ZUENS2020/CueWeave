#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")
store="$repo_dir/apps/macos/Sources/CueWeaveMac/ProjectStore.swift"
app="$repo_dir/apps/macos/Sources/CueWeaveMac/CueWeaveApp.swift"

if [ "${CUEWEAVE_SKIP_SWIFT_TESTS:-0}" != "1" ]; then
    swift test --package-path "$repo_dir/apps/macos" --disable-automatic-resolution --filter ProjectPortabilityTests
fi
rg -q 'ReferenceFileDocument' "$store"
rg -q 'DocumentGroup' "$app"
rg -q 'UndoManager' "$store"
if rg -q '\.autosave|undoStack|redoStack|autosaveTask' "$store"; then
    echo "legacy autosave or snapshot history is still present" >&2
    exit 1
fi
echo "document lifecycle and system UndoManager boundary OK"
