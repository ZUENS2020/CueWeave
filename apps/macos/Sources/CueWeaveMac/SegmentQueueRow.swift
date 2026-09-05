import AppKit
import Combine
import SwiftUI

struct SegmentQueueRow: View, Equatable {
    @ObservedObject private var l10n = L10n.shared
    let segment: LyricSegment
    let highlight: PlaybackHighlightModel
    let isIncluded: Bool
    let onSelect: () -> Void
    let onJump: () -> Void
    let onToggle: () -> Void
    let onStamp: () -> Void
    let onClear: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.segment == rhs.segment
            && lhs.highlight === rhs.highlight
            && lhs.isIncluded == rhs.isIncluded
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isIncluded ? CueWeaveStyle.accent : Color.secondary.opacity(0.6))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(format: "%04llu", segment.id)).foregroundStyle(.tertiary)
                    Spacer()
                    Text(cueTime(segment.timing.finalPoint?.timeMS ?? segment.timing.gemini?.timeMS))
                }
                .font(.system(size: 8, design: .monospaced))
                Text(segment.text)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .background(SegmentQueueHighlightSurface(segmentID: segment.id, highlight: highlight))
        .clipped()
        .accessibilityHint(l10n.t("row.hint"))
        .contextMenu {
            Button(l10n.t("row.select"), action: onSelect)
            Button(l10n.t("row.jump"), action: onJump)
            Button(l10n.t("row.stamp"), action: onStamp)
            Button(l10n.t("row.clear"), action: onClear).disabled(segment.timing.finalPoint == nil)
        }
    }

}

private struct SegmentQueueHighlightSurface: NSViewRepresentable {
    let segmentID: UInt64
    let highlight: PlaybackHighlightModel

    func makeNSView(context: Context) -> SegmentQueueHighlightNSView {
        SegmentQueueHighlightNSView(segmentID: segmentID, highlight: highlight)
    }

    func updateNSView(_ view: SegmentQueueHighlightNSView, context: Context) {
        view.configure(segmentID: segmentID, highlight: highlight)
    }

    static func dismantleNSView(_ view: SegmentQueueHighlightNSView, coordinator: ()) {
        view.highlightSubscription = nil
    }
}

private final class SegmentQueueHighlightNSView: NSView {
    var highlightSubscription: AnyCancellable?
    private let fillLayer = CALayer()
    private let activeEdge = CALayer()
    private var segmentID: UInt64
    private weak var highlight: PlaybackHighlightModel?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(segmentID: UInt64, highlight: PlaybackHighlightModel) {
        self.segmentID = segmentID
        self.highlight = highlight
        super.init(frame: .zero)
        wantsLayer = true
        let disabledActions: [String: CAAction] = [
            "backgroundColor": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
            "position": NSNull(),
        ]
        fillLayer.actions = disabledActions
        activeEdge.actions = disabledActions
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(activeEdge)
        subscribe(to: highlight)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(segmentID: UInt64, highlight: PlaybackHighlightModel) {
        self.segmentID = segmentID
        if self.highlight !== highlight {
            self.highlight = highlight
            subscribe(to: highlight)
        }
        render(highlight.state)
    }

    override func layout() {
        super.layout()
        fillLayer.frame = bounds
        activeEdge.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
    }

    private func subscribe(to highlight: PlaybackHighlightModel) {
        highlightSubscription = highlight.changes.sink { [weak self] change in
            self?.render(change.new)
        }
        render(highlight.state)
    }

    private func render(_ state: QueueRevealState) {
        let selected = state.selected == segmentID
        let active = state.active == segmentID
        fillLayer.backgroundColor = (selected
            ? CueWeaveStyle.lyricSelectedNSColor
            : (active ? CueWeaveStyle.lyricPlayingNSColor : .clear)).cgColor
        activeEdge.backgroundColor = CueWeaveStyle.accentNSColor.cgColor
        activeEdge.opacity = active ? 1 : 0
    }
}
