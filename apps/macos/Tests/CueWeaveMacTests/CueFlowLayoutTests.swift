import SwiftUI
import Testing
@testable import CueWeaveMac

struct CueFlowLayoutTests {
    @Test("Commands wrap without overlapping at narrow and wide window sizes")
    func wrapping() {
        for width in [CGFloat(320), 480, 640, 900] {
            let layout = CueFlowMetrics(sizes: [CGSize(width: 36, height: 32), CGSize(width: 104, height: 32),
                CGSize(width: 120, height: 32), CGSize(width: 180, height: 40), CGSize(width: 88, height: 32)],
                width: width, spacing: 8)
            #expect(layout.size.width <= width)
            for (index, frame) in layout.frames.enumerated() {
                #expect(frame.maxX <= width)
                #expect(frame.maxY <= layout.size.height)
                for previous in layout.frames.prefix(index) {
                    #expect(frame.minX >= previous.maxX || frame.minY >= previous.maxY)
                }
            }
        }
    }

    @Test("Exact fits have no extra row; oversized children stay in bounds")
    func edgeCases() {
        let fit = CueFlowMetrics(sizes: [.init(width: 100, height: 32), .init(width: 100, height: 32)], width: 208, spacing: 8)
        #expect(fit.size.height == 32)
        let narrow = CueFlowMetrics(sizes: [.init(width: 500, height: 40), .init(width: 100, height: 32)], width: 200, spacing: 8)
        #expect(narrow.frames[0].width == 200)
        #expect(narrow.frames[1].minY == 48)
        #expect(CueFlowMetrics(sizes: [], width: 200, spacing: 8).size == .zero)
    }
}
