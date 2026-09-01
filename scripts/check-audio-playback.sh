#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")

swift test --package-path "$repo_dir/apps/macos" --filter AudioPlaybackTests
