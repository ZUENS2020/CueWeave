import AppKit
import SwiftUI

struct AlignmentPage: View {
    @ObservedObject var store: ProjectStore
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
            Divider()
            if store.allSegments.isEmpty {
                EmptyWorkspaceState(
                    title: "No lyric segments",
                    detail: "Fetch or import lyrics before opening the timeline.",
                    icon: "waveform.path"
                )
            } else {
                HSplitView {
                    segmentSidebar.frame(minWidth: 230, idealWidth: 280, maxWidth: 340)
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
                        Divider()
                        inspector.frame(minHeight: 210, idealHeight: 230, maxHeight: 260)
                    }
                }
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
        }
        .onChange(of: store.allSegments.map(\.id)) { _, segmentIDs in
            selectedIDs.formIntersection(segmentIDs)
            interaction.reconcileSegments()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            SectionHeading("Timeline", subtitle: "Target audio is the only timing authority")
            Spacer()
            Button("Restore Gemini") {
                Task { await store.restoreGeminiAlignment() }
            }
            .disabled(store.isBusy || !store.hasGeminiSuggestions)
            .help("Replace every Final value with the stored Gemini baseline. Undo with ⌘Z.")
            Button("\(store.alignmentProvider.title) · Align All") {
                Task { await store.align() }
            }
            .disabled(store.isBusy || store.alignmentAPIKey.isEmpty || store.allSegments.isEmpty)
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
    }

    private var segmentSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SEGMENTS")
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
                    LazyVStack(spacing: 0) {
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
                }
                .onChange(of: interaction.activeSegmentID) { _, segmentID in
                    guard let segmentID,
                          store.allSegments.contains(where: { $0.id == segmentID })
                    else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(segmentID, anchor: .center)
                    }
                }
                .onChange(of: interaction.selectedSegmentID) { _, segmentID in
                    guard let segmentID,
                          store.allSegments.contains(where: { $0.id == segmentID })
                    else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(segmentID, anchor: .center)
                    }
                }
            }
            Divider()
            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Text("\(selectedIDs.count) SELECTED")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("All") { selectedIDs.formUnion(store.allSegments.map(\.id)) }
                    Button("Clear") { selectedIDs.removeAll() }.disabled(selectedIDs.isEmpty)
                }
                HStack(spacing: 6) {
                    Spacer()
                    Button("Clear Final") {
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

    @ViewBuilder
    private var inspector: some View {
        if let segment = selected {
            unifiedInspector(segment)
            .padding(14)
            .background(CueWeaveStyle.panel)
        } else {
            EmptyWorkspaceState(title: "Select a segment", detail: "Choose a lyric segment to inspect its timing.")
        }
    }

    private func inspectorHeader(_ segment: LyricSegment) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SEGMENT \(String(format: "%04llu", segment.id))")
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
            HStack(spacing: 8) {
                timingReadouts(segment)
                    .frame(minWidth: 240, idealWidth: 270, maxWidth: 300)
                Divider().frame(height: 34)
                Button("Mark at Playhead") { interaction.stamp(segment.id) }
                Button("−50") { interaction.nudgeSelected(by: -50) }
                Button("−10") { interaction.nudgeSelected(by: -10) }
                Button("−1") { interaction.nudgeSelected(by: -1) }
                Button("+1") { interaction.nudgeSelected(by: 1) }
                Button("+10") { interaction.nudgeSelected(by: 10) }
                Button("+50") { interaction.nudgeSelected(by: 50) }
                Spacer(minLength: 4)
                Button("Play −2s") { playAround(segment) }
                Button("Use Gemini") { store.acceptGeminiSuggestion(segmentID: segment.id) }
                    .disabled(segment.timing.gemini == nil)
                Button("Clear Final") { store.clearFinal(segmentID: segment.id) }
                    .disabled(segment.timing.finalPoint == nil)
            }
            .controlSize(.small)
            inspectorField("LYRIC TEXT", placeholder: "Original lyric line", text: originalLineBinding(segment.id), field: .original)
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
            if NSApp.modalWindow != nil { return event }
            if let host = interaction.hostWindow, event.window != nil, event.window !== host { return event }
            if event.type == .leftMouseDown {
                if (inspectorField != nil || interaction.inspectorEditing || Self.isEditingText())
                    && !Self.hitIsTextInput(event)
                {
                    resignInspectorFocus()
                }
                return event
            }
            if AlignmentPage.isEditingText() { return event }
            if event.modifierFlags.contains(.command) {
                let chars = event.charactersIgnoringModifiers ?? ""
                let isZoom = chars == "+" || chars == "=" || chars == "-" || chars == "_"
                if !isZoom { return event }
            }
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

    init(store: ProjectStore, interaction: TimelineInteractionController) {
        self.store = store
        player = store.player
        self.interaction = interaction
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { player.playPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            Picker(
                "Playback Speed",
                selection: Binding(get: { player.playbackRate }, set: { player.setPlaybackRate($0) })
            ) {
                ForEach(AudioPlayer.supportedRates, id: \.self) { rate in
                    Text(String(format: "%.2f×", rate)).tag(rate)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 76)
            .help("Playback speed with pitch preservation. = faster, − slower")
            Button("A") { player.markLoopStart() }.help("Set the left loop boundary (A)")
            Button("B") { player.markLoopEnd() }.help("Set the right loop boundary (B)")
            Button("Clear") { player.clearLoop() }.disabled(player.loopStart == nil && player.loopEnd == nil)
            Toggle(isOn: $interaction.followPlayback) {
                Label("Follow", systemImage: "location.fill")
            }
            .toggleStyle(.button)
            .help("Keep the playback position centered while audio is playing")
            Toggle(
                isOn: Binding(
                    get: { interaction.followSelection },
                    set: { interaction.setFollowSelection($0) }
                )
            ) {
                Label("Next", systemImage: "forward.end")
            }
            .toggleStyle(.button)
            .help("Keep the selected lyric on the next line after the playhead. Turns off if you click a lyric or use Return, ↑↓, or ⇧Tab")
            Divider().frame(height: 18)
            Button("Mark") { stampCurrent() }
            .disabled(interaction.selectedSegmentID == nil)
            Divider().frame(height: 18)
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!store.canUndo)
                .help("Undo (⌘Z)")
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo)
                .help("Redo (⇧⌘Z)")
            Menu {
                Button("Play / Pause   Space") { player.playPause() }
                Button("Select Playing Lyric   Return") { interaction.selectCurrent() }
                Button("Select Next Playing Lyric   Tab") { interaction.selectRelativeToPlayhead(offset: 1) }
                Button("Select Previous Playing Lyric   ⇧Tab") { interaction.selectRelativeToPlayhead(offset: -1) }
                Button("Place Final at Playhead   M") { stampCurrent() }
                Button("Clear Final   Delete") {
                    if let id = interaction.selectedSegmentID { store.clearFinal(segmentID: id) }
                }
                .disabled(selected?.timing.finalPoint == nil)
                Text("Next / Previous Selected   ↓ / ↑")
                Text("Move Playhead   ← / → (1% of visible time)")
                Text("Hold 1 + ←/→   −/+ 1 ms")
                Text("Hold 2 + ←/→   −/+ 10 ms")
                Text("Hold 3 + ←/→   −/+ 50 ms")
                Text("Nudge 1 ms   , / .")
                Text("Jump   Home / End")
                Text("Playback Speed   = / −")
                Text("Zoom   ⌘+ / ⌘−, pinch, or Ctrl+wheel")
                Text("Click empty space to leave a text field")
                Divider()
                Button("Loop Start   A") { player.markLoopStart() }
                Button("Loop End   B") { player.markLoopEnd() }
                Button("Clear Loop   Esc") { player.clearLoop() }
            } label: {
                Image(systemName: "keyboard")
            }
            .help("Keyboard controls")
            Divider().frame(height: 18)
            Image(systemName: "minus.magnifyingglass")
            Slider(
                value: Binding(get: { interaction.zoom }, set: { interaction.setZoom($0) }),
                in: 1 ... TimelineInteractionMath.maximumZoom,
                step: 0.5
            )
            .frame(width: 130)
            Image(systemName: "plus.magnifyingglass")
            Text("\(interaction.zoom.formatted(.number.precision(.fractionLength(1))))×")
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 34)
            Spacer()
            Text(cueTime(UInt64(max(0, player.currentTime) * 1000)))
                .font(.system(size: 11, design: .monospaced))
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(.bar)
    }

    private var selected: LyricSegment? {
        store.allSegments.first { $0.id == interaction.selectedSegmentID }
    }

    private func stampCurrent() {
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
