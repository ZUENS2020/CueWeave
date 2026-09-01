import SwiftUI

struct LyricsPage: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    @State private var showingImport = false
    @State private var showingInsert = false
    @State private var showingPreview = false
    @State private var insertAnchor: InsertAnchor?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeading(l10n.t("page.lyrics"), subtitle: l10n.t("page.lyrics.subtitle"))
                Spacer()
                Button(l10n.t("lyrics.requestPreview")) { showingPreview = true }
                    .disabled(store.allSegments.isEmpty)
                Button(l10n.t("lyrics.addLines")) { showingInsert = true }
                    .disabled(store.isBusy)
                Button(l10n.t("lyrics.import")) { showingImport = true }
                Button(l10n.t("lyrics.fetchNetease")) { Task { await store.fetchLyrics() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.project?.source?.musicID == nil || store.isBusy)
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
            LyricsTextSheet(store: store, isPresented: $showingImport, mode: .replace)
        }
        .sheet(isPresented: $showingInsert) {
            LyricsTextSheet(
                store: store,
                isPresented: $showingInsert,
                mode: .insert(after: store.project?.lyrics.lines.last?.id)
            )
        }
        .sheet(isPresented: $showingPreview) {
            AlignmentRequestPreview(store: store, isPresented: $showingPreview)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            EmptyWorkspaceState(
                title: l10n.t("lyrics.emptyTitle"),
                detail: l10n.t("lyrics.emptyDetail"),
                icon: "text.quote"
            )
            HStack {
                Button(l10n.t("lyrics.addLines")) { showingInsert = true }
                    .disabled(store.isBusy)
                Button(l10n.t("lyrics.import")) { showingImport = true }
                Button(l10n.t("lyrics.fetchNetease")) { Task { await store.fetchLyrics() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.project?.source?.musicID == nil)
            }
            Spacer()
        }
        .padding(34)
    }

    private var sourceAndCredits: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(l10n.t("lyrics.credits")).font(.system(size: 10, weight: .semibold, design: .monospaced))
                            Spacer()
                            Button { store.addCredit() } label: { Image(systemName: "plus") }
                                .buttonStyle(.plain)
                        }
                        if store.project?.lyrics.credits.isEmpty != false {
                            Text(l10n.t("lyrics.noCredits"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(store.project?.lyrics.credits ?? []) { credit in
                            HStack(spacing: 6) {
                                TextField(
                                    l10n.t("lyrics.role"),
                                    text: Binding(
                                        get: { store.project?.lyrics.credits.first { $0.id == credit.id }?.label ?? credit.label },
                                        set: { store.updateCredit(id: credit.id, label: $0) }
                                    )
                                )
                                .frame(width: 76)
                                TextField(
                                    l10n.t("lyrics.name"),
                                    text: Binding(
                                        get: { store.project?.lyrics.credits.first { $0.id == credit.id }?.value ?? credit.value },
                                        set: { store.updateCredit(id: credit.id, value: $0) }
                                    )
                                )
                                Button { store.removeCredit(id: credit.id) } label: {
                                    Image(systemName: "minus")
                                }
                                .buttonStyle(.plain)
                            }
                            .textFieldStyle(.squareBorder)
                        }
                        Text(l10n.t("lyrics.creditsNote"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n.t("lyrics.translation")).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        StatusPill(
                            text: translationCount > 0 ? l10n.t("lyrics.translationCount", String(translationCount)) : l10n.t("lyrics.optional"),
                            tone: translationCount > 0 ? CueWeaveStyle.ready : .secondary
                        )
                        Text(l10n.t("lyrics.translationHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(l10n.t("lyrics.openTranslation")) { store.selection = .translation }
                            .disabled(store.project?.lyrics.lines.isEmpty != false)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var lyricEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text(l10n.t("lyrics.lines"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer()
                Text(l10n.t("lyrics.linesMeta", String(store.project?.lyrics.lines.count ?? 0), String(store.allSegments.count)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    LyricInsertGap(
                        store: store,
                        afterLineID: nil,
                        isActive: insertAnchor == .start,
                        onBegin: { insertAnchor = .start },
                        onCancel: { insertAnchor = nil }
                    )
                    ForEach(store.project?.lyrics.lines ?? []) { line in
                        LyricLineEditor(store: store, line: line)
                        LyricInsertGap(
                            store: store,
                            afterLineID: line.id,
                            isActive: insertAnchor == .after(line.id),
                            onBegin: { insertAnchor = .after(line.id) },
                            onCancel: { insertAnchor = nil }
                        )
                    }
                }
            }
        }
    }

    private var translationCount: Int {
        store.project?.lyrics.lines.filter { $0.translation?.isEmpty == false }.count ?? 0
    }
}

private enum InsertAnchor: Equatable {
    case start
    case after(UInt64)
}

private struct LyricLineEditor: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    let line: LyricLine

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(String(format: "%03llu", line.id))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                TextField(l10n.t("lyrics.originalPlaceholder"), text: originalBinding)
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

private struct LyricInsertGap: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    let afterLineID: UInt64?
    let isActive: Bool
    let onBegin: () -> Void
    let onCancel: () -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isActive {
                HStack(spacing: 8) {
                    TextField(l10n.t("lyrics.insertPlaceholder"), text: $draft)
                        .font(.body)
                        .focused($focused)
                        .onSubmit { Task { await commit() } }
                    Button(l10n.t("lyrics.insertCommit")) { Task { await commit() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(l10n.t("action.cancel")) { onCancel() }
                        .buttonStyle(.plain)
                }
                .textFieldStyle(.squareBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .onAppear {
                    draft = ""
                    focused = true
                }
            } else {
                Button(action: onBegin) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text(l10n.t("lyrics.insertHere"))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
                .help(l10n.t("lyrics.insertHere"))
            }
        }
        Divider()
    }

    private func commit() async {
        guard await store.insertLyrics(after: afterLineID, text: draft) else { return }
        onCancel()
    }
}

private struct LyricsTextSheet: View {
    enum Mode {
        case replace
        case insert(after: UInt64?)
    }

    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    @Binding var isPresented: Bool
    let mode: Mode
    @State private var original = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title, subtitle: subtitle)
            editor(l10n.t("lyrics.original"), text: $original)
            HStack {
                StatusPill(text: l10n.t("lyrics.timingRejected"), tone: CueWeaveStyle.accent)
                Spacer()
                Button(l10n.t("action.cancel")) { isPresented = false }
                Button(commitTitle) {
                    Task {
                        switch mode {
                        case .replace:
                            await store.applyRawLyrics(original: original, translation: "")
                            isPresented = false
                        case .insert(let after):
                            if await store.insertLyrics(after: after, text: original) {
                                isPresented = false
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isBusy || original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 820, height: 520)
    }

    private var title: String {
        switch mode {
        case .replace: l10n.t("lyrics.importTitle")
        case .insert: l10n.t("lyrics.insertTitle")
        }
    }

    private var subtitle: String {
        switch mode {
        case .replace: l10n.t("lyrics.importSubtitle")
        case .insert: l10n.t("lyrics.insertSubtitle")
        }
    }

    private var commitTitle: String {
        switch mode {
        case .replace: l10n.t("lyrics.normalize")
        case .insert: l10n.t("lyrics.insertCommit")
        }
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
    @ObservedObject private var l10n = L10n.shared
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(l10n.t("lyrics.previewTitle"), subtitle: l10n.t("lyrics.previewSubtitle"))
                Spacer()
                Button(l10n.t("action.done")) { isPresented = false }
            }
            Panel {
                HStack {
                    StatusPill(text: l10n.t("lyrics.noSourceTiming"), tone: CueWeaveStyle.ready)
                    StatusPill(text: l10n.t("lyrics.noCreditsPill"), tone: CueWeaveStyle.ready)
                    StatusPill(text: l10n.t("lyrics.linesPill", String(store.project?.lyrics.lines.count ?? 0)), tone: CueWeaveStyle.accent)
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
