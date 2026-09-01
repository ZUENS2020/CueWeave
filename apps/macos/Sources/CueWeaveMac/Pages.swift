import AppKit
import SwiftUI

struct SourcePage: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionHeading(l10n.t("page.source"), subtitle: l10n.t("page.source.subtitle"))
                    Spacer()
                    StatusPill(text: l10n.t("source.timingAuthority"), tone: CueWeaveStyle.accent)
                }
                if let project = store.project {
                    HStack(alignment: .top, spacing: 18) {
                        cover(project).frame(width: 210)
                        VStack(spacing: 12) {
                            InputFilePanel(
                                role: l10n.t("source.infoRole"),
                                name: URL(fileURLWithPath: project.source?.path ?? l10n.t("file.missing")).lastPathComponent,
                                path: project.source?.path ?? l10n.t("file.missing"),
                                details: [
                                    (l10n.t("source.format"), project.source?.format?.uppercased() ?? "NCM"),
                                    (l10n.t("source.musicId"), project.source?.musicID.map(String.init) ?? "—"),
                                    (l10n.t("source.duration"), cueTime(project.source?.durationMS)),
                                ],
                                actionTitle: l10n.t("source.fixed"),
                                action: {},
                                enabled: false,
                                help: l10n.t("source.help.fixed"),
                                missingLabel: l10n.t("file.missing"),
                                loadedLabel: l10n.t("file.loaded")
                            )
                            InputFilePanel(
                                role: l10n.t("source.targetRole"),
                                name: URL(fileURLWithPath: project.target?.path ?? l10n.t("file.missing")).lastPathComponent,
                                path: project.target?.path ?? l10n.t("file.missing"),
                                details: [
                                    (l10n.t("source.format"), "MP3"),
                                    (l10n.t("source.duration"), cueTime(project.target?.durationMS)),
                                ],
                                actionTitle: l10n.t("source.replace"),
                                action: { Task { await store.replaceTargetInteractive() } },
                                enabled: !store.isBusy,
                                help: l10n.t("source.help.replace"),
                                missingLabel: l10n.t("file.missing"),
                                loadedLabel: l10n.t("file.loaded")
                            )
                        }
                    }
                    Panel {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundStyle(CueWeaveStyle.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l10n.t("source.timingIsolation")).font(.system(size: 10, weight: .semibold, design: .monospaced))
                                Text(l10n.t("source.timingIsolationBody"))
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
                Text(l10n.t("source.referenceCover")).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                CoverArtwork(project: project, projectURL: store.projectURL).frame(width: 178, height: 178)
                DataReadout(label: l10n.t("source.draft"), value: project.metadata.draft.coverPath ?? l10n.t("source.remoteCover"))
            }
        }
    }
}

struct MetadataPage: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(l10n.t("page.metadata"), subtitle: l10n.t("page.metadata.subtitle"))
                if let metadata = store.project?.metadata {
                    HStack(alignment: .top, spacing: 18) {
                        coverEditor.frame(width: 230)
                        VStack(spacing: 0) {
                            metadataHeader
                            MetadataTextRow(
                                label: l10n.t("meta.title"), source: metadata.source.title, target: metadata.target.title,
                                draft: store.draftBinding(\.title),
                                useSource: { store.adoptMetadata(\.title, from: .source) },
                                useTarget: { store.adoptMetadata(\.title, from: .target) },
                                useSourceHelp: l10n.t("meta.useSource"),
                                useTargetHelp: l10n.t("meta.useTarget")
                            )
                            MetadataTextRow(
                                label: l10n.t("meta.artist"), source: artists(metadata.source), target: artists(metadata.target),
                                draft: store.artistsBinding(),
                                useSource: { store.adoptArtists(from: .source) },
                                useTarget: { store.adoptArtists(from: .target) },
                                useSourceHelp: l10n.t("meta.useSource"),
                                useTargetHelp: l10n.t("meta.useTarget")
                            )
                            MetadataTextRow(
                                label: l10n.t("meta.albumArtist"), source: metadata.source.albumArtist, target: metadata.target.albumArtist,
                                draft: store.draftBinding(\.albumArtist),
                                useSource: { store.adoptMetadata(\.albumArtist, from: .source) },
                                useTarget: { store.adoptMetadata(\.albumArtist, from: .target) },
                                useSourceHelp: l10n.t("meta.useSource"),
                                useTargetHelp: l10n.t("meta.useTarget")
                            )
                            MetadataTextRow(
                                label: l10n.t("meta.album"), source: metadata.source.album, target: metadata.target.album,
                                draft: store.draftBinding(\.album),
                                useSource: { store.adoptMetadata(\.album, from: .source) },
                                useTarget: { store.adoptMetadata(\.album, from: .target) },
                                useSourceHelp: l10n.t("meta.useSource"),
                                useTargetHelp: l10n.t("meta.useTarget")
                            )
                            MetadataTextRow(
                                label: l10n.t("meta.date"), source: metadata.source.date, target: metadata.target.date,
                                draft: store.draftBinding(\.date),
                                useSource: { store.adoptMetadata(\.date, from: .source) },
                                useTarget: { store.adoptMetadata(\.date, from: .target) },
                                useSourceHelp: l10n.t("meta.useSource"),
                                useTargetHelp: l10n.t("meta.useTarget")
                            )
                            DisclosureGroup(l10n.t("meta.advanced")) {
                                VStack(spacing: 0) {
                                    MetadataTextRow(
                                        label: l10n.t("meta.track"), source: number(metadata.source.track), target: number(metadata.target.track),
                                        draft: store.numberBinding(\.track),
                                        useSource: { store.adoptNumber(\.track, from: .source) },
                                        useTarget: { store.adoptNumber(\.track, from: .target) },
                                        useSourceHelp: l10n.t("meta.useSource"),
                                        useTargetHelp: l10n.t("meta.useTarget")
                                    )
                                    MetadataTextRow(
                                        label: l10n.t("meta.disc"), source: number(metadata.source.disc), target: number(metadata.target.disc),
                                        draft: store.numberBinding(\.disc),
                                        useSource: { store.adoptNumber(\.disc, from: .source) },
                                        useTarget: { store.adoptNumber(\.disc, from: .target) },
                                        useSourceHelp: l10n.t("meta.useSource"),
                                        useTargetHelp: l10n.t("meta.useTarget")
                                    )
                                    MetadataTextRow(
                                        label: l10n.t("meta.composer"), source: metadata.source.composer, target: metadata.target.composer,
                                        draft: store.draftBinding(\.composer),
                                        useSource: { store.adoptMetadata(\.composer, from: .source) },
                                        useTarget: { store.adoptMetadata(\.composer, from: .target) },
                                        useSourceHelp: l10n.t("meta.useSource"),
                                        useTargetHelp: l10n.t("meta.useTarget")
                                    )
                                    MetadataTextRow(
                                        label: l10n.t("meta.lyricist"), source: metadata.source.lyricist, target: metadata.target.lyricist,
                                        draft: store.draftBinding(\.lyricist),
                                        useSource: { store.adoptMetadata(\.lyricist, from: .source) },
                                        useTarget: { store.adoptMetadata(\.lyricist, from: .target) },
                                        useSourceHelp: l10n.t("meta.useSource"),
                                        useTargetHelp: l10n.t("meta.useTarget")
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
                Text(l10n.t("meta.draftCover")).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                if let project = store.project {
                    CoverArtwork(project: project, projectURL: store.projectURL).frame(width: 198, height: 198)
                }
                Button(l10n.t("meta.chooseCover")) { store.replaceCoverInteractive() }
                Text(l10n.t("meta.coverHint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var metadataHeader: some View {
        Grid(horizontalSpacing: 12) {
            GridRow {
                Text(l10n.t("meta.field")).frame(width: 92, alignment: .leading)
                Text(l10n.t("meta.source")).frame(maxWidth: .infinity, alignment: .leading)
                Text(l10n.t("meta.target")).frame(maxWidth: .infinity, alignment: .leading)
                Text(l10n.t("meta.draft")).frame(maxWidth: .infinity, alignment: .leading)
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
    var useSourceHelp = L10n.shared.t("meta.useSource")
    var useTargetHelp = L10n.shared.t("meta.useTarget")

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 12) {
            GridRow {
                Text(label).frame(width: 92, alignment: .leading)
                valueCell(source, action: useSource, help: useSourceHelp)
                valueCell(target, action: useTarget, help: useTargetHelp)
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
    var missingLabel = L10n.shared.t("file.missing")
    var loadedLabel = L10n.shared.t("file.loaded")

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(role).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    StatusPill(text: path == missingLabel ? missingLabel : loadedLabel, tone: path == missingLabel ? CueWeaveStyle.warning : CueWeaveStyle.ready)
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
