#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(dirname -- "$script_dir")

if [ "${CUEWEAVE_SKIP_SWIFT_TESTS:-0}" != "1" ]; then
    swift test --package-path "$repo_dir/apps/macos" --disable-automatic-resolution
fi

timeline_view="$repo_dir/apps/macos/Sources/CueWeaveMac/TimelineView.swift"
alignment_page="$repo_dir/apps/macos/Sources/CueWeaveMac/AlignmentPage.swift"
controller="$repo_dir/apps/macos/Sources/CueWeaveMac/TimelineInteractionController.swift"
pointer_surface="$repo_dir/apps/macos/Sources/CueWeaveMac/TimelinePointerSurface.swift"
native_scroll="$repo_dir/apps/macos/Sources/CueWeaveMac/TimelineNativeScrollView.swift"
segment_row="$repo_dir/apps/macos/Sources/CueWeaveMac/SegmentQueueRow.swift"
audio_workspace="$repo_dir/apps/macos/Sources/CueWeaveMac/AudioWorkspace.swift"
design_system="$repo_dir/apps/macos/Sources/CueWeaveMac/DesignSystem.swift"

if rg -q 'finalMarker|DragGesture|onTapGesture|player\.seek' "$timeline_view"; then
    echo "TimelineView still contains a direct seek or draggable/clickable marker" >&2
    exit 1
fi
if rg -q 'shiftFinals' "$alignment_page"; then
    echo "AlignmentPage still exposes batch timing shifts" >&2
    exit 1
fi
if rg -q 'Picker\("Mode"|AlignmentMode|reviewInspector|timingInspector|lyricsInspector' "$alignment_page"; then
    echo "AlignmentPage still contains split inspector modes" >&2
    exit 1
fi
if rg -q 'onTapGesture\(count: 2' "$segment_row"; then
    echo "lyric rows still require a double-click for manual selection" >&2
    exit 1
fi
if ! rg -q 'contentShape\(Rectangle' "$segment_row"; then
    echo "lyric row click target is not the full box" >&2
    exit 1
fi
if ! rg -q 'onTapGesture\(perform: onSelect\)' "$segment_row"; then
    echo "lyric rows are not single-click selectable" >&2
    exit 1
fi
if rg -Fq 'selectSegment(atFraction' "$controller" || rg -Fq 'lane == .lyrics' "$controller"; then
    echo "timeline clicks still select lyrics instead of seeking" >&2
    exit 1
fi
if ! rg -Fq 'lyricPlayingFill' "$segment_row" || ! rg -Fq 'lyricSelectedFill' "$segment_row"; then
    echo "lyric row highlight is not using the shared light-blue pair" >&2
    exit 1
fi
if ! rg -Fq 'lyricPlayingFill' "$timeline_view" || ! rg -Fq 'lyricSelectedFill' "$timeline_view"; then
    echo "timeline lyric lane is not using the same selection fills as the sidebar" >&2
    exit 1
fi
if sed -n '/func playheadDidChange()/,/^    }/p' "$controller" | rg -q 'selectedSegmentID' \
    && ! sed -n '/func playheadDidChange()/,/^    }/p' "$controller" | rg -q 'followSelection'; then
    echo "playback highlighting still overwrites manual selection" >&2
    exit 1
fi
if ! rg -q 'leftMouseDown' "$alignment_page" || ! rg -q 'resignInspectorFocus' "$alignment_page"; then
    echo "text fields cannot be dismissed by clicking empty space" >&2
    exit 1
fi
if ! rg -q 'followSelection' "$controller" || ! rg -q 'followingSegmentID' "$controller"; then
    echo "lyric selection cannot follow the next line after the playhead" >&2
    exit 1
fi
if ! rg -q 'breakFollowSelection' "$controller" || ! rg -q 'keepsFollowSelection' "$controller"; then
    echo "Next follow is not cancelled by manual lyric selection" >&2
    exit 1
fi
if ! rg -q 'addLocalMonitorForEvents' "$alignment_page"; then
    echo "Alignment keyboard is not using a local NSEvent monitor" >&2
    exit 1
fi
if ! rg -q 'TimelineKeyChordState' "$alignment_page" "$controller" "$repo_dir/apps/macos/Sources/CueWeaveMac/TimelineInteractionCore.swift"; then
    echo "1/2/3 held chords are not owned by the focused Timeline key state" >&2
    exit 1
fi
if rg -q 'keyDown\(with' "$pointer_surface" || rg -q 'addLocalMonitorForEvents' "$pointer_surface"; then
    echo "Timeline still installs a native keyboard monitor or view-level keyDown" >&2
    exit 1
fi
if ! rg -q 'NSScrollView' "$native_scroll" || ! rg -q 'NSHostingView' "$native_scroll"; then
    echo "Timeline is not hosted by the native AppKit scroll component" >&2
    exit 1
fi
if rg -q 'ScrollView\(\.horizontal\)' "$timeline_view" || rg -q 'DispatchWorkItem|frameDidChangeNotification' "$controller"; then
    echo "legacy SwiftUI scrolling or asynchronous zoom correction is still active" >&2
    exit 1
fi
if ! rg -q 'documentGeometryDidChange' "$native_scroll" || ! rg -q 'documentGeometryDidChange' "$controller"; then
    echo "native document resize and zoom anchoring are not one transaction" >&2
    exit 1
fi
if ! rg -q 'documentAnchor: zoomAnchorFraction' "$controller" || ! rg -q 'playheadFraction' "$controller"; then
    echo "zoom inputs are not anchored to the current playback timestamp" >&2
    exit 1
fi
if ! rg -q 'canvasTileCount' "$timeline_view"; then
    echo "zoomed waveform is still drawn as one document-sized Canvas" >&2
    exit 1
fi
if ! rg -q 'CADisplayLink' "$audio_workspace" || ! rg -q 'forMode: \.common' "$audio_workspace"; then
    echo "playback UI clock is not synchronized to the display common run loop" >&2
    exit 1
fi
if ! rg -q 'preferredFrameRateRange' "$audio_workspace"; then
    echo "display link is not requesting a high frame-rate range" >&2
    exit 1
fi
if ! rg -q 'PlaybackDisplayClock' "$audio_workspace"; then
    echo "playhead is still following raw AVAudioPlayer currentTime" >&2
    exit 1
fi
if rg -q '@Published.*currentTime|PlaybackTickBridge' "$audio_workspace" "$alignment_page"; then
    echo "per-frame playback must not invalidate transport views or defer follow-scroll through SwiftUI" >&2
    exit 1
fi
if ! rg -Fq 'CATransaction.setDisableActions(true)' "$repo_dir/apps/macos/Sources/CueWeaveMac/PlaybackPresentation.swift" \
    || ! rg -Fq 'TimelineWaveformLanes' "$timeline_view"; then
    echo "native frame transaction or isolated static waveform is missing" >&2
    exit 1
fi
if ! rg -q 'AVAudioPlayer' "$audio_workspace" || ! rg -q 'enableRate = true' "$audio_workspace"; then
    echo "system pitch-preserving rate playback is not configured" >&2
    exit 1
fi
if rg -q 'AVAudioEngine|AVAudioPlayerNode|systemUptime' "$audio_workspace"; then
    echo "legacy engine scheduling or derived playback clock is still active" >&2
    exit 1
fi
if ! rg -q '\.lineLimit\(1\)' "$design_system" || ! rg -q '\.minimumScaleFactor' "$design_system"; then
    echo "timing readouts can wrap under constrained width" >&2
    exit 1
fi
for label in 'Button("−50")' 'Button("−10")' 'Button("−1")' 'Button("+1")' 'Button("+10")' 'Button("+50")'; do
    if ! rg -Fq "$label" "$alignment_page"; then
        echo "AlignmentPage is missing timing control: $label" >&2
        exit 1
    fi
done
echo "timeline view interaction boundary OK"
