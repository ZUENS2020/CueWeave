import SwiftUI

struct LyricsPage: View {
    @ObservedObject var store: ProjectStore
    @State private var provider: LyricsProviderMode = .auto
    @State private var showingImport = false
    @State private var showingPreview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeading("Lyrics", subtitle: "Source text only · timing is always rebuilt")
                Spacer()
                Button("Request Preview") { showingPreview = true }
                    .disabled(store.allSegments.isEmpty)
                Button("Import Text…") { showingImport = true }
                Button(fetchTitle) { Task { await store.fetchLyrics() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(provider == .manual || store.project?.source?.musicID == nil || store.isBusy)
            }
            .padding(.horizontal, 20)
            .frame(height: 72)
            Divider()
            if store.project?.lyrics.lines.isEmpty != false {
                emptyState
            } else {
                HSplitView {
                    sourceAndCredits.frame(minWidth: 250, idealWidth: 300, maxWidth: 360)
                    lyricEditor
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            ImportLyricsSheet(store: store, isPresented: $showingImport)
        }
        .sheet(isPresented: $showingPreview) {
            AlignmentRequestPreview(store: store, isPresented: $showingPreview)
        }
    }

    private var fetchTitle: String { provider == .auto ? "Resolve Lyrics" : "Fetch NetEase" }

    private var emptyState: some View {
        VStack(spacing: 20) {
            EmptyWorkspaceState(
                title: "No lyric text",
                detail: "Resolve by NetEase musicId or import plain text, LRC or YRC. Every source timestamp will be removed.",
                icon: "text.quote"
            )
            providerControls.frame(maxWidth: 520)
            HStack {
                Button("Import Text…") { showingImport = true }
                Button(fetchTitle) { Task { await store.fetchLyrics() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(provider == .manual || store.project?.source?.musicID == nil)
            }
            Spacer()
        }
        .padding(34)
    }

    private var sourceAndCredits: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                providerControls
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CREDITS").font(.system(size: 10, weight: .semibold, design: .monospaced))
                            Spacer()
                            Button { store.addCredit() } label: { Image(systemName: "plus") }
                                .buttonStyle(.plain)
                        }
                        if store.project?.lyrics.credits.isEmpty != false {
                            Text("No credits detected")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array((store.project?.lyrics.credits ?? []).enumerated()), id: \.offset) { index, credit in
                            HStack(spacing: 6) {
                                TextField(
                                    "Role",
                                    text: Binding(
                                        get: { store.project?.lyrics.credits[safe: index]?.label ?? credit.label },
                                        set: { store.updateCredit(at: index, label: $0) }
                                    )
                                )
                                .frame(width: 76)
                                TextField(
                                    "Name",
                                    text: Binding(
                                        get: { store.project?.lyrics.credits[safe: index]?.value ?? credit.value },
                                        set: { store.updateCredit(at: index, value: $0) }
                                    )
                                )
                                Button { store.removeCredit(at: index) } label: {
                                    Image(systemName: "minus")
                                }
                                .buttonStyle(.plain)
                            }
                            .textFieldStyle(.squareBorder)
                        }
                        Text("Credits are preserved separately and are never sent to Gemini as sung lyrics.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRANSLATION").font(.system(size: 10, weight: .semibold, design: .monospaced))
                        StatusPill(
                            text: translationCount > 0 ? "\(translationCount) lines" : "Optional",
                            tone: translationCount > 0 ? CueWeaveStyle.ready : .secondary
                        )
                        Text("Gemini, text import, and line editing live on the Translation page. This page keeps original lyric text only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Translation") { store.selection = .translation }
                            .disabled(store.project?.lyrics.lines.isEmpty != false)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var providerControls: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text("LYRICS SOURCE").font(.system(size: 10, weight: .semibold, design: .monospaced))
                Picker("Provider", selection: $provider) {
                    ForEach(LyricsProviderMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(provider.detail).font(.caption).foregroundStyle(.secondary)
                if provider == .auto {
                    HStack {
                        StatusPill(text: "1 · NetEase", tone: CueWeaveStyle.ready)
                        StatusPill(text: "2 · Manual fallback", tone: .secondary)
                    }
                }
            }
        }
    }

    private var lyricEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LYRIC LINES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer()
                Text("\(store.project?.lyrics.lines.count ?? 0) LINES · \(store.allSegments.count) STABLE IDS")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.project?.lyrics.lines ?? []) { line in
                        LyricLineEditor(store: store, line: line)
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

private enum LyricsProviderMode: String, CaseIterable, Identifiable {
    case auto, netease, manual
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .auto: "Use the NCM musicId first; stop before any unavailable provider."
        case .netease: "Fetch directly from NetEase using the NCM musicId."
        case .manual: "Paste plain text, LRC or YRC; timing is stripped during import."
        }
    }
}

private struct LyricLineEditor: View {
    @ObservedObject var store: ProjectStore
    let line: LyricLine

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(String(format: "%03llu", line.id))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                TextField("Original lyric", text: originalBinding)
                    .font(.body)
                Text(String(format: "ID %04llu", line.segments.first?.id ?? 0))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .textFieldStyle(.squareBorder)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var currentLine: LyricLine? {
        store.project?.lyrics.lines.first { $0.id == line.id }
    }
    private var originalBinding: Binding<String> {
        Binding(get: { currentLine?.original ?? line.original }, set: { store.updateLine(line.id, original: $0) })
    }
}

private struct ImportLyricsSheet: View {
    @ObservedObject var store: ProjectStore
    @Binding var isPresented: Bool
    @State private var original = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading("Import Lyrics", subtitle: "LRC and YRC timing will be discarded")
            editor("ORIGINAL", text: $original)
            HStack {
                StatusPill(text: "Source timing rejected", tone: CueWeaveStyle.accent)
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Normalize & Replace") {
                    Task {
                        await store.applyRawLyrics(original: original, translation: "")
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 820, height: 520)
    }

    private func editor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            TextEditor(text: text).font(.system(.body, design: .monospaced))
                .overlay { Rectangle().stroke(.quaternary, lineWidth: 1) }
        }
    }
}

private struct AlignmentRequestPreview: View {
    @ObservedObject var store: ProjectStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading("Alignment Request", subtitle: "Exactly the lyric text sent with the target MP3")
                Spacer()
                Button("Done") { isPresented = false }
            }
            Panel {
                HStack {
                    StatusPill(text: "No source timing", tone: CueWeaveStyle.ready)
                    StatusPill(text: "No credits", tone: CueWeaveStyle.ready)
                    StatusPill(text: "\(store.project?.lyrics.lines.count ?? 0) lines", tone: CueWeaveStyle.accent)
                }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.project?.lyrics.lines ?? []) { line in
                        HStack {
                            Text(String(format: "%04llu", line.segments.first?.id ?? 0))
                                .foregroundStyle(.tertiary).frame(width: 52)
                            Text(line.original).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        Divider()
                    }
                }
            }
            .overlay { Rectangle().stroke(.quaternary, lineWidth: 1) }
        }
        .padding(22)
        .frame(width: 720, height: 560)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
