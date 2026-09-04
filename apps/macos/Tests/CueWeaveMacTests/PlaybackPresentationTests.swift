import AppKit
import AVFoundation
import Combine
import Testing
@testable import CueWeaveMac

@Suite("Playback presentation", .serialized)
@MainActor
struct PlaybackPresentationTests {
    @Test("Next produces one selected reveal, including the second half and end of the song")
    func queueReveal() {
        var previous = QueueRevealState(active: 1, selected: 2)
        for id: UInt64 in 2...38 {
            let next = QueueRevealState(active: id, selected: min(id + 1, 38))
            #expect(next.target(after: previous) == min(id + 1, 38))
            #expect(next.target(after: next) == nil)
            previous = next
        }
        let manual = QueueRevealState(active: 38, selected: 10)
        #expect(manual.target(after: previous) == 10)
        #expect(QueueRevealState(active: 20, selected: 10).target(after: manual) == 20)
        #expect(QueueRevealState(active: 38, selected: nil).target(after: manual) == nil)
    }

    @Test("Readout throttling never throttles a seek or pause")
    func readoutCadence() {
        let readout = PlaybackReadout()
        var changes = 0
        let subscription = readout.objectWillChange.sink { changes += 1 }
        for frame in 0..<120 {
            readout.update(time: 80 + Double(frame) / 120, hostTime: Double(frame) / 120)
        }
        #expect((9...11).contains(changes))
        readout.update(time: 2, hostTime: 0.999, force: true)
        #expect(readout.time == 2)
        readout.update(time: 0, hostTime: 1, force: true)
        #expect(readout.time == 0)
        withExtendedLifetime(subscription) {}
    }

    @Test("Frame delivery is synchronous, does not invalidate transport, and detaches cleanly")
    func nativeFrames() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cueweave-presentation-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 44_100)
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        let store = ProjectStore()
        let player = store.player
        try player.load(url)
        let interaction = TimelineInteractionController(store: store)
        let surface = PlayheadSurface(player: player, interaction: interaction)
        surface.setFrameSize(NSSize(width: 64_000, height: 200))
        let line = try #require(surface.layer?.sublayers?.last)
        var transportChanges = 0
        var frameTimes: [Double] = []
        let state = player.objectWillChange.sink { transportChanges += 1 }
        let frames = player.frames.sink { time in
            #expect(player.currentTime == time)
            frameTimes.append(time)
        }
        for fraction in [0.0, 0.6, 0.8, 0.99, 0.2, 1.0] {
            player.seek(to: player.duration * fraction)
            #expect(abs(line.frame.minX - min((64_000 * fraction).rounded(), 63_999)) < 0.001)
            #expect(player.readout.time == player.currentTime)
            #expect(line.animationKeys()?.isEmpty ?? true)
        }
        #expect(transportChanges == 0)
        #expect(frameTimes.count == 6)
        surface.setFrameSize(NSSize(width: 1_000, height: 300))
        surface.layout()
        #expect(line.frame == CGRect(x: 999, y: 0, width: 1, height: 300))
        surface.frameSubscription = nil
        player.seek(to: 0.4)
        #expect(line.frame.minX == 999)
        withExtendedLifetime((state, frames)) {}
    }

    @Test("Static waveform identity includes data and geometry, not lyric selection")
    func waveformInputs() {
        let a = TimelineWaveformLanes(samples: [.init(maximum: 0.5)], spectrograms: [:],
                                      lanes: .init(), metrics: .init(totalHeight: 300), size: .init(width: 64_000, height: 300))
        let b = TimelineWaveformLanes(samples: [.init(maximum: 0.5)], spectrograms: [:],
                                      lanes: .init(), metrics: .init(totalHeight: 300), size: a.size)
        #expect(a == b)
        #expect(a != TimelineWaveformLanes(samples: [.init(maximum: 0.8)], spectrograms: [:],
                                           lanes: a.lanes, metrics: a.metrics, size: a.size))
        #expect(a != TimelineWaveformLanes(samples: a.samples, spectrograms: [:],
                                           lanes: a.lanes, metrics: a.metrics, size: .init(width: 2_000, height: 300)))
    }

    @Test("Center-follow remains stable at 1x through 64x, at both song edges and during manual interaction")
    func viewportFollow() {
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 1_000, height: 200))
        let document = NSView()
        scroll.documentView = document
        let viewport = TimelineViewportProxy()
        viewport.attach(scrollView: scroll)
        for zoom in [1.0, 2, 24.5, 64] {
            let width = 1_000 * zoom
            document.setFrameSize(NSSize(width: width, height: 200))
            for fraction in [0.0, 0.5, 0.6, 0.75, 0.99, 1.0] {
                viewport.center(on: fraction)
                let expected = min(max(0, fraction * width - scroll.contentSize.width / 2), width - scroll.contentSize.width)
                #expect(abs(scroll.contentView.bounds.minX - expected.rounded()) <= 1)
            }
        }
        viewport.beginInteraction()
        let before = scroll.contentView.bounds.origin
        viewport.center(on: 0.1)
        #expect(scroll.contentView.bounds.origin == before)
        viewport.endInteraction()
        viewport.center(on: 0.1)
        #expect(scroll.contentView.bounds.origin != before)
    }
}
