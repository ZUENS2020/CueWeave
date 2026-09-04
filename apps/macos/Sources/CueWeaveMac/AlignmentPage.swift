import AppKit
import SwiftUI

struct AlignmentPage: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var waveform: WaveformModel
    @StateObject private var interaction: TimelineInteractionController
    @State private var selectedIDs = Set<UInt64>()
    @State private var keyMonitor: Any?
    @FocusState private var inspectorField: InspectorField?

    init(store: ProjectStore) {
        self.store = store
        waveform = store.waveform
        _interaction = StateObject(wrappedValue: TimelineInteractionController(store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.project?.creditIntroTooShort == true {
                HStack {
                    Text(l10n.t("credit.introTooShort"))
                        .font(.caption)
                    Spacer()
                    Button(l10n.t("credit.merge")) { store.mergeCredits() }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(CueWeaveStyle.warning.opacity(0.12))
            }
            Divider()
            if store.allSegments.isEmpty {
                EmptyWorkspaceState(
                    title: l10n.t("align.emptyTitle"),
                    detail: l10n.t("align.emptyDetail"),
                    icon: "waveform.path"
                )
            } else {
                HSplitView {
                    segmentSidebar.frame(minWidth: 200, idealWidth: 280, maxWidth: 340)
                    VStack(spacing: 0) {
                        TimelinePlaybackBar(store: store, interaction: interaction)
                        PlaybackTickBridge(player: store.player) {
                            interaction.playheadDidChange()
                        }
                        ZoomableTimeline(
                            store: store,
                            player: store.player,
                            waveform: waveform,
                            interaction: interaction
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        inspector.frame(minHeight: 180, idealHeight: 220, maxHeight: 260)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WindowAnchor { interaction.hostWindow = $0 })
        .onAppear {
            interaction.prepare()
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: inspectorField) { _, field in
            interaction.inspectorEditing = field != nil
            if field != nil { interaction.setFollowSelection(false) }
            interaction.resetHotkeys()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window === interaction.hostWindow {
                interaction.resetHotkeys()
            }
        }
        .onChange(of: store.allSegments.map(\.id)) { _, segmentIDs in
            selectedIDs.formIntersection(segmentIDs)
            interaction.reconcileSegments()
        }
    }

    private var header: some View {
        CueFlowLayout(spacing: 12) {
            SectionHeading(l10n.t("timeline.title"), subtitle: l10n.t("page.alignment.subtitle"))
            Button(l10n.t("align.restoreGemini")) {
                Task { await store.restoreGeminiAlignment() }
            }
            .disabled(store.isBusy || !store.hasGeminiSuggestions)
            .help(l10n.t("align.restoreHelp"))
            Button("\(store.alignmentProvider.title) · \(l10n.t("align.all"))") {
                Task { await store.align() }
            }
            .disabled(store.isBusy || store.alignmentAPIKey.isEmpty || store.allSegments.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
    }

    private var segmentSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(l10n.t("align.segments"))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text("\(store.allSegments.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if let credits = store.project?.creditCues, !credits.isEmpty {
                            Text(l10n.t("align.credits"))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                            ForEach(credits, id: \.id) { credit in
                                CreditQueueRow(
                                    text: credit.text,
                                    timeMS: credit.timeMS,
                                    isPrimary: interaction.selectedCreditID == credit.id,
                                    onSelect: { interaction.selectCredit(credit.id) },
                                    onStamp: { interaction.stampCredit(credit.id) }
                                )
                                Divider()
                            }
                            Text(l10n.t("align.lyricsSection"))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                        }
                        ForEach(store.allSegments) { segment in
                            SegmentQueueRow(
                                segment: segment,
                                isPrimary: interaction.selectedSegmentID == segment.id,
                                isPlaybackActive: interaction.activeSegmentID == segment.id,
                                isIncluded: selectedIDs.contains(segment.id),
                                onSelect: { interaction.select(segment.id) },
                                onJump: { interaction.jump(to: segment.id) },
                                onToggle: { toggleBatch(segment.id) },
                                onStamp: { interaction.stamp(segment.id) },
                                onClear: { store.clearFinal(segmentID: segment.id) }
                            )
                            .id(segment.id)
                            Divider()
                        }
                    }
                    .background(AlwaysVisibleScrollers())
                }
                .onChange(of: interaction.activeSegmentID) { _, segmentID in
                    revealQueueItem(segmentID, proxy: proxy)
                }
                .onChange(of: interaction.selectedSegmentID) { _, segmentID in
                    revealQueueItem(segmentID, proxy: proxy)
                }
            }
            Divider()
            VStack(spacing: 7) {
                CueFlowLayout(spacing: 6) {
                    Text(l10n.t("align.selected", String(selectedIDs.count)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(l10n.t("align.allBtn")) { selectedIDs.formUnion(store.allSegments.map(\.id)) }
                    Button(l10n.t("action.clear")) { selectedIDs.removeAll() }.disabled(selectedIDs.isEmpty)
                }
                HStack(spacing: 6) {
                    Spacer()
                    Button(l10n.t("align.clearFinal")) {
                        store.clearFinals(segmentIDs: selectedIDs)
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .controlSize(.small)
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var inspector: some View {
        ScrollView {
            Group {
                if let credit = selectedCredit {
                    creditInspector(credit)
                } else if let segment = selected {
                    unifiedInspector(segment)
                } else {
                    EmptyWorkspaceState(title: l10n.t("inspect.emptyTitle"), detail: l10n.t("inspect.emptyDetail"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(CueWeaveStyle.panel)
    }

    private func creditInspector(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("align.credits"))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(credit.displayText).font(.title3).textSelection(.enabled)
            CueFlowLayout(spacing: 8) {
                Text(cueTime(store.project?.creditTime(id: credit.id) ?? 0))
                    .font(.system(size: 11, design: .monospaced))
                Button(l10n.t("inspect.markPlayhead")) { interaction.stampCredit(credit.id) }
                Button("−50") { interaction.nudgeSelected(by: -50) }
                Button("−10") { interaction.nudgeSelected(by: -10) }
                Button("−1") { interaction.nudgeSelected(by: -1) }
                Button("+1") { interaction.nudgeSelected(by: 1) }
                Button("+10") { interaction.nudgeSelected(by: 10) }
                Button("+50") { interaction.nudgeSelected(by: 50) }
            }
            .controlSize(.small)
        }
    }

    private func inspectorHeader(_ segment: LyricSegment) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("inspect.segment", String(format: "%04llu", segment.id)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(segment.text).font(.title3).textSelection(.enabled)
                if let translation = translation(for: segment.id) {
                    Text(translation).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func unifiedInspector(_ segment: LyricSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader(segment)
            CueFlowLayout(spacing: 8) {
                timingReadouts(segment)
                    .frame(width: 270)
                Button("−50") { interaction.nudgeSelected(by: -50) }
                Button("−10") { interaction.nudgeSelected(by: -10) }
                Button("−1") { interaction.nudgeSelected(by: -1) }
                Button("+1") { interaction.nudgeSelected(by: 1) }
                Button("+10") { interaction.nudgeSelected(by: 10) }
                Button("+50") { interaction.nudgeSelected(by: 50) }
                Button(l10n.t("inspect.playAround")) { playAround(segment) }
                Button(l10n.t("inspect.useGemini")) { store.acceptGeminiSuggestion(segmentID: segment.id) }
                    .disabled(segment.timing.gemini == nil)
            }
            .controlSize(.small)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            inspectorField(l10n.t("inspect.lyricText"), placeholder: l10n.t("inspect.lyricPlaceholder"), text: originalLineBinding(segment.id), field: .original)
        }
    }

    private func inspectorField(_ title: String, placeholder: String, text: Binding<String>, field: InspectorField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .semibold, design: .monospaced))
            TextField(placeholder, text: text)
                .textFieldStyle(.squareBorder)
                .focused($inspectorField, equals: field)
                .onSubmit { resignInspectorFocus() }
                .onExitCommand { resignInspectorFocus() }
        }
        .frame(maxWidth: .infinity)
    }

    private func timingReadouts(_ segment: LyricSegment) -> some View {
        HStack(spacing: 12) {
            LayerReadout(name: "GEMINI", point: segment.timing.gemini, tone: CueWeaveStyle.gemini)
            LayerReadout(name: "FINAL", point: segment.timing.finalPoint, tone: .primary)
        }
    }

    private func lyricLine(for segmentID: UInt64) -> LyricLine? {
        store.project?.lyrics.lines.first { $0.segments.contains { $0.id == segmentID } }
    }

    private func originalLineBinding(_ segmentID: UInt64) -> Binding<String> {
        Binding(
            get: { lyricLine(for: segmentID)?.original ?? "" },
            set: { value in
                if let line = lyricLine(for: segmentID) { store.updateLine(line.id, original: value) }
            }
        )
    }

    private var selected: LyricSegment? {
        store.allSegments.first { $0.id == interaction.selectedSegmentID }
    }

    private var selectedCredit: Credit? {
        store.project?.lyrics.credits.first { $0.id == interaction.selectedCreditID }
    }

    private func revealQueueItem(_ segmentID: UInt64?, proxy: ScrollViewProxy) {
        guard let segmentID,
              let index = store.allSegments.firstIndex(where: { $0.id == segmentID })
        else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(segmentID, anchor: index < 2 ? .top : .center)
        }
    }

    private func translation(for segmentID: UInt64) -> String? {
        store.project?.lyrics.lines.first { $0.segments.contains { $0.id == segmentID } }?.translation
    }

    private func toggleBatch(_ id: UInt64) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func playAround(_ segment: LyricSegment) {
        guard let time = segment.timing.finalPoint?.timeMS ?? segment.timing.gemini?.timeMS else { return }
        interaction.seek(toSeconds: max(0, Double(time) / 1000 - 2))
        if !store.player.isPlaying { store.player.playPause() }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown]) { event in
            guard let host = interaction.hostWindow, host.isKeyWindow,
                  NSApp.modalWindow == nil, host.attachedSheet == nil,
                  event.window == nil || event.window === host else {
                interaction.resetHotkeys()
                return event
            }
            if event.type == .leftMouseDown {
                interaction.resetHotkeys()
                if (inspectorField != nil || interaction.inspectorEditing || Self.isEditingText())
                    && !Self.hitIsTextInput(event)
                {
                    resignInspectorFocus()
                }
                return event
            }
            if AlignmentPage.isEditingText() { interaction.resetHotkeys(); return event }
            let input = TimelineHotkeyInput(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers ?? "",
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option),
                control: event.modifierFlags.contains(.control),
                isKeyUp: event.type == .keyUp,
                isRepeat: event.isARepeat
            )
            return interaction.handleHotkey(input) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        interaction.resetHotkeys()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func resignInspectorFocus() {
        inspectorField = nil
        interaction.inspectorEditing = false
        guard let window = interaction.hostWindow ?? NSApp.keyWindow else { return }
        window.endEditing(for: nil)
        window.makeFirstResponder(window.contentView)
    }

    private static func isEditingText() -> Bool {
        var responder = NSApp.keyWindow?.firstResponder
        while let current = responder {
            if current is NSTextView || current is NSTextField { return true }
            responder = current.nextResponder
        }
        return false
    }

    private static func hitIsTextInput(_ event: NSEvent) -> Bool {
        guard let content = event.window?.contentView else { return false }
        let point = content.convert(event.locationInWindow, from: nil)
        var view: NSView? = content.hitTest(point)
        while let current = view {
            if isTextInputView(current) { return true }
            view = current.superview
        }
        return false
    }

    private static func isTextInputView(_ view: NSView) -> Bool {
        if view is NSTextView || view is NSTextField { return true }
        let name = NSStringFromClass(type(of: view))
        return name.contains("TextField") || name.contains("TextView")
    }
}

private struct TimelinePlaybackBar: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var player: AudioPlayer
    @ObservedObject var interaction: TimelineInteractionController
    @ObservedObject private var l10n = L10n.shared

    init(store: ProjectStore, interaction: TimelineInteractionController) {
        self.store = store
        player = store.player
        self.interaction = interaction
    }

    var body: some View {
        CueFlowLayout(spacing: 8) {
            Button { player.playPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            Picker(
                l10n.t("playback.speed"),
                selection: Binding(get: { player.playbackRate }, set: { player.setPlaybackRate($0) })
            ) {
                ForEach(AudioPlayer.supportedRates, id: \.self) { rate in
                    Text(String(format: "%.2f×", rate)).tag(rate)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 76)
            .help(l10n.t("playback.speedHelp"))
            Button("A") { player.markLoopStart() }.help(l10n.t("loop.a.help"))
            Button("B") { player.markLoopEnd() }.help(l10n.t("loop.b.help"))
            Button(l10n.t("action.clear")) { player.clearLoop() }.disabled(player.loopStart == nil && player.loopEnd == nil)
            Toggle(isOn: $interaction.followPlayback) {
                Label(l10n.t("follow"), systemImage: "location.fill")
            }
            .toggleStyle(.button)
            .help(l10n.t("follow.help"))
            Toggle(
                isOn: Binding(
                    get: { interaction.followSelection },
                    set: { interaction.setFollowSelection($0) }
                )
            ) {
                Label(l10n.t("next"), systemImage: "forward.end")
            }
            .toggleStyle(.button)
            .help(l10n.t("next.help"))
            Button(l10n.t("mark")) { stampCurrent() }
            .disabled(interaction.selectedSegmentID == nil && interaction.selectedCreditID == nil)
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!store.canUndo)
                .help(l10n.t("undo.help"))
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo)
                .help(l10n.t("redo.help"))
            Menu {
                Button(l10n.t("hotkey.play")) { player.playPause() }
                Button(l10n.t("hotkey.selectPlaying")) { interaction.selectCurrent() }
                Button(l10n.t("hotkey.selectNext")) { interaction.selectRelativeToPlayhead(offset: 1) }
                Button(l10n.t("hotkey.selectPrev")) { interaction.selectRelativeToPlayhead(offset: -1) }
                Button(l10n.t("hotkey.followNext")) {
                    interaction.setFollowSelection(!interaction.followSelection)
                }
                Button(l10n.t("hotkey.mark")) { stampCurrent() }
                Button(l10n.t("hotkey.clearFinal")) {
                    if let id = interaction.selectedSegmentID { store.clearFinal(segmentID: id) }
                }
                .disabled(selected?.timing.finalPoint == nil)
                Text(l10n.t("hotkey.nextPrev"))
                Text(l10n.t("hotkey.movePlayhead"))
                Text(l10n.t("hotkey.nudge1"))
                Text(l10n.t("hotkey.nudge10"))
                Text(l10n.t("hotkey.nudge50"))
                Text(l10n.t("hotkey.nudgeComma"))
                Text(l10n.t("hotkey.jump"))
                Text(l10n.t("hotkey.speed"))
                Text(l10n.t("hotkey.zoom"))
                Text(l10n.t("hotkey.clickAway"))
                Divider()
                Button(l10n.t("hotkey.loopA")) { player.markLoopStart() }
                Button(l10n.t("hotkey.loopB")) { player.markLoopEnd() }
                Button(l10n.t("hotkey.loopClear")) { player.clearLoop() }
            } label: {
                Image(systemName: "keyboard")
            }
            .help(l10n.t("hotkeys.help"))
            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass")
                Slider(
                    value: Binding(get: { interaction.zoom }, set: { interaction.setZoom($0) }),
                    in: 1 ... TimelineInteractionMath.maximumZoom,
                    step: 0.5
                )
                .frame(width: 110)
                Image(systemName: "plus.magnifyingglass")
                Text("\(interaction.zoom.formatted(.number.precision(.fractionLength(1))))×")
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 40)
            }
            Text(cueTime(UInt64(max(0, player.currentTime) * 1000)))
                .font(.system(size: 11, design: .monospaced))
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var selected: LyricSegment? {
        store.allSegments.first { $0.id == interaction.selectedSegmentID }
    }

    private func stampCurrent() {
        if let creditID = interaction.selectedCreditID {
            interaction.stampCredit(creditID)
            return
        }
        guard let id = interaction.selectedSegmentID ?? store.allSegments.first?.id else { return }
        interaction.stamp(id)
    }
}

private struct PlaybackTickBridge: View {
    @ObservedObject var player: AudioPlayer
    var onTick: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: player.currentTime) { _, _ in onTick() }
            .accessibilityHidden(true)
    }
}

private enum InspectorField: Hashable {
    case original
}

private struct WindowAnchor: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(view.window) }
    }
}
