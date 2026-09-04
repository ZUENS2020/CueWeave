#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")

if [ "${CUEWEAVE_SKIP_SWIFT_TESTS:-0}" != "1" ]; then
    swift test --package-path "$repo_dir/apps/macos" --disable-automatic-resolution --filter LocalSettingsTests
fi

bridge="$repo_dir/apps/macos/Sources/CueWeaveMac/CoreBridge.swift"
store="$repo_dir/apps/macos/Sources/CueWeaveMac/ProjectStore.swift"
if ! rg -q 'process\.arguments = \["rpc"\]' "$bridge" || ! rg -q 'process\.standardInput = input' "$bridge"; then
    echo "macOS bridge is not using the versioned stdin RPC" >&2
    exit 1
fi
if rg -q 'OPENROUTER_API_KEY|GEMINI_API_KEY|temporaryDirectory' "$store"; then
    echo "API keys or lyrics still leave the local RPC payload boundary" >&2
    exit 1
fi
echo "local settings and RPC secret boundary OK"
