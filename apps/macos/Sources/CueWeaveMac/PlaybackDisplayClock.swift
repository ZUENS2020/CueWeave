import Foundation

/// Predicts a smooth playhead from wall time so the UI is not tied to
/// `AVAudioPlayer.currentTime`, which quantizes coarsely when `rate != 1`.
struct PlaybackDisplayClock: Equatable {
    /// Snap to the audio engine only when the prediction has clearly lost the
    /// file (loop wrap, seek, or a stall). Must stay larger than typical
    /// `currentTime` quantization at 0.5×, or the playhead will keep jumping.
    static let resyncThreshold: TimeInterval = 0.12

    private(set) var mediaTime: TimeInterval = 0
    private(set) var hostTime: TimeInterval = 0
    private(set) var rate: Double = 1
    private(set) var running = false
    private(set) var resyncCount = 0

    mutating func reset(
        mediaTime: TimeInterval,
        hostTime: TimeInterval,
        rate: Double,
        running: Bool
    ) {
        self.mediaTime = mediaTime
        self.hostTime = hostTime
        self.rate = max(rate, 0.000_1)
        self.running = running
    }

    func predictedTime(at hostTime: TimeInterval) -> TimeInterval {
        guard running else { return mediaTime }
        return mediaTime + (hostTime - self.hostTime) * rate
    }

    func presentationTime(at timestamp: TimeInterval, duration: TimeInterval) -> TimeInterval {
        clamp(predictedTime(at: timestamp), duration: max(0, duration))
    }

    mutating func tick(
        audioTime: TimeInterval,
        hostTime: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        var predicted = presentationTime(at: hostTime, duration: duration)
        if abs(audioTime - predicted) >= Self.resyncThreshold {
            resyncCount += 1
            reset(mediaTime: audioTime, hostTime: hostTime, rate: rate, running: running)
            predicted = presentationTime(at: hostTime, duration: duration)
        }
        return predicted
    }

    private func clamp(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        min(max(0, time), duration)
    }
}
