import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let cueWeaveProject = UTType(exportedAs: "dev.cueweave.project", conformingTo: .json)
}

func resolveProjectPath(_ path: String, relativeTo projectURL: URL?) -> URL {
    let portable = path.replacingOccurrences(of: "\\", with: "/")
    let foreignAbsolute = portable.hasPrefix("/") || portable.dropFirst().first == ":"
    guard !foreignAbsolute, let projectURL else { return URL(fileURLWithPath: path) }
    return projectURL.deletingLastPathComponent().appendingPathComponent(portable)
}

struct ProjectDocument: Codable, Equatable {
    var schemaVersion: Int
    var source: SourceInfo?
    var target: TargetAudio?
    var metadata: MetadataSet
    var lyrics: LyricsDocument
    var timeline: [Cue]
    var exportProfile: ExportProfile

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source, target, metadata, lyrics, timeline
        case exportProfile = "export"
    }
}

struct SourceInfo: Codable, Equatable {
    var path: String
    var fingerprint: MediaFingerprint?
    var musicID: UInt64?
    var coverURL: String?
    var format: String?
    var durationMS: UInt64?

    enum CodingKeys: String, CodingKey {
        case path, fingerprint, format
        case musicID = "music_id"
        case coverURL = "cover_url"
        case durationMS = "duration_ms"
    }
}

struct TargetAudio: Codable, Equatable {
    var path: String
    var fingerprint: MediaFingerprint?
    var durationMS: UInt64?

    enum CodingKeys: String, CodingKey {
        case path, fingerprint
        case durationMS = "duration_ms"
    }
}

struct MediaFingerprint: Codable, Equatable {
    var fileName: String
    var sizeBytes: UInt64
    var sha256: String

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case sizeBytes = "size_bytes"
        case sha256
    }
}

struct MetadataSet: Codable, Equatable {
    var source: MetadataValues
    var target: MetadataValues
    var draft: MetadataValues
}

struct MetadataValues: Codable, Equatable {
    var title: String?
    var artists: [String]
    var albumArtist: String?
    var album: String?
    var track: UInt32?
    var disc: UInt32?
    var date: String?
    var composer: String?
    var lyricist: String?
    var coverPath: String?

    enum CodingKeys: String, CodingKey {
        case title, artists, album, track, disc, date, composer, lyricist
        case albumArtist = "album_artist"
        case coverPath = "cover_path"
    }
}

struct LyricsDocument: Codable, Equatable {
    var credits: [Credit]
    var lines: [LyricLine]
}

struct Credit: Codable, Equatable {
    var label: String
    var value: String
}

struct LyricLine: Codable, Equatable, Identifiable {
    var id: UInt64
    var original: String
    var translation: String?
    var segments: [LyricSegment]
}

struct LyricSegment: Codable, Equatable, Identifiable {
    var id: UInt64
    var text: String
    var timing: SegmentTiming
}

struct SegmentTiming: Codable, Equatable {
    var gemini: AlignmentPoint?
    var finalPoint: AlignmentPoint?
    var review: ReviewState

    enum CodingKeys: String, CodingKey {
        case gemini, review
        case finalPoint = "final"
    }
}

struct AlignmentPoint: Codable, Equatable {
    var timeMS: UInt64
    var confidence: Float?

    enum CodingKeys: String, CodingKey {
        case timeMS = "time_ms"
        case confidence
    }
}

enum ReviewState: String, Codable, CaseIterable {
    case pending
    case autoAccepted = "auto_accepted"
    case needsReview = "needs_review"
    case userConfirmed = "user_confirmed"
    case ignored
    case unmatched

    var title: String {
        switch self {
        case .pending: L10n.shared.t("review.pending")
        case .autoAccepted: L10n.shared.t("review.auto")
        case .needsReview: L10n.shared.t("review.review")
        case .userConfirmed: L10n.shared.t("review.confirmed")
        case .ignored: L10n.shared.t("review.ignored")
        case .unmatched: L10n.shared.t("review.unmatched")
        }
    }
}

struct Cue: Codable, Equatable {
    var type: String
    var timeMS: UInt64?
    var text: String?
    var lineID: UInt64?

    enum CodingKeys: String, CodingKey {
        case type, text
        case timeMS = "time_ms"
        case lineID = "line_id"
    }
}

struct ExportProfile: Codable, Equatable {
    var offsetMS: Int64
    var formats: [ExportFormat]
    var bilingual: BilingualMode

    enum CodingKeys: String, CodingKey {
        case offsetMS = "offset_ms"
        case formats, bilingual
    }
}

enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case lrc, uslt, sylt
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var detail: String {
        switch self {
        case .lrc: L10n.shared.t("export.lrc")
        case .uslt: L10n.shared.t("export.uslt")
        case .sylt: L10n.shared.t("export.sylt")
        }
    }
}

enum BilingualMode: String, Codable, CaseIterable, Identifiable {
    case originalOnly = "original_only"
    case combined
    var id: String { rawValue }
    var title: String { self == .originalOnly ? L10n.shared.t("export.originalOnly") : L10n.shared.t("export.combined") }
}

enum WorkspacePage: String, CaseIterable, Identifiable {
    case source = "Source"
    case metadata = "Metadata"
    case lyrics = "Lyrics"
    case translation = "Translation"
    case alignment = "Alignment"
    case export = "Export"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .source: L10n.shared.t("page.source")
        case .metadata: L10n.shared.t("page.metadata")
        case .lyrics: L10n.shared.t("page.lyrics")
        case .translation: L10n.shared.t("page.translation")
        case .alignment: L10n.shared.t("page.alignment")
        case .export: L10n.shared.t("page.export")
        }
    }
    var icon: String {
        switch self {
        case .source: "square.and.arrow.down"
        case .metadata: "tag"
        case .lyrics: "text.quote"
        case .translation: "translate"
        case .alignment: "waveform.path"
        case .export: "square.and.arrow.up"
        }
    }

    var detail: String {
        switch self {
        case .source: L10n.shared.t("page.source.detail")
        case .metadata: L10n.shared.t("page.metadata.detail")
        case .lyrics: L10n.shared.t("page.lyrics.detail")
        case .translation: L10n.shared.t("page.translation.detail")
        case .alignment: L10n.shared.t("page.alignment.detail")
        case .export: L10n.shared.t("page.export.detail")
        }
    }
}

enum AlignmentProvider: String, CaseIterable, Identifiable {
    case openRouter = "openrouter"
    case aiStudio = "ai_studio"

    var id: String { rawValue }
    var title: String { self == .openRouter ? "OpenRouter" : "AI Studio" }
}

enum WorkspaceStageState: Equatable {
    case ready
    case review(Int)
    case pending

    var label: String {
        switch self {
        case .ready: L10n.shared.t("stage.ready")
        case let .review(count): L10n.shared.t("stage.review", String(count))
        case .pending: L10n.shared.t("stage.pending")
        }
    }
}

enum MetadataOrigin {
    case source
    case target
}
