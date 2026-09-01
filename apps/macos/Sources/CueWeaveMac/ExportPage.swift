import SwiftUI

struct ExportPage: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(l10n.t("export.title"), subtitle: l10n.t("page.export.subtitle"))
                if let project = store.project {
                    HStack(alignment: .top, spacing: 18) {
                        summary(project).frame(maxWidth: .infinity)
                        options(project).frame(width: 360)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(l10n.t("export.output")).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                            Text(l10n.t("export.outputHint"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(l10n.t("export.saveCueSheet")) { Task { await store.exportCueSheetInteractive() } }
                            .disabled(store.isBusy)
                        Button(l10n.t("export.exportFinal")) { Task { await store.exportInteractive() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(store.isBusy)
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
                HStack(spacing: 8) {
                    StatusPill(text: l10n.t("export.protectTarget"), tone: CueWeaveStyle.ready)
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
                Divider()
                Toggle(isOn: $store.overwriteExistingExport) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("export.overwriteExisting"))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text(l10n.t("export.overwriteExistingHint"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(l10n.t("export.adaptersNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

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
}
