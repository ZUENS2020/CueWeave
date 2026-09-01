import CoreGraphics
import Foundation

enum TimelineLane: Equatable {
    case ruler, waveform, bands, lyrics
}

struct TimelinePointerSample: Equatable {
    let documentFraction: Double
    let viewportFraction: Double
    let lane: TimelineLane

    init(documentFraction: Double, viewportFraction: Double, lane: TimelineLane = .waveform) {
        self.documentFraction = documentFraction
        self.viewportFraction = viewportFraction
        self.lane = lane
    }
}

enum TimelinePointerEvent: Equatable {
    case click(TimelinePointerSample)
    case selectionChanged(ClosedRange<Double>)
    case selectionCommitted(ClosedRange<Double>)
    case zoomBegan
    case zoom(delta: Double, anchor: TimelinePointerSample)
    case zoomEnded
}

struct TimelinePointerStateMachine {
    private var start: TimelinePointerSample?
    private var startX: CGFloat = 0
    private var selecting = false

    mutating func begin(at sample: TimelinePointerSample, x: CGFloat) {
        start = sample
        startX = x
        selecting = false
    }

    mutating func drag(to sample: TimelinePointerSample, x: CGFloat) -> TimelinePointerEvent? {
        guard let start else { return nil }
        if !selecting { selecting = abs(x - startX) >= 4 }
        guard selecting else { return nil }
        return .selectionChanged(Self.range(start.documentFraction, sample.documentFraction))
    }

    mutating func end(at sample: TimelinePointerSample) -> TimelinePointerEvent? {
        guard let start else { return nil }
        let event: TimelinePointerEvent = selecting
            ? .selectionCommitted(Self.range(start.documentFraction, sample.documentFraction))
            : .click(sample)
        self.start = nil
        selecting = false
        return event
    }

    mutating func cancel() {
        start = nil
        selecting = false
    }

    private static func range(_ first: Double, _ second: Double) -> ClosedRange<Double> {
        min(first, second) ... max(first, second)
    }
}

struct TimelineLayoutMetrics: Equatable {
    static let ruler: CGFloat = 24
    static let lyrics: CGFloat = 72

    let waveform: CGFloat
    let bands: CGFloat

    init(totalHeight: CGFloat) {
        let shared = max(0, totalHeight - Self.ruler - Self.lyrics) / 2
        waveform = shared
        bands = shared
    }

    var bandTop: CGFloat { Self.ruler + waveform }
    var lyricTop: CGFloat { bandTop + bands }

    static func lane(at y: CGFloat, height: CGFloat) -> TimelineLane {
        let metrics = TimelineLayoutMetrics(totalHeight: height)
        if y < ruler { return .ruler }
        if y < metrics.bandTop { return .waveform }
        if y < metrics.lyricTop { return .bands }
        return .lyrics
    }
}

struct TimelineKeyChordState: Equatable {
    enum Phase: Equatable { case down, repeating, up }
    enum Action: Equatable {
        case ignore
        case consume
        case nudge(Int64)
        case seek(Int)
    }

    private(set) var heldStep: Int64?

    mutating func handle(
        symbol: String,
        isArrowLeft: Bool,
        isArrowRight: Bool,
        phase: Phase
    ) -> Action {
        if let step = TimelineInteractionMath.nudgeStep(for: symbol) {
            if phase == .up {
                if heldStep == step { heldStep = nil }
            } else {
                heldStep = step
            }
            return .consume
        }
        if isArrowLeft || isArrowRight {
            if phase == .up { return .consume }
            if let heldStep {
                return .nudge(isArrowRight ? heldStep : -heldStep)
            }
            return .seek(isArrowRight ? 1 : -1)
        }
        return .ignore
    }
}

enum TimelineInteractionMath {
    static let maximumZoom = 64.0

    static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, x.isFinite else { return 0 }
        return Double(min(max(0, x), width) / width)
    }

    static func rangeZoom(
        _ range: ClosedRange<Double>,
        minimum: Double = 1,
        maximum: Double = maximumZoom
    ) -> Double {
        let width = max(0.000_001, range.upperBound - range.lowerBound)
        return min(maximum, max(minimum, 0.92 / width))
    }

    static func nudgeStep(for key: String) -> Int64? {
        switch key {
        case "1": 1
        case "2": 10
        case "3": 50
        default: nil
        }
    }

    static func nudgeStep(forKeyCode keyCode: UInt16) -> Int64? {
        switch keyCode {
        case 18, 83: 1
        case 19, 84: 10
        case 20, 85: 50
        default: nil
        }
    }

    static func nudged(_ milliseconds: UInt64, by delta: Int64, maximum: UInt64) -> UInt64 {
        if delta < 0 {
            let amount = UInt64(delta.magnitude)
            return amount >= milliseconds ? 0 : milliseconds - amount
        }
        let (sum, overflow) = milliseconds.addingReportingOverflow(UInt64(delta))
        return overflow ? maximum : min(sum, maximum)
    }

    static func scrollOrigin(
        anchorX: CGFloat,
        viewportAnchor: CGFloat,
        viewportWidth: CGFloat,
        documentMinX: CGFloat,
        documentMaxX: CGFloat
    ) -> CGFloat {
        let desired = anchorX - min(max(0, viewportAnchor), 1) * viewportWidth
        let maximum = max(documentMinX, documentMaxX - viewportWidth)
        return min(max(documentMinX, desired), maximum)
    }

    static func documentWidth(viewportWidth: CGFloat, zoom: Double) -> CGFloat {
        max(1, viewportWidth) * CGFloat(max(1, zoom))
    }

    /// SwiftUI `Canvas` rasterizes to a texture. On Retina that clips near 8,192
    /// device pixels, so a 40× document-sized canvas loses the right-hand waveform.
    static let canvasTileWidth: CGFloat = 2_048

    static func canvasTileCount(documentWidth: CGFloat) -> Int {
        max(1, Int(ceil(max(1, documentWidth) / canvasTileWidth)))
    }

    static func canvasTileFrame(index: Int, documentWidth: CGFloat) -> (origin: CGFloat, width: CGFloat) {
        let origin = CGFloat(index) * canvasTileWidth
        return (origin, min(canvasTileWidth, max(0, documentWidth - origin)))
    }

    static func canvasTileBins(
        tileOrigin: CGFloat,
        tileWidth: CGFloat,
        documentWidth: CGFloat,
        binCount: Int
    ) -> Range<Int> {
        guard binCount > 1, documentWidth > 0, tileWidth > 0 else {
            return 0..<max(0, binCount)
        }
        let step = documentWidth / CGFloat(binCount - 1)
        let start = min(binCount - 1, max(0, Int(floor((tileOrigin - step) / step))))
        let end = min(binCount, Int(ceil((tileOrigin + tileWidth + step) / step)) + 1)
        return start..<max(start + 1, end)
    }

    static func playheadFraction(currentTime: Double, duration: Double, fallback: Double) -> Double {
        guard duration > 0, currentTime.isFinite, duration.isFinite else {
            return min(max(0, fallback), 1)
        }
        return min(max(0, currentTime / duration), 1)
    }

    static func playheadStep(duration: Double, visibleFraction: Double, proportion: Double = 0.01) -> Double {
        max(0, duration) * min(max(visibleFraction, 0), 1) * max(0, proportion)
    }

    static func steppedRate(_ current: Double, by direction: Int, rates: [Double]) -> Double {
        let rates = rates.sorted()
        guard !rates.isEmpty else { return current }
        let index = rates.enumerated()
            .min(by: { abs($0.element - current) < abs($1.element - current) })?
            .offset ?? 0
        return rates[min(max(0, index + direction), rates.count - 1)]
    }

    static func coveringSegmentID(
        timeMS: UInt64,
        points: [(id: UInt64, timeMS: UInt64)],
        durationMS: UInt64
    ) -> UInt64? {
        for index in points.indices {
            let start = points[index].timeMS
            let next = points.dropFirst(index + 1).map(\.timeMS).first
            let end = next ?? durationMS
            if let next {
                if timeMS >= start, timeMS < next { return points[index].id }
            } else if timeMS >= start, timeMS <= end {
                return points[index].id
            }
        }
        return nil
    }

    static func followingSegmentID(activeID: UInt64?, orderedIDs: [UInt64]) -> UInt64? {
        guard !orderedIDs.isEmpty else { return nil }
        guard let activeID, let index = orderedIDs.firstIndex(of: activeID) else {
            return orderedIDs.first
        }
        return orderedIDs[min(index + 1, orderedIDs.count - 1)]
    }

    static func keepsFollowSelection(relativeOffset: Int) -> Bool {
        relativeOffset == 1
    }
}

enum TimelineHotkey: Equatable {
    case consume
    case playPause
    case seekPlayhead(Int)
    case nudgeFinal(Int64)
    case moveSelection(Int)
    case selectCurrent
    case selectRelativeToPlayhead(Int)
    case stampFinal
    case clearFinal
    case loopStart
    case loopEnd
    case clearLoop
    case seekToStart
    case seekToEnd
    case zoom(Double)
    case adjustPlaybackRate(Int)
}

struct TimelineHotkeyInput: Equatable {
    var keyCode: UInt16
    var characters: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool
    var isKeyUp: Bool
    var isRepeat: Bool
}

struct TimelineHotkeyTranslator: Equatable {
    var chord = TimelineKeyChordState()

    mutating func translate(_ input: TimelineHotkeyInput) -> TimelineHotkey? {
        if input.option || input.control { return nil }
        if input.command {
            if input.isKeyUp { return nil }
            if Self.isZoomIn(input) { return .zoom(0.5) }
            if Self.isZoomOut(input) { return .zoom(-0.5) }
            return nil
        }

        let symbol = Self.chordSymbol(input)
        switch chord.handle(
            symbol: symbol,
            isArrowLeft: input.keyCode == 123,
            isArrowRight: input.keyCode == 124,
            phase: input.isKeyUp ? .up : input.isRepeat ? .repeating : .down
        ) {
        case .ignore:
            break
        case .consume:
            return .consume
        case let .nudge(delta):
            return .nudgeFinal(delta)
        case let .seek(direction):
            return .seekPlayhead(direction)
        }

        if input.isKeyUp { return nil }
        if Self.isRateUp(input) { return .adjustPlaybackRate(1) }
        if Self.isRateDown(input) { return .adjustPlaybackRate(-1) }
        if input.isRepeat { return nil }
        if input.shift && input.keyCode != 48 { return nil }

        switch input.keyCode {
        case 49: return .playPause
        case 125: return .moveSelection(1)
        case 126: return .moveSelection(-1)
        case 36, 76: return .selectCurrent
        case 48: return .selectRelativeToPlayhead(input.shift ? -1 : 1)
        case 46: return .stampFinal
        case 0: return .loopStart
        case 11: return .loopEnd
        case 43: return .nudgeFinal(-1)
        case 47: return .nudgeFinal(1)
        case 115: return .seekToStart
        case 119: return .seekToEnd
        case 53: return .clearLoop
        case 51, 117: return .clearFinal
        default:
            switch input.characters.lowercased() {
            case "m": return .stampFinal
            case "a": return .loopStart
            case "b": return .loopEnd
            case ",", "<": return .nudgeFinal(-1)
            case ".", ">": return .nudgeFinal(1)
            default: return nil
            }
        }
    }

    private static func chordSymbol(_ input: TimelineHotkeyInput) -> String {
        switch TimelineInteractionMath.nudgeStep(forKeyCode: input.keyCode) {
        case 1: "1"
        case 10: "2"
        case 50: "3"
        default: input.characters
        }
    }

    private static func isZoomIn(_ input: TimelineHotkeyInput) -> Bool {
        input.characters == "+" || input.characters == "="
    }

    private static func isZoomOut(_ input: TimelineHotkeyInput) -> Bool {
        input.characters == "-" || input.characters == "_"
    }

    private static func isRateUp(_ input: TimelineHotkeyInput) -> Bool {
        input.keyCode == 24 || input.characters == "=" || input.characters == "+"
    }

    private static func isRateDown(_ input: TimelineHotkeyInput) -> Bool {
        input.keyCode == 27 || input.characters == "-" || input.characters == "_"
    }
}
