import AppKit
import Accelerate
import AVFoundation
import DSWaveformImage
import Foundation
import QuartzCore

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate = 1.0
    @Published private(set) var loopStart: TimeInterval?
    @Published private(set) var loopEnd: TimeInterval?

    static let supportedRates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private let displayLinkTarget = AudioDisplayLinkTarget()
    private var audioPlayer: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var lastAudioTime: TimeInterval = 0
    private var displayClock = PlaybackDisplayClock()

    override init() {
        super.init()
    }

    func load(_ url: URL) throws {
        let player = try AVAudioPlayer(contentsOf: url)
        player.enableRate = true
        player.rate = Float(playbackRate)
        player.delegate = self
        player.prepareToPlay()
        audioPlayer?.stop()
        audioPlayer = player
        duration = player.duration
        currentTime = 0
        lastAudioTime = 0
        displayClock.reset(mediaTime: 0, hostTime: CACurrentMediaTime(), rate: playbackRate, running: false)
        isPlaying = false
        startDisplayLink()
        displayLink?.isPaused = true
    }

    func playPause() {
        guard let audioPlayer else { return }
        if isPlaying {
            updateClock()
            audioPlayer.pause()
            isPlaying = false
            displayClock.reset(
                mediaTime: currentTime,
                hostTime: CACurrentMediaTime(),
                rate: playbackRate,
                running: false
            )
            displayLink?.isPaused = true
        } else {
            if currentTime >= duration { currentTime = 0 }
            audioPlayer.currentTime = currentTime
            audioPlayer.rate = Float(playbackRate)
            lastAudioTime = audioPlayer.currentTime
            displayClock.reset(
                mediaTime: currentTime,
                hostTime: CACurrentMediaTime(),
                rate: playbackRate,
                running: true
            )
            isPlaying = audioPlayer.play()
            displayClock.reset(
                mediaTime: currentTime,
                hostTime: CACurrentMediaTime(),
                rate: playbackRate,
                running: isPlaying
            )
            displayLink?.isPaused = !isPlaying
        }
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer else { return }
        currentTime = min(max(0, time), duration)
        audioPlayer.currentTime = currentTime
        lastAudioTime = currentTime
        displayClock.reset(
            mediaTime: currentTime,
            hostTime: CACurrentMediaTime(),
            rate: playbackRate,
            running: isPlaying
        )
    }

    func setPlaybackRate(_ value: Double) {
        let rate = min(max(0.5, value), 2)
        guard rate != playbackRate else { return }
        let now = CACurrentMediaTime()
        let displayed = displayClock.predictedTime(at: now)
        playbackRate = rate
        audioPlayer?.rate = Float(rate)
        displayClock.reset(
            mediaTime: min(max(0, displayed), duration),
            hostTime: now,
            rate: rate,
            running: isPlaying
        )
    }

    func markLoopStart() {
        loopStart = currentTime
        normalizeLoopBounds()
    }

    func markLoopEnd() {
        loopEnd = currentTime
        normalizeLoopBounds()
    }

    func clearLoop() { loopStart = nil; loopEnd = nil }

    private func normalizeLoopBounds() {
        guard let start = loopStart, let end = loopEnd, start > end else { return }
        loopStart = end
        loopEnd = start
    }

    private func updateClock() {
        guard isPlaying, let audioPlayer else { return }
        let now = CACurrentMediaTime()
        var audioTime = audioPlayer.currentTime
        if let start = loopStart, let end = loopEnd, end > start,
           lastAudioTime < end, audioTime >= end {
            audioPlayer.currentTime = start
            audioTime = audioPlayer.currentTime
            displayClock.reset(
                mediaTime: audioTime,
                hostTime: now,
                rate: playbackRate,
                running: true
            )
        }
        lastAudioTime = audioTime
        let nextTime = displayClock.tick(audioTime: audioTime, hostTime: now, duration: duration)
        if abs(currentTime - nextTime) > 0.000_05 { currentTime = nextTime }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            currentTime = duration
            lastAudioTime = duration
            displayClock.reset(
                mediaTime: duration,
                hostTime: CACurrentMediaTime(),
                rate: playbackRate,
                running: false
            )
            isPlaying = false
            displayLink?.isPaused = true
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        displayLinkTarget.player = self
        let link = screen.displayLink(target: displayLinkTarget, selector: #selector(AudioDisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    deinit {
        displayLink?.invalidate()
    }
}

@MainActor
private final class AudioDisplayLinkTarget: NSObject {
    weak var player: AudioPlayer?

    @objc func tick(_ link: CADisplayLink) {
        player?.displayLinkDidFire()
    }
}

private extension AudioPlayer {
    func displayLinkDidFire() {
        updateClock()
    }
}

@MainActor
final class WaveformModel: ObservableObject {
    @Published private(set) var bins: [AudioDisplayBin] = []
    @Published private(set) var spectrograms: [String: SpectrogramFrame] = [:]
    private var analysisTask: Task<Void, Never>?
    private var spectrogramTask: Task<Void, Never>?
    private var loadedURL: URL?
    private var loadedSHA: String?

    func load(_ url: URL, payloadSHA256: String? = nil) {
        analysisTask?.cancel()
        spectrogramTask?.cancel()
        bins = []
        spectrograms = [:]
        loadedURL = url
        loadedSHA = payloadSHA256
        analysisTask = Task { [weak self] in
            do {
                let amplitudes = try await WaveformAnalyzer().samples(
                    fromAudioAt: url,
                    count: 4_096,
                    channelSelection: .merged
                )
                let energy = await Task.detached(priority: .userInitiated) {
                    Self.decodeBandEnergy(url, binCount: amplitudes.count)
                }.value
                guard !Task.isCancelled else { return }
                var combined = Self.combine(amplitudes: amplitudes, energy: energy)
                if url.pathExtension.lowercased() == "mp3" {
                    combined = (try? await Self.mergeCoreWaveform(
                        url: url,
                        sha256: payloadSHA256,
                        bins: combined
                    )) ?? combined
                }
                self?.bins = combined
            } catch {
                guard !Task.isCancelled else { return }
                self?.bins = []
            }
        }
    }

    func frame(for scale: SpectrumScale) -> SpectrogramFrame? {
        spectrograms[scale.rawValue]
    }

    func loadSpectrograms(scales: [SpectrumScale]) {
        spectrogramTask?.cancel()
        let unique = Array(Set(scales))
        guard let url = loadedURL, url.pathExtension.lowercased() == "mp3", !unique.isEmpty else { return }
        spectrogramTask = Task { [weak self, loadedSHA] in
            for scale in unique {
                guard !Task.isCancelled else { return }
                guard let frame = try? await Self.fetchSpectrogram(url: url, sha256: loadedSHA, scale: scale) else {
                    continue
                }
                var next = self?.spectrograms ?? [:]
                next[scale.rawValue] = frame
                self?.spectrograms = next
            }
        }
    }

    nonisolated private static func mergeCoreWaveform(
        url: URL,
        sha256: String?,
        bins: [AudioDisplayBin]
    ) async throws -> [AudioDisplayBin] {
        var payload: [String: Any] = [
            "action": "prepare",
            "audio_path": url.path,
            "cache_dir": AudioVizCache.directory,
            "waveform_bins": bins.count,
        ]
        if let sha256, !sha256.isEmpty { payload["sha256"] = sha256 }
        let result = try await CoreBridge.result("audio_viz", payload: payload)
        let peakMin = floatArray(result["peak_min"])
        let peakMax = floatArray(result["peak_max"])
        let rms = floatArray(result["rms"])
        guard peakMin.count == bins.count, peakMax.count == bins.count, rms.count == bins.count else {
            return bins
        }
        return bins.enumerated().map { index, bin in
            var next = bin
            next.minimum = peakMin[index]
            next.maximum = peakMax[index]
            next.rms = rms[index]
            return next
        }
    }

    nonisolated private static func fetchSpectrogram(
        url: URL,
        sha256: String?,
        scale: SpectrumScale
    ) async throws -> SpectrogramFrame {
        var payload: [String: Any] = [
            "action": "spectrogram",
            "audio_path": url.path,
            "cache_dir": AudioVizCache.directory,
            "scale": scale.rawValue,
            "frequency_bins": 128,
        ]
        if let sha256, !sha256.isEmpty { payload["sha256"] = sha256 }
        let result = try await CoreBridge.result("audio_viz", payload: payload)
        let values = Data(
            base64Encoded: result["values"] as? String ?? ""
        ).map { Array($0) } ?? []
        return SpectrogramFrame(
            startMS: uint64Value(result["start_ms"]),
            endMS: uint64Value(result["end_ms"]),
            timeBins: intValue(result["time_bins"]),
            frequencyBins: intValue(result["frequency_bins"]),
            values: values
        )
    }

    nonisolated private static func floatArray(_ value: Any?) -> [Float] {
        (value as? [NSNumber])?.map(\.floatValue) ?? []
    }

    nonisolated private static func intValue(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    nonisolated private static func uint64Value(_ value: Any?) -> UInt64 {
        (value as? NSNumber)?.uint64Value ?? 0
    }

    nonisolated private static func decodeBandEnergy(_ url: URL, binCount: Int) -> [BandEnergy] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return [] }
        var output = Array(repeating: BandEnergy(), count: binCount)
        let sampleRate = file.processingFormat.sampleRate
        guard var lowFilter = vDSP.Biquad(
            coefficients: lowPass(cutoff: 220, sampleRate: sampleRate),
            channelCount: 1,
            sectionCount: 1,
            ofType: Float.self
        ), var midFilter = vDSP.Biquad(
            coefficients: lowPass(cutoff: 3_800, sampleRate: sampleRate),
            channelCount: 1,
            sectionCount: 1,
            ofType: Float.self
        ), let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192)
        else { return [] }
        var consumed: AVAudioFramePosition = 0
        while true {
            do { try file.read(into: buffer) } catch { break }
            if buffer.frameLength == 0 { break }
            guard let channels = buffer.floatChannelData else { return [] }
            let frameCount = Int(buffer.frameLength)
            var mono = [Float](repeating: 0, count: frameCount)
            for channel in 0 ..< Int(buffer.format.channelCount) {
                for frame in 0 ..< frameCount { mono[frame] += channels[channel][frame] }
            }
            let scale = 1 / Float(max(1, buffer.format.channelCount))
            for frame in mono.indices { mono[frame] *= scale }
            let low = lowFilter.apply(input: mono)
            let belowHigh = midFilter.apply(input: mono)
            for frame in 0 ..< frameCount {
                let position = consumed + AVAudioFramePosition(frame)
                let bin = min(binCount - 1, Int(position * AVAudioFramePosition(binCount) / file.length))
                let middle: Float = belowHigh[frame] - low[frame]
                let high: Float = mono[frame] - belowHigh[frame]
                output[bin].low += low[frame] * low[frame]
                output[bin].mid += middle * middle
                output[bin].high += high * high
                output[bin].frameCount += 1
            }
            consumed += AVAudioFramePosition(buffer.frameLength)
        }
        let measured = output.map { value in
            let frames = Float(max(1, value.frameCount))
            return BandEnergy(
                low: sqrt(value.low / frames),
                mid: sqrt(value.mid / frames),
                high: sqrt(value.high / frames)
            )
        }
        let lowPeak = measured.map(\.low).max() ?? 0
        let midPeak = measured.map(\.mid).max() ?? 0
        let highPeak = measured.map(\.high).max() ?? 0
        return measured.map { value in
            BandEnergy(
                low: lowPeak > 0 ? value.low / lowPeak : 0,
                mid: midPeak > 0 ? value.mid / midPeak : 0,
                high: highPeak > 0 ? value.high / highPeak : 0
            )
        }
    }

    nonisolated private static func combine(
        amplitudes: [Float],
        energy: [BandEnergy]
    ) -> [AudioDisplayBin] {
        amplitudes.enumerated().map { index, sample in
            let amplitude = 1 - min(max(sample, 0), 1)
            let bands = energy.indices.contains(index) ? energy[index] : BandEnergy()
            return AudioDisplayBin(
                minimum: -amplitude,
                maximum: amplitude,
                rms: amplitude * 0.7,
                low: bands.low,
                mid: bands.mid,
                high: bands.high
            )
        }
    }

    nonisolated private static func lowPass(cutoff: Double, sampleRate: Double) -> [Double] {
        let omega = 2 * Double.pi * min(cutoff, sampleRate * 0.49) / sampleRate
        let cosine = cos(omega)
        let alpha = sin(omega) / sqrt(2)
        let divisor = 1 + alpha
        return [
            (1 - cosine) / 2 / divisor,
            (1 - cosine) / divisor,
            (1 - cosine) / 2 / divisor,
            -2 * cosine / divisor,
            (1 - alpha) / divisor,
        ]
    }
}

struct AudioDisplayBin: Sendable {
    var minimum: Float = 0
    var maximum: Float = 0
    var rms: Float = 0
    var low: Float = 0
    var mid: Float = 0
    var high: Float = 0
}

enum AudioVizCache {
    static var directory: String {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CueWeave", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}

private struct BandEnergy: Sendable {
    var low: Float = 0
    var mid: Float = 0
    var high: Float = 0
    var frameCount = 0
}
