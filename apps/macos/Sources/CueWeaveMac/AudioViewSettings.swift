import SwiftUI

enum SpectrumScale: String, CaseIterable, Identifiable {
    case linear, log, mel
    var id: String { rawValue }
}

enum AudioVizSurface: String, Equatable {
    case waveform
    case spectrogram
    case bands
}

struct AudioVizAdapterInfo: Identifiable, Equatable, Hashable {
    var id: String
    var surface: AudioVizSurface
    var series: [String]
    var scale: SpectrumScale?
}

enum AudioVizCatalog {
    static let builtins: [AudioVizAdapterInfo] = [
        .init(id: "peak", surface: .waveform, series: ["peak"], scale: nil),
        .init(id: "rms", surface: .waveform, series: ["rms"], scale: nil),
        .init(id: "peakRms", surface: .waveform, series: ["peak", "rms"], scale: nil),
        .init(id: "bands", surface: .bands, series: [], scale: nil),
        .init(id: "specLinear", surface: .spectrogram, series: [], scale: .linear),
        .init(id: "specLog", surface: .spectrogram, series: [], scale: .log),
        .init(id: "specMel", surface: .spectrogram, series: [], scale: .mel),
    ]

    static func info(_ id: String) -> AudioVizAdapterInfo? {
        builtins.first { $0.id == id }
    }
}

enum AudioLaneKind: String, CaseIterable, Identifiable {
    case peak
    case rms
    case peakRms
    case bands
    case specLinear
    case specLog
    case specMel

    var id: String { rawValue }
    var titleKey: String { "audio.\(rawValue)" }
    var adapter: AudioVizAdapterInfo? { AudioVizCatalog.info(rawValue) }
}

struct AudioLaneSettings: Equatable {
    var upper = AudioLaneKind.peak
    var lower = AudioLaneKind.bands

    var neededScales: [SpectrumScale] {
        [upper, lower].compactMap { $0.adapter?.scale }
    }
}

struct SpectrogramFrame: Sendable {
    var startMS: UInt64
    var endMS: UInt64
    var timeBins: Int
    var frequencyBins: Int
    var values: [UInt8]
}
