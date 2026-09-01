import SwiftUI

struct ExportPage: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionHeading(l10n.t("export.title"), subtitle: l10n.t("page.export.subtitle"))
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
                            Text(l10n.t("export.output")).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                            Text(l10n.t("export.outputHint"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(l10n.t("export.saveCueSheet")) { Task { await store.exportCueSheetInteractive() } }
                            .disabled(store.project?.lyrics.lines.isEmpty != false || store.isBusy)
                        Button(l10n.t("export.exportFinal")) { Task { await store.exportInteractive() } }
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
                        Text(project.metadata.draft.title ?? l10n.t("file.untitled"))
                            .font(.system(size: 24, weight: .semibold))
                        Text(project.metadata.draft.artists.joined(separator: " / "))
                            .foregroundStyle(.secondary)
                        Divider()
                        HStack(spacing: 26) {
                            DataReadout(label: l10n.t("meta.albumLabel"), value: project.metadata.draft.album ?? "—")
                            DataReadout(label: l10n.t("meta.albumArtistLabel"), value: project.metadata.draft.albumArtist ?? "—")
                            DataReadout(label: l10n.t("meta.release"), value: project.metadata.draft.date ?? "—")
                        }
                    }
                }
                Divider()
                Text(l10n.t("export.projectContent")).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                SummaryRow(
                    icon: "tag", title: l10n.t("page.metadata"),
                    detail: metadataReady ? l10n.t("export.metadataReady") : l10n.t("export.metadataMissing"),
                    ready: metadataReady
                )
                SummaryRow(
                    icon: "text.quote", title: l10n.t("page.lyrics"),
                    detail: l10n.t("export.lyricsDetail", String(project.lyrics.lines.count), String(store.allSegments.count), String(translationCount)),
                    ready: !project.lyrics.lines.isEmpty
                )
                SummaryRow(
                    icon: "waveform.path", title: l10n.t("page.alignment"),
                    detail: l10n.t("export.alignmentDetail", String(alignedCount), String(store.allSegments.count)),
                    ready: alignedCount == store.allSegments.count && !store.allSegments.isEmpty
                )
                SummaryRow(
                    icon: "waveform", title: l10n.t("export.audio"),
                    detail: l10n.t("export.audioDetail"),
                    ready: project.target != nil
                )
                Divider()
                HStack(spacing: 8) {
                    StatusPill(text: l10n.t("export.noOverwrite"), tone: CueWeaveStyle.ready)
                    StatusPill(text: l10n.t("export.noReencode"), tone: CueWeaveStyle.ready)
                    StatusPill(text: l10n.t("export.atomic"), tone: CueWeaveStyle.ready)
                }
            }
        }
    }

    private func options(_ project: ProjectDocument) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text(l10n.t("export.adapters")).font(.system(size: 10, weight: .semibold, design: .monospaced))
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
                Text(l10n.t("export.bilingual")).font(.system(size: 10, weight: .semibold, design: .monospaced))
                Picker(l10n.t("export.bilingual"), selection: bilingualBinding) {
                    ForEach(BilingualMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .labelsHidden()
                Divider()
                Stepper(
                    l10n.t("export.offset", String(project.exportProfile.offsetMS)),
                    value: offsetBinding,
                    in: -2_000 ... 2_000,
                    step: 10
                )
                .font(.system(size: 11, design: .monospaced))
                Text(l10n.t("export.adaptersNote"))
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
                    Text(exportReady ? l10n.t("export.ready") : l10n.t("export.blocked"))
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
        if !metadataReady { return l10n.t("export.block.metadata") }
        if project.lyrics.lines.isEmpty { return l10n.t("export.block.lyrics") }
        let missing = store.allSegments.count - alignedCount
        if missing > 0 { return l10n.t("export.block.final", String(missing)) }
        if project.exportProfile.formats.isEmpty { return l10n.t("export.block.formats") }
        return l10n.t("export.allReady")
    }
}

private struct SummaryRow: View {
    @ObservedObject private var l10n = L10n.shared
    let icon: String
    let title: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(title).frame(width: 84, alignment: .leading)
            Text(detail).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            StatusPill(text: ready ? l10n.t("pill.ready") : l10n.t("pill.pending"), tone: ready ? CueWeaveStyle.ready : CueWeaveStyle.warning)
        }
        .font(.callout)
    }
}
