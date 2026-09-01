import AppKit
import SwiftUI

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
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.documentView = context.coordinator.hostingView
        viewport.attach(scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let hostingView = context.coordinator.hostingView
        hostingView.rootView = content
        hostingView.setFrameSize(NSSize(
            width: TimelineInteractionMath.documentWidth(
                viewportWidth: viewportSize.width,
                zoom: zoom
            ),
            height: max(1, viewportSize.height)
        ))
        hostingView.layoutSubtreeIfNeeded()
        viewport.attach(scrollView: scrollView)
        viewport.documentGeometryDidChange()
    }

    final class Coordinator {
        let hostingView: NSHostingView<Content>

        init(content: Content) {
            hostingView = NSHostingView(rootView: content)
            hostingView.sizingOptions = []
        }
    }
}
