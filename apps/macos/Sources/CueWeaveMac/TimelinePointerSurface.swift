import AppKit
import SwiftUI

struct TimelinePointerSurface: NSViewRepresentable {
    let onEvent: (TimelinePointerEvent) -> Void
    let creditAt: (TimelinePointerSample, CGFloat) -> UInt64?

    func makeNSView(context: Context) -> PointerView {
        let view = PointerView()
        view.onEvent = onEvent
        view.creditAt = creditAt
        return view
    }

    func updateNSView(_ view: PointerView, context: Context) {
        view.onEvent = onEvent
        view.creditAt = creditAt
    }

}

final class PointerView: NSView {
    var onEvent: ((TimelinePointerEvent) -> Void)?
    var creditAt: ((TimelinePointerSample, CGFloat) -> UInt64?)?
    private var pointer = TimelinePointerStateMachine()
    private var zoomGestureActive = false

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let sample = sample(event)
        pointer.begin(at: sample, x: point.x, credit: sample.lane == .lyrics ? creditAt?(sample, bounds.width) : nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let event = pointer.drag(to: sample(event), x: point.x) { onEvent?(event) }
    }

    override func mouseUp(with event: NSEvent) {
        if let event = pointer.end(at: sample(event)) { onEvent?(event) }
    }

    override func magnify(with event: NSEvent) {
        beginZoomIfNeeded()
        onEvent?(.zoom(delta: Double(event.magnification), anchor: sample(event)))
        endZoomIfNeeded(for: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let isEnding = event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled)
        guard event.modifierFlags.contains(.control) else {
            if zoomGestureActive, isEnding { finishZoom() }
            super.scrollWheel(with: event)
            return
        }
        guard event.scrollingDeltaY != 0 else {
            if zoomGestureActive, isEnding { finishZoom() }
            return
        }
        beginZoomIfNeeded()
        let delta = event.scrollingDeltaY > 0 ? 0.06 : -0.06
        onEvent?(.zoom(delta: delta, anchor: sample(event)))
        endZoomIfNeeded(for: event)
    }

    override func cancelOperation(_ sender: Any?) {
        pointer.cancel()
        if zoomGestureActive {
            zoomGestureActive = false
            onEvent?(.zoomEnded)
        }
        super.cancelOperation(sender)
    }

    private func sample(_ event: NSEvent) -> TimelinePointerSample {
        let point = convert(event.locationInWindow, from: nil)
        let document = TimelineInteractionMath.fraction(at: point.x, width: bounds.width)
        let lane = TimelineLayoutMetrics.lane(at: point.y, height: bounds.height)
        guard let scrollView = enclosingScrollView else {
            return TimelinePointerSample(documentFraction: document, viewportFraction: document, lane: lane)
        }
        let clipPoint = scrollView.contentView.convert(event.locationInWindow, from: nil)
        let viewport = TimelineInteractionMath.fraction(at: clipPoint.x, width: scrollView.contentView.bounds.width)
        return TimelinePointerSample(documentFraction: document, viewportFraction: viewport, lane: lane)
    }

    private func beginZoomIfNeeded() {
        guard !zoomGestureActive else { return }
        zoomGestureActive = true
        onEvent?(.zoomBegan)
    }

    private func endZoomIfNeeded(for event: NSEvent) {
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
        let phaseLessWheel = event.type == .scrollWheel
            && event.phase.isEmpty
            && event.momentumPhase.isEmpty
        guard ended || phaseLessWheel else { return }
        finishZoom()
    }

    private func finishZoom() {
        zoomGestureActive = false
        onEvent?(.zoomEnded)
    }
}
