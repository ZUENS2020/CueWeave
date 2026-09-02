#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(dirname -- "$SCRIPT_DIR")
ZIP_PATH="$REPO_DIR/dist/CueWeave-macOS.zip"
STAGING_DIR=$(mktemp -d /tmp/cueweave-package.XXXXXX)
STAGED_APP="$STAGING_DIR/CueWeave.app"
VERIFY_DIR="$STAGING_DIR/verify"
MACOS_DIR="$STAGED_APP/Contents/MacOS"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT HUP INT TERM

cd "$REPO_DIR"
cargo build --locked --release -p cueweave-cli
swift build -c release --package-path apps/macos --disable-automatic-resolution

mkdir -p "$MACOS_DIR"
cp apps/macos/Info.plist "$STAGED_APP/Contents/Info.plist"
cp apps/macos/.build/release/CueWeaveMac "$MACOS_DIR/CueWeave"
cp apps/shared/l10n.json "$MACOS_DIR/l10n.json"
cp target/release/cueweave-cli "$MACOS_DIR/cueweave-cli"
chmod 755 "$MACOS_DIR/CueWeave" "$MACOS_DIR/cueweave-cli"
xattr -cr "$STAGED_APP"
codesign --force --deep --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

mkdir -p "$REPO_DIR/dist"
rm -f "$ZIP_PATH"
rm -rf "$REPO_DIR/dist/CueWeave.app"
ditto "$STAGED_APP" "$REPO_DIR/dist/CueWeave.app"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr --noqtn "$STAGED_APP" "$ZIP_PATH"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/CueWeave.app"
test -x "$VERIFY_DIR/CueWeave.app/Contents/MacOS/CueWeave"
test -x "$VERIFY_DIR/CueWeave.app/Contents/MacOS/cueweave-cli"
test -f "$VERIFY_DIR/CueWeave.app/Contents/MacOS/l10n.json"
printf '%s' '{"protocol_version":1,"request_id":"package-smoke","command":"ping","payload":{}}' \
    | "$VERIFY_DIR/CueWeave.app/Contents/MacOS/cueweave-cli" rpc \
    | jq -e '.ok == true and .result.protocol_version == 1' >/dev/null

echo "$ZIP_PATH"
