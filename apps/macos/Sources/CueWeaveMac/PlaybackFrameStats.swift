import Foundation
import OSLog

/// Numeric-only local diagnostics: never includes media paths, lyrics, or credentials.
struct PlaybackFrameStats {
    private static let logger = Logger(subsystem: "dev.cueweave.app", category: "Playback")
    private(set) var frames = 0
    private(set) var missed = 0
    private(set) var maxGap = 0.0
    private(set) var maxWork = 0.0
    private var previousTarget: Double?

    mutating func record(target: Double, interval: Double, work: Double, corrections: Int) {
        if let previousTarget, interval > 0 {
            let gap = target - previousTarget
            maxGap = max(maxGap, gap)
            missed += max(0, Int((gap / interval).rounded()) - 1)
        }
        previousTarget = target
        maxWork = max(maxWork, work)
        frames += 1
        if frames % 120 == 0 {
            Self.logger.notice("frames=\(frames, privacy: .public) missed=\(missed, privacy: .public) maxGapMS=\(maxGap * 1_000, privacy: .public) maxWorkMS=\(maxWork * 1_000, privacy: .public) clockResyncs=\(corrections, privacy: .public)")
        }
    }
}
