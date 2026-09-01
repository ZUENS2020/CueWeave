#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(dirname -- "$SCRIPT_DIR")
APP_PATH="${1:-$REPO_DIR/dist/CueWeave.app}"

if [ ! -x "$APP_PATH/Contents/MacOS/CueWeave" ]; then
    echo "missing app: $APP_PATH" >&2
    exit 1
fi

killall CueWeave 2>/dev/null || true
sleep 0.4
rm -rf "$HOME/Library/Saved Application State/dev.cueweave.app.savedState"

open "$APP_PATH"
sleep 2.4

RESULT=$(swift -e '
import CoreGraphics
import Foundation

let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var windows: [[String: Any]] = []
for entry in info {
    let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
    guard owner == "CueWeave" else { continue }
    let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let width = bounds["Width"] ?? 0
    let height = bounds["Height"] ?? 0
    guard width >= 80, height >= 80 else { continue }
    windows.append([
        "title": entry[kCGWindowName as String] as? String ?? "",
        "width": width,
        "height": height,
    ])
}

func emit(_ status: String, _ reason: String) {
    print("STATUS=\(status)")
    print("REASON=\(reason)")
    for window in windows {
        let title = window["title"] as? String ?? ""
        let width = window["width"] as? CGFloat ?? 0
        let height = window["height"] as? CGFloat ?? 0
        print(String(format: "WINDOW title=%@ size=%.0fx%.0f", title as NSString, width, height))
    }
}

if windows.isEmpty {
    emit("FAIL", "no CueWeave window")
    exit(0)
}

let panelTitles: Set<String> = ["Open", "打开"]
let panel = windows.first { window in
    let title = window["title"] as? String ?? ""
    let height = window["height"] as? CGFloat ?? 0
    let width = window["width"] as? CGFloat ?? 0
    if title.hasPrefix("Choose the original") { return true }
    if panelTitles.contains(title) { return true }
    return height >= 400 && height <= 520 && width >= 780 && width <= 980
}

if let panel {
    let title = panel["title"] as? String ?? ""
    let width = panel["width"] as? CGFloat ?? 0
    let height = panel["height"] as? CGFloat ?? 0
    emit("FAIL", String(format: "file panel on launch title=%@ size=%.0fx%.0f", title as NSString, width, height))
    exit(0)
}

let welcome = windows.first { window in
    (window["height"] as? CGFloat ?? 0) >= 650
}

guard welcome != nil else {
    emit("FAIL", "no welcome-sized window")
    exit(0)
}

emit("PASS", "untitled welcome window")
')

printf '%s\n' "$RESULT"
echo "$RESULT" | grep -q '^STATUS=PASS$'

dump_windows() {
    swift -e '
import CoreGraphics
import Foundation
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for entry in info {
    let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
    guard owner == "CueWeave" else { continue }
    let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let width = bounds["Width"] ?? 0
    let height = bounds["Height"] ?? 0
    guard width >= 80, height >= 80 else { continue }
    let title = entry[kCGWindowName as String] as? String ?? ""
    print(String(format: "WINDOW title=%@ size=%.0fx%.0f", title as NSString, width, height))
}
'
}

click_toolbar() {
    osascript -e "tell application \"System Events\" to tell process \"CueWeave\" to click button \"$1\" of toolbar 1 of window 1" 2>/dev/null ||
    osascript -e "tell application \"System Events\" to tell process \"CueWeave\" to click (first button of toolbar 1 of window 1 whose description contains \"$1\")" 2>/dev/null ||
    true
}

osascript -e 'tell application "System Events" to tell process "CueWeave" to set frontmost to true' >/dev/null 2>&1 || true
sleep 0.3
click_toolbar "Open Project"
sleep 1.2
OPEN_WINDOWS=$(dump_windows)
printf '%s\n' "$OPEN_WINDOWS"
echo "$OPEN_WINDOWS" | grep -q 'title=Open Project' || {
    echo "STATUS=FAIL"
    echo "REASON=Open Project panel did not stay open"
    killall CueWeave 2>/dev/null || true
    exit 1
}

osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
sleep 0.4
click_toolbar "New Project"
sleep 1.2
NEW_WINDOWS=$(dump_windows)
printf '%s\n' "$NEW_WINDOWS"
echo "$NEW_WINDOWS" | grep -q 'Choose the original' || {
    echo "STATUS=FAIL"
    echo "REASON=New Project file panel did not stay open"
    killall CueWeave 2>/dev/null || true
    exit 1
}

osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
killall CueWeave 2>/dev/null || true
echo "STATUS=PASS"
echo "REASON=welcome plus Open/New panels stay open"
