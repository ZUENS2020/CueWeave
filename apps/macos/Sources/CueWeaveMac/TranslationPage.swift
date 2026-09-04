import SwiftUI

struct TranslationPage: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    @State private var showingImport = false
    @State private var targetLanguage = ""

    var body: some View {
        VStack(spacing: 0) {
            CueFlowLayout(spacing: 10) {
                SectionHeading(l10n.t("page.translation"), subtitle: l10n.t("page.translation.subtitle"))
                Button(l10n.t("translation.import")) { showingImport = true }
                    .disabled(store.project?.lyrics.lines.isEmpty != false || store.isBusy)
                Button(l10n.t("translation.clearAll")) { store.clearTranslations() }
                    .disabled(translationCount == 0 || store.isBusy)
                Button(l10n.t("translation.translateWith", store.alignmentProvider.title)) {
                    Task { await store.translateLyrics(targetLanguage: targetLanguage) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.project?.lyrics.lines.isEmpty != false
                    || store.alignmentAPIKey.isEmpty
                    || store.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 72)
            Divider()
            if store.project?.lyrics.lines.isEmpty != false {
                EmptyWorkspaceState(
                    title: l10n.t("translation.emptyTitle"),
                    detail: l10n.t("translation.emptyDetail"),
                    icon: "translate"
                )
            } else {
                HSplitView {
                    controls.frame(minWidth: 250, idealWidth: 300, maxWidth: 360)
                    translationEditor
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportTranslationSheet(store: store, isPresented: $showingImport)
        }
        .onAppear {
            if targetLanguage.isEmpty { targetLanguage = l10n.t("translation.targetDefault") }
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(l10n.t("translation.gemini")).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        HStack {
                            StatusPill(
                                text: store.alignmentProvider.title,
                                tone: store.alignmentAPIKey.isEmpty ? CueWeaveStyle.warning : CueWeaveStyle.ready
                            )
                            StatusPill(
                                text: store.alignmentAPIKey.isEmpty ? l10n.t("settings.keyMissing") : l10n.t("translation.sameKey"),
                                tone: store.alignmentAPIKey.isEmpty ? CueWeaveStyle.warning : CueWeaveStyle.ready
                            )
                        }
                        Text(l10n.t("translation.geminiHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(l10n.t("translation.targetLanguage"), text: $targetLanguage)
                            .textFieldStyle(.squareBorder)
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n.t("translation.coverage")).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        StatusPill(
                            text: translationCount > 0
                                ? l10n.t("translation.coverageCount", String(translationCount), String(store.project?.lyrics.lines.count ?? 0))
                                : l10n.t("translation.none"),
                            tone: translationCount > 0 ? CueWeaveStyle.ready : .secondary
                        )
                        Text(l10n.t("translation.coverageHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var translationEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text(l10n.t("translation.lineHeader"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer()
                Text(l10n.t("translation.linesCount", String(store.project?.lyrics.lines.count ?? 0)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.project?.lyrics.lines ?? []) { line in
                        TranslationLineEditor(store: store, line: line)
                        Divider()
                    }
                }
            }
        }
    }

    private var translationCount: Int {
        store.project?.lyrics.lines.filter { $0.translation?.isEmpty == false }.count ?? 0
    }
}

private struct TranslationLineEditor: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    let line: LyricLine

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(String(format: "%03llu", line.id))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(currentLine?.original ?? line.original)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField(l10n.t("translation.placeholder"), text: translationBinding)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.squareBorder)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var currentLine: LyricLine? {
        store.project?.lyrics.lines.first { $0.id == line.id }
    }

    private var translationBinding: Binding<String> {
        Binding(
            get: { currentLine?.translation ?? "" },
            set: { store.updateLine(line.id, translation: $0) }
        )
    }
}

private struct ImportTranslationSheet: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    @Binding var isPresented: Bool
    @State private var translation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(l10n.t("translation.importTitle"), subtitle: l10n.t("translation.importSubtitle"))
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(l10n.t("translation.text"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(l10n.t("translation.originalLines", String(store.project?.lyrics.lines.count ?? 0)))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                TextEditor(text: $translation)
                    .font(.system(.body, design: .monospaced))
                    .overlay { Rectangle().stroke(.quaternary, lineWidth: 1) }
            }
            HStack {
                StatusPill(text: l10n.t("translation.lineOrder"), tone: CueWeaveStyle.accent)
                Spacer()
                Button(l10n.t("action.cancel")) { isPresented = false }
                Button(l10n.t("action.apply")) {
                    Task {
                        await store.applyRawTranslations(translation)
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 720, height: 520)
    }
}
