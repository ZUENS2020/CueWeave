import CoreGraphics
import Testing
@testable import CueWeaveMac

@Suite("Timeline interaction")
struct TimelineInteractionTests {
    @Test("Click and drag split at four points")
    func pointerEvents() {
        let start = TimelinePointerSample(documentFraction: 0.10, viewportFraction: 0.25)
        var pointer = TimelinePointerStateMachine()
        pointer.begin(at: start, x: 100)
        #expect(pointer.drag(to: .init(documentFraction: 0.103, viewportFraction: 0.253), x: 103) == nil)
        guard case let .click(sample)? = pointer.end(at: .init(documentFraction: 0.103, viewportFraction: 0.253)) else {
            Issue.record("Sub-threshold drag must emit one click")
            return
        }
        #expect(close(sample.documentFraction, 0.103))
        #expect(sample.lane == .waveform)

        let lyricClick = TimelinePointerSample(documentFraction: 0.40, viewportFraction: 0.40, lane: .lyrics)
        pointer.begin(at: lyricClick, x: 200)
        guard case let .click(lyricSample)? = pointer.end(at: lyricClick) else {
            Issue.record("Lyric-lane click must remain a click, not a range zoom")
            return
        }
        #expect(lyricSample.lane == .lyrics)

        pointer.begin(at: start, x: 100)
        guard case let .selectionChanged(preview)? = pointer.drag(
            to: .init(documentFraction: 0.30, viewportFraction: 0.45), x: 104
        ) else {
            Issue.record("Four-point drag must begin selection")
            return
        }
        #expect(preview == 0.10 ... 0.30)
        guard case let .selectionCommitted(committed)? = pointer.end(
            at: .init(documentFraction: 0.35, viewportFraction: 0.50)
        ) else {
            Issue.record("Selection must commit on mouse-up")
            return
        }
        #expect(committed == 0.10 ... 0.35)

        pointer.begin(at: start, x: 100, credit: 7)
        #expect(
            pointer.drag(to: .init(documentFraction: 0.20, viewportFraction: 0.35), x: 150)
                == .creditDrag(id: 7, fraction: 0.20)
        )
        #expect(pointer.end(at: .init(documentFraction: 0.22, viewportFraction: 0.37)) == nil)

        pointer.begin(at: start, x: 100, credit: 7)
        guard case let .click(creditClick)? = pointer.end(at: start) else {
            Issue.record("Unmoved credit press must remain a click")
            return
        }
        #expect(close(creditClick.documentFraction, 0.10))
    }

    @Test("Coordinates cover a complete 149.091-second document")
    func coordinateMapping() {
        let duration = 149.091
        for (x, width, expected): (CGFloat, CGFloat, Double) in [
            (100, 1_000, 14.9091),
            (1_000, 2_000, 74.5455),
            (10_800, 12_000, 134.1819),
        ] {
            #expect(close(
                duration * TimelineInteractionMath.fraction(at: x, width: width),
                expected,
                tolerance: 0.000_1
            ))
        }
        #expect(TimelineInteractionMath.fraction(at: -50, width: 1_000) == 0)
        #expect(TimelineInteractionMath.fraction(at: 1_050, width: 1_000) == 1)
    }

    @Test("Zoom keeps the chosen timestamp at viewport center")
    func zoomGeometry() {
        for (zoom, anchor, expected): (CGFloat, CGFloat, CGFloat) in [
            (1, 500, 0),
            (2, 1_000, 500),
            (12, 6_000, 5_500),
            (64, 32_000, 31_500),
        ] {
            #expect(TimelineInteractionMath.scrollOrigin(
                anchorX: anchor,
                viewportAnchor: 0.5,
                viewportWidth: 1_000,
                documentMinX: 0,
                documentMaxX: 1_000 * zoom
            ) == expected)
        }
        #expect(TimelineInteractionMath.documentWidth(viewportWidth: 1_000, zoom: 12) == 12_000)
        #expect(TimelineInteractionMath.rangeZoom(0.20 ... 0.66) == 2)
        #expect(TimelineInteractionMath.rangeZoom(0.20 ... 0.21) == 64)
        #expect(TimelineInteractionMath.playheadFraction(
            currentTime: 74.5455, duration: 149.091, fallback: 0
        ) == 0.5)
    }

    @Test("Waveform and band energy split the flexible height")
    func layout() {
        for height: CGFloat in [350, 600, 900] {
            let layout = TimelineLayoutMetrics(totalHeight: height)
            #expect(layout.waveform == layout.bands)
            #expect(layout.lyricTop + TimelineLayoutMetrics.lyrics == height)
        }
        #expect(TimelineLayoutMetrics.ruler == 24)
        #expect(TimelineLayoutMetrics.lyrics == 72)
        let layout = TimelineLayoutMetrics(totalHeight: 350)
        #expect(TimelineLayoutMetrics.lane(at: 0, height: 350) == .ruler)
        #expect(TimelineLayoutMetrics.lane(at: layout.bandTop - 1, height: 350) == .waveform)
        #expect(TimelineLayoutMetrics.lane(at: layout.bandTop, height: 350) == .bands)
        #expect(TimelineLayoutMetrics.lane(at: layout.lyricTop - 1, height: 350) == .bands)
        #expect(TimelineLayoutMetrics.lane(at: layout.lyricTop, height: 350) == .lyrics)
        #expect(TimelineLayoutMetrics.lane(at: 349, height: 350) == .lyrics)
    }

    @Test("Each audio lane can show any visualization kind")
    func audioLanesCombineFreely() {
        var lanes = AudioLaneSettings()
        #expect(lanes.upper == .peak)
        #expect(lanes.lower == .bands)
        #expect(lanes.neededScales.isEmpty)
        lanes.upper = .specLog
        lanes.lower = .peakRms
        #expect(lanes.neededScales == [.log])
        lanes.lower = .specMel
        #expect(Set(lanes.neededScales) == [.log, .mel])
        lanes.upper = .rms
        lanes.lower = .bands
        #expect(lanes.neededScales.isEmpty)
    }

    @Test("High-zoom canvases split before the Retina rasterization cap")
    func canvasTilesCoverAZoomedDocument() {
        #expect(TimelineInteractionMath.canvasTileCount(documentWidth: 1_000) == 1)
        #expect(TimelineInteractionMath.canvasTileCount(documentWidth: 2_048) == 1)
        #expect(TimelineInteractionMath.canvasTileCount(documentWidth: 2_049) == 2)
        let zoomed = TimelineInteractionMath.documentWidth(viewportWidth: 930, zoom: 40.3)
        #expect(zoomed > 8_192)
        let tiles = TimelineInteractionMath.canvasTileCount(documentWidth: zoomed)
        #expect(tiles >= 10)
        var covered = 0..<0
        for index in 0..<tiles {
            let frame = TimelineInteractionMath.canvasTileFrame(index: index, documentWidth: zoomed)
            #expect(frame.width <= TimelineInteractionMath.canvasTileWidth)
            let bins = TimelineInteractionMath.canvasTileBins(
                tileOrigin: frame.origin,
                tileWidth: frame.width,
                documentWidth: zoomed,
                binCount: 4_096
            )
            #expect(!bins.isEmpty)
            if covered.isEmpty {
                covered = bins
            } else {
                covered = covered.lowerBound..<max(covered.upperBound, bins.upperBound)
            }
        }
        #expect(covered == 0..<4_096)
    }

    @Test("Lyric-lane clicks cover the same boxes drawn on the timeline")
    func lyricLaneCoveringSegment() {
        let points: [(id: UInt64, timeMS: UInt64)] = [
            (1, 0),
            (2, 10_000),
            (3, 20_000),
        ]
        #expect(TimelineInteractionMath.coveringSegmentID(timeMS: 0, points: points, durationMS: 30_000) == 1)
        #expect(TimelineInteractionMath.coveringSegmentID(timeMS: 9_999, points: points, durationMS: 30_000) == 1)
        #expect(TimelineInteractionMath.coveringSegmentID(timeMS: 10_000, points: points, durationMS: 30_000) == 2)
        #expect(TimelineInteractionMath.coveringSegmentID(timeMS: 20_000, points: points, durationMS: 30_000) == 3)
        #expect(TimelineInteractionMath.coveringSegmentID(timeMS: 30_000, points: points, durationMS: 30_000) == 3)
        #expect(TimelineInteractionMath.coveringSegmentID(timeMS: 5_000, points: [], durationMS: 30_000) == nil)
        #expect(TimelineInteractionMath.coveringSegmentID(
            timeMS: 4_000,
            points: [(id: 9, timeMS: 8_000)],
            durationMS: 30_000
        ) == nil)
    }

    @Test("Follow-next selection stays one lyric ahead of the playhead")
    func followingSegmentID() {
        let ids: [UInt64] = [1, 2, 3]
        #expect(TimelineInteractionMath.followingSegmentID(activeID: nil, orderedIDs: ids) == 1)
        #expect(TimelineInteractionMath.followingSegmentID(activeID: 1, orderedIDs: ids) == 2)
        #expect(TimelineInteractionMath.followingSegmentID(activeID: 2, orderedIDs: ids) == 3)
        #expect(TimelineInteractionMath.followingSegmentID(activeID: 3, orderedIDs: ids) == 3)
        #expect(TimelineInteractionMath.followingSegmentID(activeID: 9, orderedIDs: ids) == 1)
        #expect(TimelineInteractionMath.followingSegmentID(activeID: 1, orderedIDs: []) == nil)
        #expect(TimelineInteractionMath.keepsFollowSelection(relativeOffset: 1))
        #expect(!TimelineInteractionMath.keepsFollowSelection(relativeOffset: -1))
        #expect(!TimelineInteractionMath.keepsFollowSelection(relativeOffset: 0))
    }

    @Test("Current follow has a dedicated keyboard toggle")
    func currentFollowHotkey() {
        var translator = TimelineHotkeyTranslator()
        let input = TimelineHotkeyInput(
            keyCode: 8,
            characters: "c",
            command: false,
            shift: false,
            option: false,
            control: false,
            isKeyUp: false,
            isRepeat: false
        )
        #expect(translator.translate(input) == .toggleFollowCurrentSelection)
        var repeated = input
        repeated.isRepeat = true
        #expect(translator.translate(repeated) == .consume)
    }

    @Test("Playback cue lookup is cached, ordered, and handles equal timestamps")
    func playbackCueIndex() {
        let segments = [
            LyricSegment(id: 3, text: "C", timing: SegmentTiming(gemini: AlignmentPoint(timeMS: 2_000, confidence: nil), finalPoint: nil)),
            LyricSegment(id: 1, text: "A", timing: SegmentTiming(gemini: AlignmentPoint(timeMS: 1_000, confidence: nil), finalPoint: nil)),
            LyricSegment(id: 2, text: "B", timing: SegmentTiming(gemini: AlignmentPoint(timeMS: 1_000, confidence: nil), finalPoint: AlignmentPoint(timeMS: 1_500, confidence: nil))),
            LyricSegment(id: 4, text: "D", timing: SegmentTiming(gemini: nil, finalPoint: nil)),
        ]
        var index = PlaybackCueIndex(segments: segments)
        #expect(index.orderedIDs == [3, 1, 2, 4])
        #expect(index.timed.map(\.id) == [1, 2, 3])
        #expect(index.activeID(at: 999) == nil)
        #expect(index.activeID(at: 1_000) == 1)
        #expect(index.activeID(at: 1_500) == 2)
        #expect(index.activeID(at: 9_000) == 3)
        #expect(index.followingID(after: 1) == 2)

        index.rebuild(segments: Array(segments.prefix(2)))
        #expect(index.orderedIDs == [3, 1])
        #expect(index.activeID(at: 1_500) == 1)
    }

    @Test("Timing chords and plain arrows have correct direction and scale")
    func keyboardMath() {
        #expect(TimelineInteractionMath.nudgeStep(forKeyCode: 18) == 1)
        #expect(TimelineInteractionMath.nudgeStep(forKeyCode: 19) == 10)
        #expect(TimelineInteractionMath.nudgeStep(forKeyCode: 20) == 50)
        for step: Int64 in [1, 10, 50] {
            #expect(TimelineInteractionMath.nudged(1_000, by: -step, maximum: 2_000) == 1_000 - UInt64(step))
            #expect(TimelineInteractionMath.nudged(1_000, by: step, maximum: 2_000) == 1_000 + UInt64(step))
        }
        #expect(TimelineInteractionMath.nudged(10, by: -50, maximum: 2_000) == 0)
        #expect(TimelineInteractionMath.nudged(1_990, by: 50, maximum: 2_000) == 2_000)
        #expect(close(TimelineInteractionMath.playheadStep(duration: 149.091, visibleFraction: 1), 1.49091))
        #expect(close(TimelineInteractionMath.playheadStep(duration: 149.091, visibleFraction: 0.5), 0.745455))
        #expect(close(
            TimelineInteractionMath.playheadStep(duration: 149.091, visibleFraction: 1.0 / 12.0),
            0.1242425
        ))
        #expect(TimelineInteractionMath.steppedRate(1.0, by: 1, rates: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) == 1.25)
        #expect(TimelineInteractionMath.steppedRate(1.0, by: -1, rates: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) == 0.75)
        #expect(TimelineInteractionMath.steppedRate(2.0, by: 1, rates: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) == 2.0)
        #expect(TimelineInteractionMath.steppedRate(0.5, by: -1, rates: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) == 0.5)
    }

    @Test("Held 1/2/3 plus arrows emit the matching Final delta")
    func keyChords() {
        var chord = TimelineKeyChordState()
        #expect(chord.handle(symbol: "1", isArrowLeft: false, isArrowRight: false, phase: .down) == .consume)
        #expect(chord.handle(symbol: "", isArrowLeft: true, isArrowRight: false, phase: .down) == .nudge(-1))
        #expect(chord.handle(symbol: "", isArrowLeft: false, isArrowRight: true, phase: .repeating) == .nudge(1))
        #expect(chord.handle(symbol: "1", isArrowLeft: false, isArrowRight: false, phase: .up) == .consume)
        #expect(chord.handle(symbol: "", isArrowLeft: false, isArrowRight: true, phase: .down) == .seek(1))

        #expect(chord.handle(symbol: "2", isArrowLeft: false, isArrowRight: false, phase: .down) == .consume)
        #expect(chord.handle(symbol: "", isArrowLeft: true, isArrowRight: false, phase: .down) == .nudge(-10))
        #expect(chord.handle(symbol: "3", isArrowLeft: false, isArrowRight: false, phase: .down) == .consume)
        #expect(chord.handle(symbol: "", isArrowLeft: false, isArrowRight: true, phase: .down) == .nudge(50))
        #expect(chord.handle(symbol: "3", isArrowLeft: false, isArrowRight: false, phase: .up) == .consume)
        #expect(chord.handle(symbol: "", isArrowLeft: true, isArrowRight: false, phase: .up) == .consume)
    }

    @Test("Hotkeys survive non-command modifiers and map timeline actions")
    func hotkeys() {
        var translator = TimelineHotkeyTranslator()
        let space = TimelineHotkeyInput(
            keyCode: 49, characters: " ", command: false, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )
        #expect(translator.translate(space) == .playPause)
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 49, characters: " ", command: false, shift: false,
            option: true, control: false, isKeyUp: false, isRepeat: false
        )) == nil)
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 48, characters: "\t", command: false, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .selectRelativeToPlayhead(1))
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 48, characters: "\t", command: false, shift: true,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .selectRelativeToPlayhead(-1))
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 36, characters: "\r", command: false, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .selectCurrent)
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 24, characters: "=", command: true, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .zoom(0.5))
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 24, characters: "=", command: false, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .adjustPlaybackRate(1))
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 27, characters: "-", command: false, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .adjustPlaybackRate(-1))
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 27, characters: "-", command: true, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .zoom(-0.5))

        translator = TimelineHotkeyTranslator()
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 18, characters: "1", command: false, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .consume)
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 123, characters: "", command: false, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .nudgeFinal(-1))
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 6, characters: "z", command: true, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == nil)
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 6, characters: "z", command: true, shift: true,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == nil)
        translator = TimelineHotkeyTranslator()
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 45, characters: "n", command: false, shift: false,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == .toggleFollowSelection)
        #expect(translator.translate(TimelineHotkeyInput(
            keyCode: 45, characters: "n", command: false, shift: true,
            option: false, control: false, isKeyUp: false, isRepeat: false
        )) == nil)
    }

    @Test("Audio visualization adapters dispatch by surface and series")
    func audioVizAdaptersStayAlignedWithLaneKinds() {
        #expect(AudioVizCatalog.builtins.map(\.id) == AudioLaneKind.allCases.map(\.rawValue))
        #expect(AudioLaneKind.peak.adapter?.surface == .waveform)
        #expect(AudioLaneKind.peakRms.adapter?.series == ["peak", "rms"])
        #expect(AudioLaneKind.bands.adapter?.surface == .bands)
        #expect(AudioLaneKind.specMel.adapter?.scale == .mel)
        #expect(AudioVizCatalog.info("onset") == nil)
    }
}

private func close(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.000_000_1) -> Bool {
    abs(lhs - rhs) <= tolerance
}
