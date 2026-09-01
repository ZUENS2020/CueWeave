import AppKit
import SwiftUI

struct SourcePage: View {
    @ObservedObject var store: ProjectStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionHeading("Source", subtitle: "Information source and target timing authority")
                    Spacer()
                    StatusPill(text: "Target = timing authority", tone: CueWeaveStyle.accent)
                }
                if let project = store.project {
                    HStack(alignment: .top, spacing: 18) {
                        cover(project).frame(width: 210)
                        VStack(spacing: 12) {
                            InputFilePanel(
                                role: "INFORMATION SOURCE",
                                name: URL(fileURLWithPath: project.source?.path ?? "Missing").lastPathComponent,
                                path: project.source?.path ?? "Missing",
                                details: [
                                    ("FORMAT", project.source?.format?.uppercased() ?? "NCM"),
                                    ("MUSIC ID", project.source?.musicID.map(String.init) ?? "—"),
                                    ("DURATION", cueTime(project.source?.durationMS)),
                                ],
                                actionTitle: "Fixed for this project",
                                action: {},
                                enabled: false,
                                help: "Create a new project to change the original NCM information source."
                            )
                            InputFilePanel(
                                role: "TARGET AUDIO · ONLY TIMING AUTHORITY",
                                name: URL(fileURLWithPath: project.target?.path ?? "Missing").lastPathComponent,
                                path: project.target?.path ?? "Missing",
                                details: [
                                    ("FORMAT", "MP3"),
                                    ("DURATION", cueTime(project.target?.durationMS)),
                                    ("ALIGNMENT", store.stageState(.alignment).label),
                                ],
                                actionTitle: "Replace Target…",
                                action: { Task { await store.replaceTargetInteractive() } },
                                enabled: !store.isBusy,
                                help: "Replacing the target invalidates Gemini and Final timing while preserving lyrics and metadata draft."
                            )
                        }
                    }
                    Panel {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundStyle(CueWeaveStyle.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TIMING ISOLATION").font(.system(size: 10, weight: .semibold, design: .monospaced))
                                Text("Source lyric timestamps are destroyed before project creation. Only the selected Gemini provider or manual timing can place lyrics on this target audio.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 1120, alignment: .leading)
        }
    }

    @ViewBuilder
    private func cover(_ project: ProjectDocument) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("REFERENCE COVER").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                CoverArtwork(project: project, projectURL: store.projectURL).frame(width: 178, height: 178)
                DataReadout(label: "Draft", value: project.metadata.draft.coverPath ?? "Remote or missing")
            }
        }
    }
}

struct MetadataPage: View {
    @ObservedObject var store: ProjectStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionHeading("Metadata", subtitle: "Source and target stay visible; only Draft is exported")
                    Spacer()
                    StatusPill(text: store.stageState(.metadata).label, tone: CueWeaveStyle.ready)
                }
                if let metadata = store.project?.metadata {
                    HStack(alignment: .top, spacing: 18) {
                        coverEditor.frame(width: 230)
                        VStack(spacing: 0) {
                            metadataHeader
                            MetadataTextRow(
                                label: "TITLE", source: metadata.source.title, target: metadata.target.title,
                                draft: store.draftBinding(\.title),
                                useSource: { store.adoptMetadata(\.title, from: .source) },
                                useTarget: { store.adoptMetadata(\.title, from: .target) }
                            )
                            MetadataTextRow(
                                label: "ARTIST", source: artists(metadata.source), target: artists(metadata.target),
                                draft: store.artistsBinding(),
                                useSource: { store.adoptArtists(from: .source) },
                                useTarget: { store.adoptArtists(from: .target) }
                            )
                            MetadataTextRow(
                                label: "ALBUM ARTIST", source: metadata.source.albumArtist, target: metadata.target.albumArtist,
                                draft: store.draftBinding(\.albumArtist),
                                useSource: { store.adoptMetadata(\.albumArtist, from: .source) },
                                useTarget: { store.adoptMetadata(\.albumArtist, from: .target) }
                            )
                            MetadataTextRow(
                                label: "ALBUM", source: metadata.source.album, target: metadata.target.album,
                                draft: store.draftBinding(\.album),
                                useSource: { store.adoptMetadata(\.album, from: .source) },
                                useTarget: { store.adoptMetadata(\.album, from: .target) }
                            )
                            MetadataTextRow(
                                label: "DATE", source: metadata.source.date, target: metadata.target.date,
                                draft: store.draftBinding(\.date),
                                useSource: { store.adoptMetadata(\.date, from: .source) },
                                useTarget: { store.adoptMetadata(\.date, from: .target) }
                            )
                            DisclosureGroup("ADVANCED METADATA") {
                                VStack(spacing: 0) {
                                    MetadataTextRow(
                                        label: "TRACK", source: number(metadata.source.track), target: number(metadata.target.track),
                                        draft: store.numberBinding(\.track),
                                        useSource: { store.adoptNumber(\.track, from: .source) },
                                        useTarget: { store.adoptNumber(\.track, from: .target) }
                                    )
                                    MetadataTextRow(
                                        label: "DISC", source: number(metadata.source.disc), target: number(metadata.target.disc),
                                        draft: store.numberBinding(\.disc),
                                        useSource: { store.adoptNumber(\.disc, from: .source) },
                                        useTarget: { store.adoptNumber(\.disc, from: .target) }
                                    )
                                    MetadataTextRow(
                                        label: "COMPOSER", source: metadata.source.composer, target: metadata.target.composer,
                                        draft: store.draftBinding(\.composer),
                                        useSource: { store.adoptMetadata(\.composer, from: .source) },
                                        useTarget: { store.adoptMetadata(\.composer, from: .target) }
                                    )
                                    MetadataTextRow(
                                        label: "LYRICIST", source: metadata.source.lyricist, target: metadata.target.lyricist,
                                        draft: store.draftBinding(\.lyricist),
                                        useSource: { store.adoptMetadata(\.lyricist, from: .source) },
                                        useTarget: { store.adoptMetadata(\.lyricist, from: .target) }
                                    )
                                }
                                .padding(.top, 8)
                            }
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(14)
                            .background(CueWeaveStyle.panel)
                        }
                        .overlay { Rectangle().stroke(.quaternary, lineWidth: 1) }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 1200, alignment: .leading)
        }
    }

    private var coverEditor: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("DRAFT COVER").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                if let project = store.project {
                    CoverArtwork(project: project, projectURL: store.projectURL).frame(width: 198, height: 198)
                }
                Button("Choose Cover…") { store.replaceCoverInteractive() }
                Text("PNG or JPEG · embedded at export")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var metadataHeader: some View {
        Grid(horizontalSpacing: 12) {
            GridRow {
                Text("FIELD").frame(width: 92, alignment: .leading)
                Text("SOURCE").frame(maxWidth: .infinity, alignment: .leading)
                Text("TARGET").frame(maxWidth: .infinity, alignment: .leading)
                Text("DRAFT").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(12)
        .background(CueWeaveStyle.panel)
    }

    private func artists(_ values: MetadataValues) -> String? {
        values.artists.isEmpty ? nil : values.artists.joined(separator: " / ")
    }
    private func number(_ value: UInt32?) -> String? { value.map(String.init) }
}

private struct MetadataTextRow: View {
    let label: String
    let source: String?
    let target: String?
    @Binding var draft: String
    let useSource: () -> Void
    let useTarget: () -> Void

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 12) {
            GridRow {
                Text(label).frame(width: 92, alignment: .leading)
                valueCell(source, action: useSource, help: "Use source value")
                valueCell(target, action: useTarget, help: "Use target value")
                TextField(label, text: $draft).textFieldStyle(.squareBorder)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(12)
        .background(CueWeaveStyle.panel)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func valueCell(_ value: String?, action: @escaping () -> Void, help: String) -> some View {
        HStack(spacing: 5) {
            Text(value?.isEmpty == false ? value! : "—")
                .foregroundStyle(value?.isEmpty == false ? .secondary : .tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) { Image(systemName: "arrow.right") }
                .buttonStyle(.plain)
                .disabled(value?.isEmpty != false)
                .help(help)
        }
    }
}

private struct InputFilePanel: View {
    let role: String
    let name: String
    let path: String
    let details: [(String, String)]
    let actionTitle: String
    let action: () -> Void
    let enabled: Bool
    let help: String

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(role).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    StatusPill(text: path == "Missing" ? "Missing" : "Loaded", tone: path == "Missing" ? CueWeaveStyle.warning : CueWeaveStyle.ready)
                }
                Text(name).font(.headline).lineLimit(1)
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 28) {
                    ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                        DataReadout(label: detail.0, value: detail.1)
                    }
                    Spacer()
                }
                Button(actionTitle, action: action).disabled(!enabled).help(help)
            }
        }
    }
}

struct CoverArtwork: View {
    let project: ProjectDocument
    let projectURL: URL?

    var body: some View {
        let resolved = project.metadata.draft.coverPath.map { resolveProjectPath($0, relativeTo: projectURL) }
        Group {
            if let resolved, let image = loadCoverImage(from: resolved) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary).overlay {
                    Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
        }
        .id(resolved?.path ?? "")
        .clipped()
        .overlay { Rectangle().stroke(.quaternary, lineWidth: 1) }
    }

    private func loadCoverImage(from url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            return nil
        }
        var rect = NSRect(origin: .zero, size: image.size)
        _ = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        return image
    }
}
