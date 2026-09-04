import SwiftUI

/// Content keeps its readable size; controls flow to another row instead of compressing.
struct CueFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        metrics(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = metrics(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = layout.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> CueFlowMetrics {
        let sizes = subviews.map { subview in
            let ideal = subview.sizeThatFits(.unspecified)
            return ideal.width > width
                ? subview.sizeThatFits(ProposedViewSize(width: max(0, width), height: nil)) : ideal
        }
        return CueFlowMetrics(sizes: sizes, width: width, spacing: spacing)
    }
}

struct CueFlowMetrics {
    var size = CGSize.zero
    var frames: [CGRect] = []

    init(sizes: [CGSize], width: CGFloat, spacing: CGFloat) {
        let width = width.isNaN ? 0 : max(0, width)
        let spacing = spacing.isFinite ? max(0, spacing) : 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for item in sizes {
            let itemWidth = min(width, max(0, item.width))
            if x > 0, x + itemWidth > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: item.height))
            size.width = max(size.width, x + itemWidth)
            x += itemWidth + spacing
            rowHeight = max(rowHeight, item.height)
        }
        size.height = y + rowHeight
    }
}
