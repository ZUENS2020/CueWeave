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
    var body: some View { Text(cueTime(UInt64(max(0, readout.time) * 1_000))) }
}

struct QueueRevealState: Equatable {
    var active: UInt64?
    var selected: UInt64?
    func target(after previous: Self) -> UInt64? {
        selected != previous.selected ? selected : (active != previous.active ? active : nil)
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
        layer?.addSublayer(halo)
        layer?.addSublayer(line)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    convenience init(player: AudioPlayer, interaction: TimelineInteractionController) {
        self.init(frame: .zero)
        frameSubscription = player.frames.sink { [weak self, weak interaction, weak player] _ in
            guard let self, let interaction, let player else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            interaction.playheadDidChange()
            render(player: player, active: interaction.activeSegmentID != nil)
            CATransaction.commit()
        }
    }

    func render(player: AudioPlayer, active: Bool) {
        fraction = TimelineInteractionMath.playheadFraction(currentTime: player.currentTime, duration: player.duration, fallback: 0)
        let color = NSColor(active ? CueWeaveStyle.accent : CueWeaveStyle.warning)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.backgroundColor = color.withAlphaComponent(0.12).cgColor
        line.backgroundColor = color.cgColor
        positionLayers()
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        positionLayers()
        CATransaction.commit()
    }

    private func positionLayers() {
        let scale = window?.backingScaleFactor ?? 1
        let x = (bounds.width * fraction * scale).rounded() / scale
        halo.frame = CGRect(x: x - 5, y: 0, width: 11, height: bounds.height)
        line.frame = CGRect(x: min(x, max(0, bounds.width - 1)), y: 0, width: 1, height: bounds.height)
    }
}
