import SwiftUI

struct ZoomableTimeline: View {
    @ObservedObject var store: ProjectStore
    let player: AudioPlayer
    @ObservedObject var waveform: WaveformModel
    @ObservedObject var interaction: TimelineInteractionController

    var body: some View {
        GeometryReader { outer in
            let metrics = TimelineLayoutMetrics(totalHeight: outer.size.height)
            HStack(spacing: 0) {
                TimelineLaneLabels(interaction: interaction, metrics: metrics).frame(width: 108)
                Divider()
                TimelineNativeScrollView(
                    zoom: interaction.zoom,
                    viewportSize: CGSize(width: max(1, outer.size.width - 109), height: outer.size.height),
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
                waveformLanes(size: geometry.size).allowsHitTesting(false)
                segmentRegions(duration: duration, width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                ForEach(store.allSegments) { segment in
                    geminiMarker(segment, duration: duration, width: geometry.size.width)
                }
                selectionOverlay(width: geometry.size.width, height: geometry.size.height)
                TimelinePlayhead(
                    player: player,
                    active: interaction.activeSegmentID != nil,
                    duration: duration,
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                TimelinePointerSurface(onEvent: interaction.handle)
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

    private func waveformLanes(size: CGSize) -> some View {
        let tiles = TimelineInteractionMath.canvasTileCount(documentWidth: size.width)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<tiles, id: \.self) { index in
                let frame = TimelineInteractionMath.canvasTileFrame(index: index, documentWidth: size.width)
                Canvas { context, canvasSize in
                    drawWaveformTile(
                        context: context,
                        documentWidth: size.width,
                        tileOrigin: frame.origin,
                        tileSize: canvasSize
                    )
                }
                .frame(width: frame.width, height: size.height)
                .offset(x: frame.origin)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawWaveformTile(
        context: GraphicsContext,
        documentWidth: CGFloat,
        tileOrigin: CGFloat,
        tileSize: CGSize
    ) {
        guard !waveform.bins.isEmpty, documentWidth > 0 else { return }
        let bins = TimelineInteractionMath.canvasTileBins(
            tileOrigin: tileOrigin,
            tileWidth: tileSize.width,
            documentWidth: documentWidth,
            binCount: waveform.bins.count
        )
        guard !bins.isEmpty else { return }
        let lanes = interaction.lanes
        let step = documentWidth / CGFloat(max(1, waveform.bins.count - 1))
        drawKind(
            lanes.upper,
            context: context,
            documentWidth: documentWidth,
            tileOrigin: tileOrigin,
            tileSize: tileSize,
            bins: bins,
            step: step,
            rect: CGRect(x: 0, y: TimelineLayoutMetrics.ruler, width: tileSize.width, height: metrics.waveform)
        )
        drawKind(
            lanes.lower,
            context: context,
            documentWidth: documentWidth,
            tileOrigin: tileOrigin,
            tileSize: tileSize,
            bins: bins,
            step: step,
            rect: CGRect(
                x: 0,
                y: TimelineLayoutMetrics.ruler + metrics.waveform,
                width: tileSize.width,
                height: metrics.bands
            )
        )
    }

    private func drawKind(
        _ kind: AudioLaneKind,
        context: GraphicsContext,
        documentWidth: CGFloat,
        tileOrigin: CGFloat,
        tileSize: CGSize,
        bins: Range<Int>,
        step: CGFloat,
        rect: CGRect
    ) {
        guard let adapter = kind.adapter else { return }
        let center = rect.midY
        let radius = rect.height * 0.39
        switch adapter.surface {
        case .waveform:
            if adapter.series.contains("peak") {
                fillPeak(context: context, bins: bins, step: step, tileOrigin: tileOrigin, center: center, radius: radius)
            }
            if adapter.series.contains("rms") {
                strokeRMS(context: context, bins: bins, step: step, tileOrigin: tileOrigin, center: center, radius: radius)
            }
        case .bands:
            drawBands(context: context, documentWidth: documentWidth, tileOrigin: tileOrigin, tileSize: tileSize, bins: bins, top: rect.minY, height: rect.height)
        case .spectrogram:
            if let scale = adapter.scale {
                fillSpectrogram(
                    context: context,
                    tileOrigin: tileOrigin,
                    tileSize: tileSize,
                    documentWidth: documentWidth,
                    rect: rect,
                    scale: scale
                )
            }
        }
    }

    private func fillPeak(
        context: GraphicsContext,
        bins: Range<Int>,
        step: CGFloat,
        tileOrigin: CGFloat,
        center: CGFloat,
        radius: CGFloat
    ) {
        var mono = Path()
        let upper = bins.map { index in
            CGPoint(
                x: CGFloat(index) * step - tileOrigin,
                y: center - CGFloat(waveform.bins[index].maximum) * radius
            )
        }
        let lower = bins.reversed().map { index in
            CGPoint(
                x: CGFloat(index) * step - tileOrigin,
                y: center - CGFloat(waveform.bins[index].minimum) * radius
            )
        }
        if let first = upper.first {
            mono.move(to: first)
            for point in upper.dropFirst() { mono.addLine(to: point) }
            for point in lower { mono.addLine(to: point) }
            mono.closeSubpath()
            context.fill(mono, with: .color(CueWeaveStyle.gemini.opacity(0.48)))
        }
    }

    private func strokeRMS(
        context: GraphicsContext,
        bins: Range<Int>,
        step: CGFloat,
        tileOrigin: CGFloat,
        center: CGFloat,
        radius: CGFloat
    ) {
        var upper = Path()
        var lower = Path()
        for (offset, index) in bins.enumerated() {
            let x = CGFloat(index) * step - tileOrigin
            let rms = CGFloat(waveform.bins[index].rms) * radius
            let top = CGPoint(x: x, y: center - rms)
            let bottom = CGPoint(x: x, y: center + rms)
            if offset == 0 {
                upper.move(to: top)
                lower.move(to: bottom)
            } else {
                upper.addLine(to: top)
                lower.addLine(to: bottom)
            }
        }
        context.stroke(upper, with: .color(CueWeaveStyle.accent.opacity(0.85)), lineWidth: 1)
        context.stroke(lower, with: .color(CueWeaveStyle.accent.opacity(0.85)), lineWidth: 1)
    }

    private func drawBands(
        context: GraphicsContext,
        documentWidth: CGFloat,
        tileOrigin: CGFloat,
        tileSize: CGSize,
        bins: Range<Int>,
        top: CGFloat,
        height: CGFloat
    ) {
        let rowHeight = height / 3
        for row in 1 ... 2 {
            var divider = Path()
            let y = top + CGFloat(row) * rowHeight
            divider.move(to: CGPoint(x: 0, y: y))
            divider.addLine(to: CGPoint(x: tileSize.width, y: y))
            context.stroke(divider, with: .color(.secondary.opacity(0.10)), lineWidth: 1)
        }
        context.fill(
            bandPath(documentWidth: documentWidth, tileOrigin: tileOrigin, bins: bins, bandTop: top, rowHeight: rowHeight, row: 0, value: \.low),
            with: .color(CueWeaveStyle.lowBand.opacity(0.55))
        )
        context.fill(
            bandPath(documentWidth: documentWidth, tileOrigin: tileOrigin, bins: bins, bandTop: top, rowHeight: rowHeight, row: 1, value: \.mid),
            with: .color(CueWeaveStyle.midBand.opacity(0.52))
        )
        context.fill(
            bandPath(documentWidth: documentWidth, tileOrigin: tileOrigin, bins: bins, bandTop: top, rowHeight: rowHeight, row: 2, value: \.high),
            with: .color(CueWeaveStyle.highBand.opacity(0.52))
        )
    }

    private func fillSpectrogram(
        context: GraphicsContext,
        tileOrigin: CGFloat,
        tileSize: CGSize,
        documentWidth: CGFloat,
        rect: CGRect,
        scale: SpectrumScale
    ) {
        guard let frame = waveform.frame(for: scale), frame.timeBins > 0, frame.frequencyBins > 0 else { return }
        let duration = max(1, frame.endMS)
        let x0 = CGFloat(frame.startMS) / CGFloat(duration) * documentWidth - tileOrigin
        let width = CGFloat(max(1, frame.endMS - frame.startMS)) / CGFloat(duration) * documentWidth
        let cellW = width / CGFloat(frame.timeBins)
        let cellH = rect.height / CGFloat(frame.frequencyBins)
        let timeStride = max(1, Int((1 / max(cellW, 0.001)).rounded(.up)))
        let freqStride = max(1, Int((1 / max(cellH, 0.001)).rounded(.up)))
        let minX = rect.minX
        let maxX = rect.minX + tileSize.width
        var time = 0
        while time < frame.timeBins {
            let x = x0 + CGFloat(time) * cellW
            if x + cellW * CGFloat(timeStride) < minX || x > maxX { time += timeStride; continue }
            var freq = 0
            while freq < frame.frequencyBins {
                let value = frame.values[time * frame.frequencyBins + freq]
                if value >= 8 {
                    let y = rect.minY + CGFloat(frame.frequencyBins - 1 - freq) * cellH
                    context.fill(
                        Path(CGRect(x: x, y: y, width: max(1, cellW * CGFloat(timeStride)), height: max(1, cellH * CGFloat(freqStride)))),
                        with: .color(CueWeaveStyle.gemini.opacity(0.15 + 0.75 * Double(value) / 255))
                    )
                }
                freq += freqStride
            }
            time += timeStride
        }
    }

    private func bandPath(
        documentWidth: CGFloat,
        tileOrigin: CGFloat,
        bins: Range<Int>,
        bandTop: CGFloat,
        rowHeight: CGFloat,
        row: Int,
        value: KeyPath<AudioDisplayBin, Float>
    ) -> Path {
        let top = bandTop + CGFloat(row) * rowHeight
        let baseline = top + rowHeight - 2
        let amplitude = rowHeight - 4
        let step = documentWidth / CGFloat(max(1, waveform.bins.count - 1))
        var path = Path()
        guard let first = bins.first, let last = bins.last else { return path }
        let firstX = CGFloat(first) * step - tileOrigin
        let lastX = CGFloat(last) * step - tileOrigin
        path.move(to: CGPoint(x: firstX, y: baseline))
        for index in bins {
            path.addLine(to: CGPoint(
                x: CGFloat(index) * step - tileOrigin,
                y: baseline - CGFloat(waveform.bins[index][keyPath: value]) * amplitude
            ))
        }
        path.addLine(to: CGPoint(x: lastX, y: baseline))
        path.closeSubpath()
        return path
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
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let fraction = min(max(0, (x + value.translation.width) / width), 1)
                            interaction.dragCredit(credit.id, fraction: Double(fraction))
                        }
                )
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
        if interaction.selectedSegmentID == segment.id { return CueWeaveStyle.lyricSelectedFill }
        if interaction.activeSegmentID == segment.id { return CueWeaveStyle.lyricPlayingFill }
        if segment.timing.finalPoint != nil { return CueWeaveStyle.gemini.opacity(0.07) }
        return Color.secondary.opacity(0.05)
    }

    private func lyricLaneStroke(_ segment: LyricSegment) -> Color {
        if interaction.selectedSegmentID == segment.id { return CueWeaveStyle.accent.opacity(0.42) }
        if interaction.activeSegmentID == segment.id { return CueWeaveStyle.accent.opacity(0.28) }
        if segment.timing.finalPoint != nil { return CueWeaveStyle.gemini.opacity(0.16) }
        return Color.secondary.opacity(0.12)
    }

    private func segmentTone(_ segment: LyricSegment) -> Color {
        if interaction.selectedSegmentID == segment.id { return CueWeaveStyle.accent }
        if interaction.activeSegmentID == segment.id { return CueWeaveStyle.accent.opacity(0.72) }
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

private struct TimelinePlayhead: View {
    @ObservedObject var player: AudioPlayer
    let active: Bool
    let duration: UInt64
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let x = CGFloat(player.currentTime * 1_000) / CGFloat(duration) * width
        let tone = active ? CueWeaveStyle.accent : CueWeaveStyle.warning
        let halo = active ? 11.0 : 5.0
        let line = active ? 2.0 : 1.0
        return ZStack {
            Rectangle().fill(tone.opacity(0.12)).frame(width: halo, height: height)
            Rectangle().fill(tone).frame(width: line, height: height)
        }
        .offset(x: x - (active ? 5 : 2))
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
    }
}
