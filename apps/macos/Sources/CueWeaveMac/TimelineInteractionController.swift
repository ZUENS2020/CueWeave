import AppKit
import Combine
import SwiftUI

@MainActor
final class TimelineInteractionController: ObservableObject {
    @Published private(set) var selectedCreditID: UInt64?
    @Published private(set) var inspectorSegmentID: UInt64?
    @Published private(set) var selectionRange: ClosedRange<Double>?
    @Published private(set) var zoom = 2.0
    @Published var followPlayback = true
    @Published var followSelection = false
    @Published var lanes = AudioLaneSettings()
    var inspectorEditing = false
    weak var hostWindow: NSWindow?

    let viewport = TimelineViewportProxy()
    let playbackHighlight = PlaybackHighlightModel()
    private let store: ProjectStore
    private let player: AudioPlayer
    private var hotkeys = TimelineHotkeyTranslator()
    private var cueIndex = PlaybackCueIndex()
    private var queueRevealPlanner = QueueRevealPlanner()
    private var playbackStateSubscription: AnyCancellable?

    var selectedSegmentID: UInt64? { playbackHighlight.state.selected }
    var activeSegmentID: UInt64? { playbackHighlight.state.active }

    init(store: ProjectStore) {
        self.store = store
        player = store.player
        playbackStateSubscription = player.$isPlaying
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                guard let self, !isPlaying else { return }
                inspectorSegmentID = selectedSegmentID
            }
    }

    func prepare() {
        reconcileSegments()
    }

    func reconcileSegments() {
        let segments = store.allSegments
        cueIndex.rebuild(segments: segments)
        queueRevealPlanner = QueueRevealPlanner()
        let ids = Set(cueIndex.orderedIDs)
        var selected = selectedSegmentID
        if let selectedSegmentID, !ids.contains(selectedSegmentID) {
            selected = nil
        } else if selectedSegmentID == nil {
            selected = cueIndex.orderedIDs.first
        }
        setHighlight(active: activeSegmentID, selected: selected)
        if inspectorSegmentID == nil || !ids.contains(inspectorSegmentID ?? 0) {
            inspectorSegmentID = selected
        }
        playheadDidChange()
    }

    func handle(_ event: TimelinePointerEvent) {
        switch event {
        case let .click(sample):
            if let creditID = hitCredit(at: sample.documentFraction) {
                selectCredit(creditID)
                return
            }
            selectionRange = nil
            selectedCreditID = nil
            seek(toFraction: sample.documentFraction)
        case let .selectionChanged(range):
            if selectionRange == nil { viewport.beginInteraction() }
            selectionRange = range
        case let .selectionCommitted(range):
            zoom(
                to: TimelineInteractionMath.rangeZoom(range),
                documentAnchor: (range.lowerBound + range.upperBound) / 2
            )
            selectionRange = nil
            viewport.endInteraction()
        case .zoomBegan:
            viewport.beginInteraction()
        case let .creditDrag(id, fraction):
            dragCredit(id, fraction: fraction)
        case let .zoom(delta, _):
            zoom(to: zoom * exp(delta * 2))
        case .zoomEnded:
            viewport.endInteraction()
        }
    }

    func playheadDidChange(frameHostTime: TimeInterval? = nil) {
        let currentMS = UInt64(max(0, player.currentTime) * 1_000)
        let nextActive = cueIndex.activeID(at: currentMS)
        var nextSelected = selectedSegmentID
        if followSelection {
            nextSelected = cueIndex.followingID(after: nextActive)
        }
        setHighlight(active: nextActive, selected: nextSelected)
        if followPlayback, player.isPlaying, selectionRange == nil, player.duration > 0 {
            viewport.center(
                on: player.presentationTime / player.duration,
                frameHostTime: frameHostTime
            )
        }
    }

    func select(_ segmentID: UInt64) {
        guard store.allSegments.contains(where: { $0.id == segmentID }) else { return }
        breakFollowSelection()
        selectedCreditID = nil
        setSelectedSegmentID(segmentID)
    }

    func selectCredit(_ creditID: UInt64) {
        guard store.project?.lyrics.credits.contains(where: { $0.id == creditID }) == true else { return }
        breakFollowSelection()
        selectedCreditID = creditID
        inspectorSegmentID = nil
        setSelectedSegmentID(nil)
    }

    func stampCredit(_ creditID: UInt64) {
        store.setCreditTime(id: creditID, milliseconds: UInt64(max(0, player.currentTime * 1_000)))
        selectedCreditID = creditID
        inspectorSegmentID = nil
        setSelectedSegmentID(nil)
    }

    func dragCredit(_ creditID: UInt64, fraction: Double) {
        guard player.duration > 0 else { return }
        let milliseconds = UInt64((player.duration * min(max(0, fraction), 1) * 1_000).rounded())
        store.setCreditTime(id: creditID, milliseconds: milliseconds)
        selectedCreditID = creditID
        inspectorSegmentID = nil
        setSelectedSegmentID(nil)
    }

    func setFollowSelection(_ on: Bool) {
        followSelection = on
        if on {
            selectedCreditID = nil
            playheadDidChange()
            inspectorSegmentID = selectedSegmentID
        }
    }

    func selectCurrent() {
        breakFollowSelection()
        selectedCreditID = nil
        setSelectedSegmentID(activeSegmentID)
    }

    func selectRelativeToPlayhead(offset: Int) {
        if !TimelineInteractionMath.keepsFollowSelection(relativeOffset: offset) {
            breakFollowSelection()
        }
        selectedCreditID = nil
        let segments = store.allSegments
        guard !segments.isEmpty else { return }
        let current = segments.firstIndex { $0.id == activeSegmentID } ?? -1
        setSelectedSegmentID(segments[min(max(0, current + offset), segments.count - 1)].id)
    }

    func jump(to segmentID: UInt64) {
        breakFollowSelection()
        setSelectedSegmentID(segmentID)
        guard let segment = store.allSegments.first(where: { $0.id == segmentID }),
              let point = segment.timing.finalPoint ?? segment.timing.gemini
        else { return }
        seek(toSeconds: Double(point.timeMS) / 1_000)
    }

    func moveSelection(by offset: Int) {
        breakFollowSelection()
        selectedCreditID = nil
        let segments = store.allSegments
        guard !segments.isEmpty else { return }
        let current = segments.firstIndex { $0.id == selectedSegmentID } ?? (offset > 0 ? -1 : segments.count)
        setSelectedSegmentID(segments[min(max(0, current + offset), segments.count - 1)].id)
    }

    func stamp(_ segmentID: UInt64) {
        store.setFinal(segmentID: segmentID, milliseconds: UInt64(max(0, player.currentTime * 1_000)))
    }

    func nudgeSelected(by delta: Int64) {
        if let creditID = selectedCreditID {
            let base = store.project?.creditTime(id: creditID)
                ?? UInt64(max(0, player.currentTime * 1_000))
            let maximum = loadedMaximum ?? store.project?.target?.durationMS ?? UInt64.max
            store.setCreditTime(
                id: creditID,
                milliseconds: TimelineInteractionMath.nudged(base, by: delta, maximum: maximum)
            )
            return
        }
        guard let id = selectedSegmentID,
              let segment = store.allSegments.first(where: { $0.id == id })
        else { return }
        let base = segment.timing.finalPoint?.timeMS
            ?? segment.timing.gemini?.timeMS
            ?? UInt64(max(0, player.currentTime * 1_000))
        let maximum = loadedMaximum ?? store.project?.target?.durationMS ?? UInt64.max
        store.setFinal(
            segmentID: id,
            milliseconds: TimelineInteractionMath.nudged(base, by: delta, maximum: maximum)
        )
    }

    private var loadedMaximum: UInt64? {
        player.duration > 0 ? UInt64((player.duration * 1_000).rounded()) : nil
    }

    func hitCreditHandle(_ sample: TimelinePointerSample, width: CGFloat) -> UInt64? {
        guard width > 0, player.duration > 0 else { return nil }
        return hitCredit(at: sample.documentFraction, windowMS: 14 / width * player.duration * 1_000)
    }

    private func hitCredit(at fraction: Double, windowMS: Double = 120) -> UInt64? {
        guard player.duration > 0, let cues = store.project?.creditCues, !cues.isEmpty else { return nil }
        let target = fraction * player.duration * 1_000
        return cues.min(by: { abs(Double($0.timeMS) - target) < abs(Double($1.timeMS) - target) })
            .flatMap { abs(Double($0.timeMS) - target) <= windowMS ? $0.id : nil }
    }

    func seek(toSeconds seconds: TimeInterval) {
        player.seek(to: seconds)
        playheadDidChange()
    }

    func seek(toFraction fraction: Double) {
        guard player.duration > 0 else { return }
        seek(toSeconds: player.duration * min(max(0, fraction), 1))
    }

    func seekByVisibleStep(_ direction: Int) {
        let visible = viewport.visibleDocumentFraction ?? 1 / zoom
        let step = TimelineInteractionMath.playheadStep(
            duration: player.duration,
            visibleFraction: visible
        )
        seek(toSeconds: player.currentTime + Double(direction) * step)
    }

    private func breakFollowSelection() {
        if followSelection { followSelection = false }
    }

    private func setSelectedSegmentID(_ selected: UInt64?) {
        setHighlight(active: activeSegmentID, selected: selected)
        inspectorSegmentID = selected
    }

    private func setHighlight(active: UInt64?, selected: UInt64?) {
        playbackHighlight.set(active: active, selected: selected)
    }

    func shouldRevealQueueItem(index: Int, automatically: Bool) -> Bool {
        queueRevealPlanner.shouldReveal(index: index, automatically: automatically)
    }

    func markLoopStart() { player.markLoopStart() }
    func markLoopEnd() { player.markLoopEnd() }
    func clearLoop() { player.clearLoop() }

    func resetHotkeys() { hotkeys = TimelineHotkeyTranslator() }

    func handleHotkey(_ input: TimelineHotkeyInput) -> Bool {
        if inspectorEditing { return false }
        guard let action = hotkeys.translate(input) else { return false }
        switch action {
        case .consume:
            return true
        case .playPause:
            player.playPause()
        case let .seekPlayhead(direction):
            seekByVisibleStep(direction)
        case let .nudgeFinal(delta):
            nudgeSelected(by: delta)
        case let .moveSelection(offset):
            moveSelection(by: offset)
        case .selectCurrent:
            selectCurrent()
        case let .selectRelativeToPlayhead(offset):
            selectRelativeToPlayhead(offset: offset)
        case .stampFinal:
            if let creditID = selectedCreditID {
                stampCredit(creditID)
                return true
            }
            guard let id = selectedSegmentID ?? store.allSegments.first?.id else { return false }
            stamp(id)
        case .clearFinal:
            guard let id = selectedSegmentID,
                  store.allSegments.first(where: { $0.id == id })?.timing.finalPoint != nil
            else { return false }
            store.clearFinal(segmentID: id)
        case .loopStart:
            markLoopStart()
        case .loopEnd:
            markLoopEnd()
        case .clearLoop:
            guard player.loopStart != nil || player.loopEnd != nil else { return false }
            player.clearLoop()
        case .seekToStart:
            seek(toSeconds: 0)
        case .seekToEnd:
            seek(toSeconds: player.duration)
        case let .zoom(delta):
            adjustZoom(by: delta)
        case let .adjustPlaybackRate(direction):
            player.setPlaybackRate(
                TimelineInteractionMath.steppedRate(
                    player.playbackRate,
                    by: direction,
                    rates: AudioPlayer.supportedRates
                )
            )
        case .toggleFollowSelection:
            setFollowSelection(!followSelection)
        }
        return true
    }

    func adjustZoom(by delta: Double) {
        setZoom(zoom + delta)
    }

    func setZoom(_ value: Double) {
        zoom(to: value)
    }

    private func zoom(to value: Double) {
        zoom(to: value, documentAnchor: zoomAnchorFraction)
    }

    private func zoom(to value: Double, documentAnchor: Double) {
        let target = min(max(1, value), TimelineInteractionMath.maximumZoom)
        guard target != zoom else {
            viewport.position(documentAnchor: documentAnchor, viewportAnchor: 0.5)
            return
        }
        viewport.preserve(
            documentAnchor: documentAnchor,
            viewportAnchor: 0.5
        ) { zoom = target }
    }

    private var zoomAnchorFraction: Double {
        TimelineInteractionMath.playheadFraction(
            currentTime: player.currentTime,
            duration: player.duration,
            fallback: viewport.visibleCenterFraction
        )
    }

}

@MainActor
final class TimelineViewportProxy {
    private static let scrollerRefreshInterval: TimeInterval = 1.0 / 30.0
    weak var scrollView: NSScrollView?
    private var pendingAnchor: (document: Double, viewport: Double)?
    private var interactionActive = false
    private var endInteractionAfterGeometry = false
    private var lastScrollerReflection = -Double.infinity

    var visibleCenterFraction: Double {
        guard let scrollView, let document = scrollView.documentView, document.bounds.width > 0 else { return 0.5 }
        let visible = document.convert(scrollView.contentView.bounds, from: scrollView.contentView)
        return min(max(0, Double((visible.midX - document.bounds.minX) / document.bounds.width)), 1)
    }

    var visibleDocumentFraction: Double? {
        guard let scrollView, let document = scrollView.documentView, document.bounds.width > 0 else { return nil }
        return min(1, Double(scrollView.contentView.bounds.width / document.bounds.width))
    }

    func attach(scrollView: NSScrollView?) {
        if self.scrollView !== scrollView { lastScrollerReflection = -Double.infinity }
        self.scrollView = scrollView
    }

    func preserve(
        documentAnchor: Double,
        viewportAnchor: Double,
        change: () -> Void
    ) {
        pendingAnchor = (documentAnchor, viewportAnchor)
        change()
    }

    func beginInteraction() {
        interactionActive = true
        endInteractionAfterGeometry = false
    }

    func endInteraction() {
        if pendingAnchor == nil {
            interactionActive = false
        } else {
            endInteractionAfterGeometry = true
        }
    }

    func documentGeometryDidChange() {
        guard let pendingAnchor else { return }
        scroll(
            documentAnchor: pendingAnchor.document,
            viewportAnchor: pendingAnchor.viewport
        )
        self.pendingAnchor = nil
        if endInteractionAfterGeometry {
            interactionActive = false
            endInteractionAfterGeometry = false
        }
    }

    func center(on fraction: Double, frameHostTime: TimeInterval? = nil) {
        guard !interactionActive, pendingAnchor == nil else { return }
        scroll(
            documentAnchor: fraction,
            viewportAnchor: 0.5,
            frameHostTime: frameHostTime
        )
    }

    func position(documentAnchor: Double, viewportAnchor: Double) {
        guard pendingAnchor == nil else { return }
        scroll(documentAnchor: documentAnchor, viewportAnchor: viewportAnchor)
    }

    private func scroll(
        documentAnchor: Double,
        viewportAnchor: Double,
        frameHostTime: TimeInterval? = nil
    ) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let documentX = document.bounds.minX
            + CGFloat(min(max(0, documentAnchor), 1)) * document.bounds.width
        let originX = TimelineInteractionMath.scrollOrigin(
            anchorX: documentX,
            viewportAnchor: CGFloat(viewportAnchor),
            viewportWidth: clip.bounds.width,
            documentMinX: document.bounds.minX,
            documentMaxX: document.bounds.maxX
        )
        // NSClipView supports fractional bounds. Rounding here made the moving
        // waveform visibly step at well below 60 fps on long songs.
        let origin = NSPoint(x: originX, y: clip.bounds.minY)
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        if let frameHostTime {
            guard frameHostTime - lastScrollerReflection >= Self.scrollerRefreshInterval else { return }
            lastScrollerReflection = frameHostTime
        } else {
            lastScrollerReflection = -Double.infinity
        }
        // The visible document scrolls every display frame. The scrollbar thumb
        // is bookkeeping UI, so refreshing it at 30 Hz avoids redundant layout.
        scrollView.reflectScrolledClipView(clip)
    }

}
