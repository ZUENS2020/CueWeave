import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    let documentURL: URL?
    @Environment(\.undoManager) private var undoManager
    @State private var showingSettings = false

    var body: some View {
        Group {
            if store.project == nil {
                WelcomeView(store: store)
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    VStack(spacing: 0) {
                        workspaceHeader
                        Divider()
                        page.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(CueWeaveStyle.workspace)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { PlaybackStatusBar(store: store) }
            }
        }
        .tint(CueWeaveStyle.accent)
        .focusedSceneValue(\.cueWeaveStore, store)
        .onAppear { store.attachDocument(url: documentURL, undoManager: undoManager) }
        .onChange(of: documentURL) { _, url in
            store.attachDocument(url: url, undoManager: undoManager)
        }
        .onChange(of: undoManagerID) { _, _ in
            store.updateUndoManager(undoManager)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await store.createInteractive() } } label: {
                    Label(l10n.t("action.new"), systemImage: "plus")
                }
                .help(l10n.t("action.new"))
                Button { store.openInteractive() } label: {
                    Label(l10n.t("action.open"), systemImage: "square.and.arrow.down")
                }
                .help(l10n.t("action.open"))
                Button { store.undo() } label: {
                    Label(l10n.t("action.undo"), systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)
                Button { store.redo() } label: {
                    Label(l10n.t("action.redo"), systemImage: "arrow.uturn.forward")
                }
                .disabled(!store.canRedo)
                Button { showingSettings = true } label: {
                    Label(l10n.t("action.settings"), systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, isPresented: $showingSettings)
        }
        .alert(
            "CueWeave",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button(l10n.t("action.ok")) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? l10n.t("error.unknown"))
        }
    }

    private var undoManagerID: String {
        undoManager.map { String(ObjectIdentifier($0).hashValue) } ?? "none"
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CUEWEAVE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(store.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                Text(store.projectPath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            Divider()
            List(WorkspacePage.allCases, selection: $store.selection) { page in
                SidebarRow(page: page)
                    .tag(page)
            }
            .listStyle(.sidebar)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("chrome.alignment"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(store.alignmentProvider.title)
                        .font(.system(size: 11, design: .monospaced))
                }
                Spacer()
                Circle()
                    .fill(store.alignmentAPIKey.isEmpty ? Color.secondary : CueWeaveStyle.ready)
                    .frame(width: 7, height: 7)
            }
            .padding(14)
        }
        .navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 260)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selection.title.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(store.selection.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(
                text: store.saveState,
                tone: store.hasUnsavedChanges ? CueWeaveStyle.warning : CueWeaveStyle.ready
            )
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(.bar)
    }

    @ViewBuilder
    private var page: some View {
        switch store.selection {
        case .source: SourcePage(store: store)
        case .metadata: MetadataPage(store: store)
        case .lyrics: LyricsPage(store: store)
        case .translation: TranslationPage(store: store)
        case .alignment: AlignmentPage(store: store)
        case .export: ExportPage(store: store)
        }
    }
}

private struct PlaybackStatusBar: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var player: AudioPlayer
    @ObservedObject private var l10n = L10n.shared

    init(store: ProjectStore) {
        self.store = store
        player = store.player
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { player.playPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            Text(time(player.currentTime))
            Text("/").foregroundStyle(.tertiary)
            Text(time(player.duration)).foregroundStyle(.secondary)
            if let start = player.loopStart, let end = player.loopEnd, end > start {
                Divider().frame(height: 14)
                Text(l10n.t("loop.status", time(start), time(end)))
                    .foregroundStyle(CueWeaveStyle.accent)
            }
            Spacer()
            if store.isBusy {
                ProgressView().controlSize(.small)
                Button(l10n.t("action.cancel")) { store.cancelOperation() }.buttonStyle(.plain)
            }
            Text(store.activity).foregroundStyle(.secondary)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func time(_ value: TimeInterval) -> String {
        let milliseconds = UInt64(max(0, value) * 1000)
        return String(format: "%02llu:%02llu.%03llu", milliseconds / 60_000, milliseconds / 1_000 % 60, milliseconds % 1_000)
    }
}

private struct SidebarRow: View {
    @ObservedObject private var l10n = L10n.shared
    let page: WorkspacePage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: page.icon).frame(width: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                Text(page.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct WelcomeView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Text(l10n.t("welcome.kicker"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(l10n.t("welcome.headline"))
                    .font(.system(size: 38, weight: .semibold))
                    .tracking(-1.1)
                Text(l10n.t("welcome.body"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520, alignment: .leading)
                HStack(spacing: 10) {
                    Button(l10n.t("welcome.new")) { Task { await store.createInteractive() } }
                        .controlSize(.large)
                    Button(l10n.t("welcome.open")) { store.openInteractive() }
                        .controlSize(.large)
                }
                Spacer()
                Text(l10n.t("welcome.pipeline"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(64)
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(CueWeaveStyle.accent.opacity(0.08))
                .frame(width: 240)
                .overlay {
                    VStack(spacing: 10) {
                        ForEach(0 ..< 9, id: \.self) { index in
                            Rectangle()
                                .fill(index == 4 ? CueWeaveStyle.accent : Color.secondary.opacity(0.16))
                                .frame(width: index == 4 ? 120 : 74, height: 1)
                        }
                    }
                }
        }
        .background(CueWeaveStyle.workspace)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(l10n.t("settings.language"), subtitle: l10n.t("settings.languageHint"))
            Picker(l10n.t("settings.language"), selection: $store.uiLanguage) {
                Text(l10n.t("lang.system")).tag("system")
                Text(l10n.t("lang.en")).tag("en")
                Text(l10n.t("lang.zh")).tag("zh")
            }
            .pickerStyle(.segmented)
            .onChange(of: store.uiLanguage) { _, _ in store.applyUiLanguage() }
            SectionHeading(l10n.t("settings.title"), subtitle: l10n.t("settings.subtitle"))
            Picker(l10n.t("settings.provider"), selection: $store.alignmentProvider) {
                ForEach(AlignmentProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text(l10n.t("settings.apiKey")).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    SecureField(l10n.t("settings.pasteKey"), text: selectedKey)
                    Link(l10n.t("action.create"), destination: keyURL)
                }
                GridRow {
                    Text(l10n.t("settings.model")).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    TextField(l10n.t("settings.modelPlaceholder"), text: selectedModel)
                        .font(.system(.body, design: .monospaced))
                    Button(l10n.t("action.default")) { resetModel() }
                }
            }
            HStack(spacing: 8) {
                StatusPill(
                    text: selectedKey.wrappedValue.isEmpty ? l10n.t("settings.keyMissing") : l10n.t("settings.keyStored"),
                    tone: selectedKey.wrappedValue.isEmpty ? CueWeaveStyle.warning : CueWeaveStyle.ready
                )
                Button(l10n.t("settings.clearKey"), role: .destructive) {
                    store.clearAPIKey(for: store.alignmentProvider)
                }
                .disabled(selectedKey.wrappedValue.isEmpty)
            }
            Divider()
            Text(l10n.t("settings.keysNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(store.settingsPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button(l10n.t("action.cancel")) { isPresented = false }
                Button(l10n.t("action.save")) {
                    store.persistSettings()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 600)
    }

    private var selectedKey: Binding<String> {
        store.alignmentProvider == .openRouter ? $store.openRouterAPIKey : $store.aiStudioAPIKey
    }

    private var selectedModel: Binding<String> {
        store.alignmentProvider == .openRouter ? $store.openRouterModel : $store.aiStudioModel
    }

    private var keyURL: URL {
        URL(string: store.alignmentProvider == .openRouter
            ? "https://openrouter.ai/settings/keys"
            : "https://aistudio.google.com/app/apikey")!
    }

    private func resetModel() {
        if store.alignmentProvider == .openRouter {
            store.openRouterModel = "google/gemini-3.7-flash"
        } else {
            store.aiStudioModel = "gemini-3.7-flash"
        }
    }
}
