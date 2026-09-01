import SwiftUI

struct ExportPage: View {
    @ObservedObject var store: ProjectStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionHeading("Final Export", subtitle: "Write a new MP3, then adapt lyrics through player plugins")
                    Spacer()
                    StatusPill(text: store.stageState(.export).label, tone: exportTone)
                }
                if let project = store.project {
                    HStack(alignment: .top, spacing: 18) {
                        summary(project).frame(maxWidth: .infinity)
                        options(project).frame(width: 360)
                    }
                    blockingStatus(project)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OUTPUT").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                            Text("Export Final writes a new MP3. Save Cue Sheet writes the player-agnostic JSON later plugins will consume.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Save Cue Sheet…") { Task { await store.exportCueSheetInteractive() } }
                            .disabled(store.project?.lyrics.lines.isEmpty != false || store.isBusy)
                        Button("Export Final…") { Task { await store.exportInteractive() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!exportReady || store.isBusy)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(22)
            .frame(maxWidth: 1160, alignment: .leading)
        }
    }

    private func summary(_ project: ProjectDocument) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    CoverArtwork(project: project, projectURL: store.projectURL).frame(width: 132, height: 132)
                    VStack(alignment: .leading, spacing: 11) {
                        Text(project.metadata.draft.title ?? "Untitled")
                            .font(.system(size: 24, weight: .semibold))
                        Text(project.metadata.draft.artists.joined(separator: " / "))
                            .foregroundStyle(.secondary)
                        Divider()
                        HStack(spacing: 26) {
                            DataReadout(label: "Album", value: project.metadata.draft.album ?? "—")
                            DataReadout(label: "Album Artist", value: project.metadata.draft.albumArtist ?? "—")
                            DataReadout(label: "Release", value: project.metadata.draft.date ?? "—")
                        }
                    }
                }
                Divider()
                Text("PROJECT CONTENT").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                SummaryRow(
                    icon: "tag", title: "Metadata",
                    detail: metadataReady ? "Title and artist ready" : "Title or artist missing",
                    ready: metadataReady
                )
                SummaryRow(
                    icon: "text.quote", title: "Lyrics",
                    detail: "\(project.lyrics.lines.count) lines · \(store.allSegments.count) segments · \(translationCount) translated",
                    ready: !project.lyrics.lines.isEmpty
                )
                SummaryRow(
                    icon: "waveform.path", title: "Alignment",
                    detail: "\(alignedCount) / \(store.allSegments.count) have Final times",
                    ready: alignedCount == store.allSegments.count && !store.allSegments.isEmpty
                )
                SummaryRow(
                    icon: "waveform", title: "Audio",
                    detail: "Original MPEG frame payload · SHA-256 verified after tagging",
                    ready: project.target != nil
                )
                Divider()
                HStack(spacing: 8) {
                    StatusPill(text: "No overwrite", tone: CueWeaveStyle.ready)
                    StatusPill(text: "No re-encode", tone: CueWeaveStyle.ready)
                    StatusPill(text: "Atomic output", tone: CueWeaveStyle.ready)
                }
            }
        }
    }

    private func options(_ project: ProjectDocument) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text("PLAYER ADAPTERS").font(.system(size: 10, weight: .semibold, design: .monospaced))
                ForEach(ExportFormat.allCases) { format in
                    HStack {
                        Toggle(isOn: store.formatBinding(format)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.title).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Text(format.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Divider()
                Text("BILINGUAL").font(.system(size: 10, weight: .semibold, design: .monospaced))
                Picker("Bilingual", selection: bilingualBinding) {
                    ForEach(BilingualMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .labelsHidden()
                Divider()
                Stepper(
                    "Export offset  \(project.exportProfile.offsetMS) ms",
                    value: offsetBinding,
                    in: -2_000 ... 2_000,
                    step: 10
                )
                .font(.system(size: 11, design: .monospaced))
                Text("Built-in adapters: LRC sidecar, USLT/SYLT tags. Additional players will plug into the Cue Sheet JSON, not the project file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func blockingStatus(_ project: ProjectDocument) -> some View {
        Panel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: exportReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(exportReady ? CueWeaveStyle.ready : CueWeaveStyle.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(exportReady ? "READY TO EXPORT" : "EXPORT BLOCKED")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text(blockingReason(project)).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metadataReady: Bool {
        store.project?.metadata.draft.title?.isEmpty == false
            && store.project?.metadata.draft.artists.contains { !$0.isEmpty } == true
    }
    private var alignedCount: Int { store.allSegments.filter { $0.timing.finalPoint != nil }.count }
    private var translationCount: Int { store.project?.lyrics.lines.filter { $0.translation?.isEmpty == false }.count ?? 0 }
    private var exportReady: Bool {
        metadataReady && !store.allSegments.isEmpty && alignedCount == store.allSegments.count
            && !(store.project?.exportProfile.formats.isEmpty ?? true)
    }
    private var exportTone: Color { exportReady ? CueWeaveStyle.ready : CueWeaveStyle.warning }
    private var bilingualBinding: Binding<BilingualMode> {
        Binding(
            get: { store.project?.exportProfile.bilingual ?? .originalOnly },
            set: { value in store.mutate { $0.exportProfile.bilingual = value } }
        )
    }
    private var offsetBinding: Binding<Int64> {
        Binding(
            get: { store.project?.exportProfile.offsetMS ?? 0 },
            set: { value in store.mutate { $0.exportProfile.offsetMS = value } }
        )
    }

    private func blockingReason(_ project: ProjectDocument) -> String {
        if !metadataReady { return "Add at least a title and one artist in Metadata." }
        if project.lyrics.lines.isEmpty { return "Fetch or import lyric text." }
        let missing = store.allSegments.count - alignedCount
        if missing > 0 { return "Set Final timing for \(missing) segment(s)." }
        if project.exportProfile.formats.isEmpty { return "Select at least one lyric output format." }
        return "Metadata, lyric timing and output formats are ready."
    }
}

private struct SummaryRow: View {
    let icon: String
    let title: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(title).frame(width: 84, alignment: .leading)
            Text(detail).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            StatusPill(text: ready ? "Ready" : "Pending", tone: ready ? CueWeaveStyle.ready : CueWeaveStyle.warning)
        }
        .font(.callout)
    }
}
