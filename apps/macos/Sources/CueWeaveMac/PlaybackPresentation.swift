import AppKit
import Combine
import SwiftUI

@MainActor
final class PlaybackReadout: ObservableObject {
    @Published private(set) var time: TimeInterval = 0
    private var lastUpdate = -Double.infinity

    func update(time: TimeInterval, hostTime: TimeInterval, force: Bool = false) {
        guard force || hostTime - lastUpdate >= 0.1 else { return }
        lastUpdate = hostTime
        if self.time != time { self.time = time }
    }
}

struct PlaybackTimeLabel: View {
    @ObservedObject var readout: PlaybackReadout
    // Fixed raster bounds keep digit changes out of the window's layout engine.
    var body: some View {
        Canvas { context, size in
            context.draw(Text(cueTime(UInt64(max(0, readout.time) * 1_000)))
                .font(.system(size: 11, design: .monospaced)), at: CGPoint(x: size.width / 2, y: size.height / 2))
        }.frame(width: 74, height: 15)
            .accessibilityLabel(cueTime(UInt64(max(0, readout.time) * 1_000)))
    }
}

struct QueueRevealState: Equatable {
    var active: UInt64?
    var selected: UInt64?
    func target(after previous: Self) -> UInt64? {
        selected != previous.selected ? selected : (active != previous.active ? active : nil)
    }
}

struct QueueRevealChange {
    let old: QueueRevealState
    let new: QueueRevealState
}

@MainActor
final class PlaybackHighlightModel {
    private(set) var state = QueueRevealState(active: nil, selected: nil)
    let changes = PassthroughSubject<QueueRevealChange, Never>()

    func set(active: UInt64?, selected: UInt64?) {
        let next = QueueRevealState(active: active, selected: selected)
        guard state != next else { return }
        let previous = state
        state = next
        changes.send(QueueRevealChange(old: previous, new: next))
    }
}

struct QueueRevealPlanner {
    static let automaticStride = 4
    private(set) var anchorIndex: Int?

    mutating func shouldReveal(index: Int, automatically: Bool) -> Bool {
        guard automatically else {
            anchorIndex = index
            return true
        }
        guard let anchorIndex else {
            self.anchorIndex = index
            return false
        }
        guard abs(index - anchorIndex) >= Self.automaticStride else { return false }
        self.anchorIndex = index
        return true
    }
}

struct TimelinePlayhead: NSViewRepresentable {
    let player: AudioPlayer
    let interaction: TimelineInteractionController

    func makeNSView(context: Context) -> PlayheadSurface {
        PlayheadSurface(player: player, interaction: interaction)
    }

    func updateNSView(_ view: PlayheadSurface, context: Context) {
        view.render(player: player, active: interaction.activeSegmentID != nil)
    }

    static func dismantleNSView(_ view: PlayheadSurface, coordinator: ()) {
        view.frameSubscription = nil
    }
}

struct TimelineHighlightSurface: NSViewRepresentable {
    let segments: [LyricSegment]
    let duration: UInt64
    let lyricTop: CGFloat
    let highlight: PlaybackHighlightModel

    func makeNSView(context: Context) -> TimelineHighlightNSView {
        TimelineHighlightNSView(highlight: highlight)
    }

    func updateNSView(_ view: TimelineHighlightNSView, context: Context) {
        view.configure(segments: segments, duration: duration, lyricTop: lyricTop)
    }

    static func dismantleNSView(_ view: TimelineHighlightNSView, coordinator: ()) {
        view.highlightSubscription = nil
    }
}

final class TimelineHighlightNSView: NSView {
    var highlightSubscription: AnyCancellable?
    private let activeLayer = CALayer()
    private let selectedLayer = CALayer()
    private var regions: [UInt64: ClosedRange<Double>] = [:]
    private var lyricTop: CGFloat = 0
    private var state = QueueRevealState(active: nil, selected: nil)
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(highlight: PlaybackHighlightModel) {
        super.init(frame: .zero)
        wantsLayer = true
        let disabledActions: [String: CAAction] = [
            "backgroundColor": NSNull(),
            "borderColor": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
            "position": NSNull(),
        ]
        for regionLayer in [activeLayer, selectedLayer] {
            regionLayer.actions = disabledActions
            regionLayer.borderWidth = 1
            layer?.addSublayer(regionLayer)
        }
        state = highlight.state
        highlightSubscription = highlight.changes.sink { [weak self] change in
            self?.state = change.new
            self?.positionLayers()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(segments: [LyricSegment], duration: UInt64, lyricTop: CGFloat) {
        let safeDuration = max(1, duration)
        var nextRegions: [UInt64: ClosedRange<Double>] = [:]
        for (index, segment) in segments.enumerated() {
            guard let start = segment.timing.finalPoint?.timeMS ?? segment.timing.gemini?.timeMS else { continue }
            let end = segments.dropFirst(index + 1).compactMap {
                $0.timing.finalPoint?.timeMS ?? $0.timing.gemini?.timeMS
            }.first ?? safeDuration
            nextRegions[segment.id] = Double(start) / Double(safeDuration) ... Double(max(start, end)) / Double(safeDuration)
        }
        regions = nextRegions
        self.lyricTop = lyricTop
        positionLayers()
    }

    override func layout() {
        super.layout()
        positionLayers()
    }

    private func positionLayers() {
        position(
            activeLayer,
            id: state.active,
            fill: CueWeaveStyle.lyricPlayingNSColor,
            borderAlpha: 0.28
        )
        position(
            selectedLayer,
            id: state.selected,
            fill: CueWeaveStyle.lyricSelectedNSColor,
            borderAlpha: 0.42
        )
    }

    private func position(
        _ regionLayer: CALayer,
        id: UInt64?,
        fill: NSColor,
        borderAlpha: CGFloat
    ) {
        guard let id, let range = regions[id] else {
            regionLayer.opacity = 0
            return
        }
        let start = CGFloat(min(max(0, range.lowerBound), 1)) * bounds.width
        let end = CGFloat(min(max(0, range.upperBound), 1)) * bounds.width
        regionLayer.backgroundColor = fill.cgColor
        regionLayer.borderColor = CueWeaveStyle.accentNSColor.withAlphaComponent(borderAlpha).cgColor
        regionLayer.frame = CGRect(
            x: start,
            y: lyricTop,
            width: max(2, end - start),
            height: TimelineLayoutMetrics.lyrics
        )
        regionLayer.opacity = 1
    }
}

final class PlayheadSurface: NSView {
    var frameSubscription: AnyCancellable?
    private let halo = CALayer()
    private let line = CALayer()
    private var fraction: Double = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let disabledActions: [String: CAAction] = [
            "backgroundColor": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
            "position": NSNull(),
        ]
        halo.actions = disabledActions
        line.actions = disabledActions
        layer?.addSublayer(halo)
        layer?.addSublayer(line)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    convenience init(player: AudioPlayer, interaction: TimelineInteractionController) {
        self.init(frame: .zero)
        frameSubscription = player.frames.sink { [weak self, weak interaction, weak player] _ in
            guard let self, let interaction, let player else { return }
            interaction.playheadDidChange(frameHostTime: CACurrentMediaTime())
            render(player: player, active: interaction.activeSegmentID != nil)
        }
    }

    func render(player: AudioPlayer, active: Bool) {
        fraction = TimelineInteractionMath.playheadFraction(currentTime: player.presentationTime, duration: player.duration, fallback: 0)
        let color = NSColor(active ? CueWeaveStyle.accent : CueWeaveStyle.warning)
        halo.backgroundColor = color.withAlphaComponent(0.12).cgColor
        line.backgroundColor = color.cgColor
        positionLayers()
    }

    override func layout() {
        super.layout()
        positionLayers()
    }

    private func positionLayers() {
        // Keep fractional coordinates. Pixel-snapping a 90–150 second timeline
        // reduces visible movement to roughly 20–35 steps/second at 2× zoom,
        // even while CADisplayLink itself is delivering 60 frames/second.
        let x = bounds.width * fraction
        halo.frame = CGRect(x: x - 5, y: 0, width: 11, height: bounds.height)
        line.frame = CGRect(x: min(x, max(0, bounds.width - 1)), y: 0, width: 1, height: bounds.height)
    }
}
