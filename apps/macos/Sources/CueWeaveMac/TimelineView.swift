import SwiftUI

struct ZoomableTimeline: View {
    @ObservedObject var store: ProjectStore
    let player: AudioPlayer
    @ObservedObject var waveform: WaveformModel
    @ObservedObject var interaction: TimelineInteractionController

    var body: some View {
        GeometryReader { outer in
            let bar = TimelineScrollChrome.barHeight
            let plotHeight = max(1, outer.size.height - bar)
            let metrics = TimelineLayoutMetrics(totalHeight: plotHeight)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    TimelineLaneLabels(interaction: interaction, metrics: metrics)
                    Color.clear.frame(height: bar)
                }
                .frame(width: 108, height: outer.size.height)
                Divider()
                TimelineNativeScrollView(
                    zoom: interaction.zoom,
                    viewportSize: CGSize(width: max(1, outer.size.width - 109), height: plotHeight),
                    viewport: interaction.viewport
                ) {
                    TimelineCanvas(
                        store: store,
                        player: player,
                        waveform: waveform,
                        interaction: interaction,
                        metrics: metrics
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: outer.size.width, height: outer.size.height)
            .clipped()
        }
        .onChange(of: interaction.lanes) { _, lanes in
            waveform.loadSpectrograms(scales: lanes.neededScales)
        }
        .onChange(of: waveform.bins.count) { _, _ in
            waveform.loadSpectrograms(scales: interaction.lanes.neededScales)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TimelineLaneLabels: View {
    @ObservedObject var interaction: TimelineInteractionController
    @ObservedObject private var l10n = L10n.shared
    let metrics: TimelineLayoutMetrics

    var body: some View {
        VStack(spacing: 0) {
            laneCaption(l10n.t("lane.time"), height: TimelineLayoutMetrics.ruler)
            lanePicker(selection: upperLane, height: metrics.waveform)
            lanePicker(selection: lowerLane, height: metrics.bands)
            laneCaption(l10n.t("lane.lyrics"), detail: l10n.t("lane.timestamps"), height: TimelineLayoutMetrics.lyrics)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var upperLane: Binding<AudioLaneKind> {
        Binding(
            get: { interaction.lanes.upper },
            set: { kind in var next = interaction.lanes; next.upper = kind; interaction.lanes = next }
        )
    }

    private var lowerLane: Binding<AudioLaneKind> {
        Binding(
            get: { interaction.lanes.lower },
            set: { kind in var next = interaction.lanes; next.lower = kind; interaction.lanes = next }
        )
    }

    private func lanePicker(selection: Binding<AudioLaneKind>, height: CGFloat) -> some View {
        Picker("", selection: selection) {
            ForEach(AudioLaneKind.allCases) { kind in
                Text(l10n.t(kind.titleKey)).tag(kind)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func laneCaption(_ title: String, detail: String? = nil, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).fontWeight(.semibold)
            if let detail { Text(detail).foregroundStyle(.tertiary) }
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct TimelineCanvas: View {
    @ObservedObject var store: ProjectStore
    let player: AudioPlayer
    @ObservedObject var waveform: WaveformModel
    @ObservedObject var interaction: TimelineInteractionController
    let metrics: TimelineLayoutMetrics

    var body: some View {
        GeometryReader { geometry in
            let loadedDuration = player.duration > 0
                ? UInt64((player.duration * 1_000).rounded())
                : nil
            let duration = max(1, loadedDuration ?? store.project?.target?.durationMS ?? 1)
            ZStack(alignment: .topLeading) {
                trackBackgrounds
                timeGrid(width: geometry.size.width, duration: duration).allowsHitTesting(false)
                TimelineLoopRegion(
                    player: player,
                    duration: duration,
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                TimelineWaveformLanes(
                    samples: waveform.bins, spectrograms: waveform.spectrograms,
                    lanes: interaction.lanes, metrics: metrics, size: geometry.size
                ).equatable().allowsHitTesting(false)
                segmentRegions(duration: duration, width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                TimelineHighlightSurface(
                    segments: store.allSegments,
                    duration: duration,
                    lyricTop: metrics.lyricTop,
                    highlight: interaction.playbackHighlight
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)
                ForEach(store.allSegments) { segment in
                    geminiMarker(segment, duration: duration, width: geometry.size.width)
                }
                selectionOverlay(width: geometry.size.width, height: geometry.size.height)
                TimelinePlayhead(
                    player: player,
                    interaction: interaction
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)
                TimelinePointerSurface(onEvent: interaction.handle, creditAt: interaction.hitCreditHandle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                creditHandles(duration: duration, width: geometry.size.width, height: geometry.size.height)
            }
            .clipped()
        }
    }

    private var trackBackgrounds: some View {
        VStack(spacing: 0) {
            Color(nsColor: .controlBackgroundColor).frame(height: TimelineLayoutMetrics.ruler)
            Color(nsColor: .textBackgroundColor).frame(height: metrics.waveform)
            CueWeaveStyle.gemini.opacity(0.035).frame(height: metrics.bands)
            Color(nsColor: .textBackgroundColor).frame(height: TimelineLayoutMetrics.lyrics)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear.frame(height: TimelineLayoutMetrics.ruler - 1); Divider()
                Color.clear.frame(height: metrics.waveform - 1); Divider()
                Color.clear.frame(height: metrics.bands - 1); Divider()
            }
        }
    }

    private func timeGrid(width: CGFloat, duration: UInt64) -> some View {
        let tiles = TimelineInteractionMath.canvasTileCount(documentWidth: width)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<tiles, id: \.self) { index in
                let frame = TimelineInteractionMath.canvasTileFrame(index: index, documentWidth: width)
                Canvas { context, canvasSize in
                    for line in 0 ... 12 {
                        let x = CGFloat(line) / 12 * width - frame.origin
                        guard x >= -40, x <= canvasSize.width + 40 else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: TimelineLayoutMetrics.ruler))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                        context.stroke(path, with: .color(.secondary.opacity(0.11)), lineWidth: 1)
                        context.draw(
                            Text(cueTime(duration * UInt64(line) / 12))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary),
                            at: CGPoint(x: x + 25, y: 10)
                        )
                    }
                }
                .frame(width: frame.width)
                .offset(x: frame.origin)
            }
        }
    }

    private func segmentRegions(duration: UInt64, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(store.allSegments.enumerated()), id: \.element.id) { index, segment in
                if let start = displayPoint(segment)?.timeMS {
                    let end = nextTime(after: index) ?? duration
                    let x = CGFloat(start) / CGFloat(duration) * width
                    let regionWidth = max(2, CGFloat(max(start, end) - start) / CGFloat(duration) * width)
                    Rectangle()
                        .fill(lyricLaneFill(segment))
                        .overlay(alignment: .topLeading) {
                            if regionWidth > 42 {
                                Text(String(format: "%04llu", segment.id))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(segmentTone(segment))
                                    .padding(4)
                            }
                        }
                        .overlay {
                            Rectangle().stroke(
                                lyricLaneStroke(segment),
                                lineWidth: 1
                            )
                        }
                        .frame(width: regionWidth, height: TimelineLayoutMetrics.lyrics)
                        .offset(x: x, y: metrics.lyricTop)
                }
            }
        }
    }

    private func creditHandles(duration: UInt64, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(store.project?.creditCues ?? [], id: \.id) { credit in
                let x = CGFloat(credit.timeMS) / CGFloat(duration) * width
                VStack(spacing: 2) {
                    Text("C")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    Circle()
                        .fill(interaction.selectedCreditID == credit.id ? CueWeaveStyle.accent : CueWeaveStyle.accent.opacity(0.7))
                        .frame(width: 9, height: 9)
                    Rectangle().frame(width: 1, height: max(12, height - metrics.lyricTop - 28))
                }
                .foregroundStyle(CueWeaveStyle.accent)
                .position(x: x, y: metrics.lyricTop + 18)
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func geminiMarker(_ segment: LyricSegment, duration: UInt64, width: CGFloat) -> some View {
        if let point = segment.timing.gemini {
            let x = CGFloat(point.timeMS) / CGFloat(duration) * width
            VStack(spacing: 1) {
                Text("G").font(.system(size: 8, weight: .semibold, design: .monospaced))
                Rectangle().frame(width: 1, height: 14)
            }
            .foregroundStyle(CueWeaveStyle.gemini)
            .position(x: x, y: metrics.lyricTop + 12)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func selectionOverlay(width: CGFloat, height: CGFloat) -> some View {
        if let range = interaction.selectionRange {
            let x = CGFloat(range.lowerBound) * width
            let selectionWidth = max(1, CGFloat(range.upperBound - range.lowerBound) * width)
            Rectangle()
                .fill(CueWeaveStyle.accent.opacity(0.12))
                .overlay { Rectangle().stroke(CueWeaveStyle.accent.opacity(0.82), lineWidth: 1) }
                .frame(width: selectionWidth, height: height)
                .offset(x: x)
                .allowsHitTesting(false)
        }
    }

    private func displayPoint(_ segment: LyricSegment) -> AlignmentPoint? {
        segment.timing.finalPoint ?? segment.timing.gemini
    }

    private func nextTime(after index: Int) -> UInt64? {
        store.allSegments.dropFirst(index + 1).compactMap { displayPoint($0)?.timeMS }.first
    }

    private func lyricLaneFill(_ segment: LyricSegment) -> Color {
        if segment.timing.finalPoint != nil { return CueWeaveStyle.gemini.opacity(0.07) }
        return Color.secondary.opacity(0.05)
    }

    private func lyricLaneStroke(_ segment: LyricSegment) -> Color {
        if segment.timing.finalPoint != nil { return CueWeaveStyle.gemini.opacity(0.16) }
        return Color.secondary.opacity(0.12)
    }

    private func segmentTone(_ segment: LyricSegment) -> Color {
        if segment.timing.finalPoint != nil { return CueWeaveStyle.gemini }
        return Color.secondary
    }
}

private struct TimelineLoopRegion: View {
    @ObservedObject var player: AudioPlayer
    let duration: UInt64
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        if let start = player.loopStart, let end = player.loopEnd, end > start {
            let x = CGFloat(start * 1_000) / CGFloat(duration) * width
            let regionWidth = CGFloat(end - start) * 1_000 / CGFloat(duration) * width
            Rectangle()
                .fill(CueWeaveStyle.accent.opacity(0.075))
                .overlay(alignment: .leading) { Rectangle().fill(CueWeaveStyle.accent).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(CueWeaveStyle.accent).frame(width: 1) }
                .frame(width: regionWidth, height: height - TimelineLayoutMetrics.ruler)
                .offset(x: x, y: TimelineLayoutMetrics.ruler)
                .allowsHitTesting(false)
        }
    }
}
