import SwiftUI

struct TranslationPage: View {
    @ObservedObject var store: ProjectStore
    @State private var showingImport = false
    @State private var targetLanguage = "Simplified Chinese"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeading("Translation", subtitle: "Line-level only · originals and timing stay untouched")
                Spacer()
                Button("Import Text…") { showingImport = true }
                    .disabled(store.project?.lyrics.lines.isEmpty != false || store.isBusy)
                Button("Clear All") { store.clearTranslations() }
                    .disabled(translationCount == 0 || store.isBusy)
                Button("Translate with \(store.alignmentProvider.title)") {
                    Task { await store.translateLyrics(targetLanguage: targetLanguage) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.project?.lyrics.lines.isEmpty != false
                    || store.alignmentAPIKey.isEmpty
                    || store.isBusy)
            }
            .padding(.horizontal, 20)
            .frame(height: 72)
            Divider()
            if store.project?.lyrics.lines.isEmpty != false {
                EmptyWorkspaceState(
                    title: "No lyric lines",
                    detail: "Import or fetch lyrics first. Translation is bound to those line IDs.",
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
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GEMINI").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        HStack {
                            StatusPill(
                                text: store.alignmentProvider.title,
                                tone: store.alignmentAPIKey.isEmpty ? CueWeaveStyle.warning : CueWeaveStyle.ready
                            )
                            StatusPill(
                                text: store.alignmentAPIKey.isEmpty ? "Key missing" : "Same key as Align",
                                tone: store.alignmentAPIKey.isEmpty ? CueWeaveStyle.warning : CueWeaveStyle.ready
                            )
                        }
                        Text("Uses the current alignment provider, model, and API key. The request is text-only — no target audio is uploaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Target language", text: $targetLanguage)
                            .textFieldStyle(.squareBorder)
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COVERAGE").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        StatusPill(
                            text: translationCount > 0
                                ? "\(translationCount) / \(store.project?.lyrics.lines.count ?? 0) lines"
                                : "None",
                            tone: translationCount > 0 ? CueWeaveStyle.ready : .secondary
                        )
                        Text("Import a plain-text or LRC translation, one line per original lyric. Extra lines are ignored; shorter imports leave the rest unchanged.")
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
                Text("LINE TRANSLATIONS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer()
                Text("\(store.project?.lyrics.lines.count ?? 0) LINES")
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
            TextField("Line translation", text: translationBinding)
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
    @Binding var isPresented: Bool
    @State private var translation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading("Import Translation", subtitle: "LRC timing is stripped · originals are not replaced")
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("TRANSLATION TEXT")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.project?.lyrics.lines.count ?? 0) original lines")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                TextEditor(text: $translation)
                    .font(.system(.body, design: .monospaced))
                    .overlay { Rectangle().stroke(.quaternary, lineWidth: 1) }
            }
            HStack {
                StatusPill(text: "Line order only", tone: CueWeaveStyle.accent)
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Apply") {
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
