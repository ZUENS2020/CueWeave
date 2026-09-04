import AVFoundation
import Foundation
import Testing
@testable import CueWeaveMac

@Suite("Audio playback")
struct AudioPlaybackTests {
    @Test("Pitch-preserving rates, seek, and normalized loop bounds")
    @MainActor
    func ratesSeekAndLoop() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cueweave-audio-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeSilentFixture(at: url)

        let player = AudioPlayer()
        try player.load(url)
        #expect(player.duration > 0.9)
        for rate in AudioPlayer.supportedRates {
            player.setPlaybackRate(rate)
            #expect(player.playbackRate == rate)
        }

        player.seek(to: player.duration * 0.8)
        player.markLoopStart()
        player.seek(to: player.duration * 0.2)
        player.markLoopEnd()
        #expect(player.loopStart == player.duration * 0.2)
        #expect(player.loopEnd == player.duration * 0.8)
        player.clearLoop()
        #expect(player.loopStart == nil)
        #expect(player.loopEnd == nil)
    }

    @Test("Stable analyzer produces merged amplitude and three visual bands")
    @MainActor
    func waveformAnalysis() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cueweave-waveform-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeSilentFixture(at: url)

        let waveform = WaveformModel()
        waveform.load(url)
        for _ in 0 ..< 200 where waveform.bins.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(waveform.bins.count == 4_096)
        #expect(waveform.bins.map(\.maximum).max() ?? 0 > 0)
        #expect(waveform.bins.map(\.mid).max() ?? 0 > 0.9)
        #expect(waveform.bins.allSatisfy { bin in
            [bin.minimum, bin.maximum, bin.low, bin.mid, bin.high].allSatisfy(\.isFinite)
        })
    }

    @Test("Missing or undecodable audio does not surface raw OSStatus")
    func audioLoadErrorsAreReadable() throws {
        let store = ProjectStore()
        let missing = URL(fileURLWithPath: "/tmp/cueweave-missing-\(UUID().uuidString).mp3")
        let missingMessage = store.audioLoadMessage(
            for: missing,
            error: NSError(domain: NSOSStatusErrorDomain, code: 2_003_334_207)
        )
        #expect(missingMessage == L10n.shared.t("error.audioMissing", missing.path))
        #expect(!missingMessage.contains("OSStatus"))

        let junk = FileManager.default.temporaryDirectory
            .appendingPathComponent("cueweave-not-audio-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: junk) }
        try Data("not audio".utf8).write(to: junk)
        let junkMessage = store.audioLoadMessage(
            for: junk,
            error: NSError(domain: NSOSStatusErrorDomain, code: 2_003_334_207)
        )
        #expect(junkMessage == L10n.shared.t("error.audioDecode", junk.path))
        #expect(!junkMessage.contains("OSStatus"))
    }

    @Test("Display clock keeps moving when audio currentTime is quantized")
    func displayClockAdvancesWhileAudioHolds() {
        var clock = PlaybackDisplayClock()
        clock.reset(mediaTime: 1.0, hostTime: 100, rate: 0.5, running: true)
        let displayed = clock.tick(audioTime: 1.0, hostTime: 100.040, duration: 10)
        #expect(abs(displayed - 1.020) < 0.000_5)
        #expect(displayed != 1.0)
    }

    @Test("Display clock snaps only for large audio jumps")
    func displayClockHardSyncsOnLoopWrap() {
        var clock = PlaybackDisplayClock()
        clock.reset(mediaTime: 8.0, hostTime: 200, rate: 1, running: true)
        let wrapped = clock.tick(audioTime: 2.0, hostTime: 200.016, duration: 10)
        #expect(abs(wrapped - 2.0) < 0.000_5)

        clock.reset(mediaTime: 1.0, hostTime: 300, rate: 1, running: true)
        let held = clock.tick(audioTime: 1.05, hostTime: 300.016, duration: 10)
        #expect(abs(held - 1.016) < 0.000_5)
    }

    @Test("Paused display clock does not advance")
    func pausedDisplayClockIsFrozen() {
        var clock = PlaybackDisplayClock()
        clock.reset(mediaTime: 2.5, hostTime: 50, rate: 1.5, running: false)
        let displayed = clock.tick(audioTime: 2.5, hostTime: 50.5, duration: 10)
        #expect(displayed == 2.5)
    }

    @Test("Display targets advance uniformly despite callback delivery jitter", arguments: [0.5, 1.0, 2.0])
    func presentationTargets(rate: Double) {
        var clock = PlaybackDisplayClock()
        clock.reset(mediaTime: 80, hostTime: 100, rate: rate, running: true)
        var previous = clock.presentationTime(at: 100, duration: 149)
        for frame in 1...240 {
            let target = 100 + Double(frame) / 60
            let callback = target - 1 / 60.0 + Double(frame % 5) * 0.002
            _ = clock.tick(audioTime: 80 + (callback - 100) * rate, hostTime: callback, duration: 149)
            let presented = clock.presentationTime(at: target, duration: 149)
            #expect(abs(presented - previous - rate / 60) < 0.000_001)
            previous = presented
        }
        #expect(clock.resyncCount == 0)
        #expect(clock.presentationTime(at: 1_000, duration: 149) == 149)
        clock.reset(mediaTime: 2, hostTime: 104, rate: rate, running: false)
        #expect(clock.presentationTime(at: 105, duration: 149) == 2)
    }

    @Test("Frame diagnostics count missed display slots instead of treating low CPU as smoothness")
    func frameDiagnostics() {
        let stats = PlaybackFrameStats()
        for frame in [0, 1, 2, 6, 7] {
            stats.record(target: Double(frame) / 60, interval: 1 / 60, work: 0.002, corrections: 0)
        }
        #expect(stats.frames == 5)
        #expect(stats.missed == 3)
        #expect(abs(stats.maxGap - 4 / 60) < 0.000_001)
        #expect(stats.maxWork == 0.002)
    }

    private func makeSilentFixture(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        if let samples = buffer.floatChannelData?[0] {
            for frame in 0 ..< 44_100 {
                samples[frame] = 0.25 * sin(2 * .pi * 440 * Float(frame) / 44_100)
            }
        }
        try file.write(from: buffer)
    }
}
