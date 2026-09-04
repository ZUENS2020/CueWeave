import AppKit
import SwiftUI

enum TimelineScrollChrome {
    static var barHeight: CGFloat { MiniLegacyScroller.barHeight }
}

struct AlwaysVisibleScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { RevealLegacyScrollersView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? RevealLegacyScrollersView)?.apply()
    }
}

private final class RevealLegacyScrollersView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    func apply() {
        var current: NSView? = self
        while let view = current {
            if let scroll = view as? NSScrollView {
                MiniLegacyScroller.install(on: scroll, vertical: true, horizontal: false)
                return
            }
            current = view.superview
        }
    }
}

struct TimelineNativeScrollView<Content: View>: NSViewRepresentable {
    let zoom: Double
    let viewportSize: CGSize
    let viewport: TimelineViewportProxy
    let content: Content

    init(
        zoom: Double,
        viewportSize: CGSize,
        viewport: TimelineViewportProxy,
        @ViewBuilder content: () -> Content
    ) {
        self.zoom = zoom
        self.viewportSize = viewportSize
        self.viewport = viewport
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator(content: content) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = TimelineScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        MiniLegacyScroller.install(on: scrollView, vertical: false, horizontal: true)
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.documentView = context.coordinator.hostingView
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        viewport.attach(scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let hostingView = context.coordinator.hostingView
        hostingView.rootView = content
        let size = NSSize(
            width: TimelineInteractionMath.documentWidth(
                viewportWidth: viewportSize.width,
                zoom: zoom
            ),
            height: max(1, viewportSize.height)
        )
        if hostingView.frame.size != size {
            hostingView.setFrameSize(size)
            hostingView.layoutSubtreeIfNeeded()
        }
        MiniLegacyScroller.install(on: scrollView, vertical: false, horizontal: true)
        viewport.attach(scrollView: scrollView)
        viewport.documentGeometryDidChange()
    }

    final class Coordinator {
        let hostingView: NSHostingView<Content>

        init(content: Content) {
            hostingView = NSHostingView(rootView: content)
            hostingView.sizingOptions = []
            hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }
}

private final class MiniLegacyScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }

    static var barHeight: CGFloat {
        max(15, scrollerWidth(for: .mini, scrollerStyle: .legacy))
    }

    static func install(on scrollView: NSScrollView, vertical: Bool, horizontal: Bool) {
        if scrollView.hasVerticalScroller != vertical { scrollView.hasVerticalScroller = vertical }
        if scrollView.hasHorizontalScroller != horizontal { scrollView.hasHorizontalScroller = horizontal }
        if scrollView.autohidesScrollers { scrollView.autohidesScrollers = false }
        if scrollView.scrollerStyle != .legacy { scrollView.scrollerStyle = .legacy }
        if vertical {
            if !(scrollView.verticalScroller is MiniLegacyScroller) {
                let bar = MiniLegacyScroller()
                scrollView.verticalScroller = bar
            }
            if scrollView.verticalScroller?.controlSize != .mini { scrollView.verticalScroller?.controlSize = .mini }
        }
        if horizontal {
            if !(scrollView.horizontalScroller is MiniLegacyScroller) {
                let bar = MiniLegacyScroller()
                scrollView.horizontalScroller = bar
            }
            if scrollView.horizontalScroller?.controlSize != .mini { scrollView.horizontalScroller?.controlSize = .mini }
        }
    }
}

private final class TimelineScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MiniLegacyScroller.install(on: self, vertical: false, horizontal: true)
    }

    override func tile() {
        MiniLegacyScroller.install(on: self, vertical: false, horizontal: true)
        super.tile()
        MiniLegacyScroller.install(on: self, vertical: false, horizontal: true)
    }
}
