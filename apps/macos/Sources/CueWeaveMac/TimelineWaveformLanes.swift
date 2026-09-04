import SwiftUI

/// Only audio data, lane settings and geometry invalidate these expensive tiled canvases.
/// Playback/selection highlighting belongs to the separate lyric overlay.
struct TimelineWaveformLanes: View, Equatable {
    let samples: [AudioDisplayBin]
    let spectrograms: [String: SpectrogramFrame]
    let lanes: AudioLaneSettings
    let metrics: TimelineLayoutMetrics
    let size: CGSize

    var body: some View {
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
        guard !samples.isEmpty, documentWidth > 0 else { return }
        let bins = TimelineInteractionMath.canvasTileBins(
            tileOrigin: tileOrigin,
            tileWidth: tileSize.width,
            documentWidth: documentWidth,
            binCount: samples.count
        )
        guard !bins.isEmpty else { return }
        let step = documentWidth / CGFloat(max(1, samples.count - 1))
        let rows = [
            (lanes.upper, TimelineLayoutMetrics.ruler, metrics.waveform),
            (lanes.lower, TimelineLayoutMetrics.ruler + metrics.waveform, metrics.bands),
        ]
        for (kind, top, height) in rows {
            drawKind(
                kind, context: context, documentWidth: documentWidth,
                tileOrigin: tileOrigin, bins: bins, step: step,
                rect: CGRect(x: 0, y: top, width: tileSize.width, height: height)
            )
        }
    }

    private func drawKind(
        _ kind: AudioLaneKind,
        context: GraphicsContext,
        documentWidth: CGFloat,
        tileOrigin: CGFloat,
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
            drawBands(context: context, documentWidth: documentWidth, tileOrigin: tileOrigin, bins: bins, rect: rect)
        case .spectrogram:
            if let scale = adapter.scale {
                fillSpectrogram(
                    context: context,
                    tileOrigin: tileOrigin,
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
        for index in bins {
            let point = CGPoint(x: CGFloat(index) * step - tileOrigin, y: center - CGFloat(samples[index].maximum) * radius)
            if index == bins.lowerBound { mono.move(to: point) } else { mono.addLine(to: point) }
        }
        for index in bins.reversed() {
            mono.addLine(to: CGPoint(x: CGFloat(index) * step - tileOrigin, y: center - CGFloat(samples[index].minimum) * radius))
        }
        mono.closeSubpath()
        context.fill(mono, with: .color(CueWeaveStyle.gemini.opacity(0.48)))
    }

    private func strokeRMS(
        context: GraphicsContext,
        bins: Range<Int>,
        step: CGFloat,
        tileOrigin: CGFloat,
        center: CGFloat,
        radius: CGFloat
    ) {
        for sign: CGFloat in [-1, 1] {
            var path = Path()
            for (offset, index) in bins.enumerated() {
                let point = CGPoint(x: CGFloat(index) * step - tileOrigin,
                                    y: center + sign * CGFloat(samples[index].rms) * radius)
                if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(CueWeaveStyle.accent.opacity(0.85)), lineWidth: 1)
        }
    }

    private func drawBands(
        context: GraphicsContext,
        documentWidth: CGFloat,
        tileOrigin: CGFloat,
        bins: Range<Int>,
        rect: CGRect
    ) {
        let rowHeight = rect.height / 3
        for row in 1 ... 2 {
            var divider = Path()
            let y = rect.minY + CGFloat(row) * rowHeight
            divider.move(to: CGPoint(x: 0, y: y))
            divider.addLine(to: CGPoint(x: rect.width, y: y))
            context.stroke(divider, with: .color(.secondary.opacity(0.10)), lineWidth: 1)
        }
        let bands: [(KeyPath<AudioDisplayBin, Float>, Color)] = [
            (\.low, CueWeaveStyle.lowBand.opacity(0.55)),
            (\.mid, CueWeaveStyle.midBand.opacity(0.52)),
            (\.high, CueWeaveStyle.highBand.opacity(0.52)),
        ]
        for (row, band) in bands.enumerated() {
            context.fill(bandPath(documentWidth: documentWidth, tileOrigin: tileOrigin, bins: bins,
                                  bandTop: rect.minY, rowHeight: rowHeight, row: row, value: band.0), with: .color(band.1))
        }
    }

    private func fillSpectrogram(
        context: GraphicsContext,
        tileOrigin: CGFloat,
        documentWidth: CGFloat,
        rect: CGRect,
        scale: SpectrumScale
    ) {
        guard let frame = spectrograms[scale.rawValue], frame.timeBins > 0, frame.frequencyBins > 0 else { return }
        let duration = max(1, frame.endMS)
        let x0 = CGFloat(frame.startMS) / CGFloat(duration) * documentWidth - tileOrigin
        let width = CGFloat(max(1, frame.endMS - frame.startMS)) / CGFloat(duration) * documentWidth
        let cellW = width / CGFloat(frame.timeBins)
        let cellH = rect.height / CGFloat(frame.frequencyBins)
        let timeStride = max(1, Int((1 / max(cellW, 0.001)).rounded(.up)))
        let freqStride = max(1, Int((1 / max(cellH, 0.001)).rounded(.up)))
        let minX = rect.minX
        let maxX = rect.maxX
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
        let step = documentWidth / CGFloat(max(1, samples.count - 1))
        var path = Path()
        guard let first = bins.first, let last = bins.last else { return path }
        let firstX = CGFloat(first) * step - tileOrigin
        let lastX = CGFloat(last) * step - tileOrigin
        path.move(to: CGPoint(x: firstX, y: baseline))
        for index in bins {
            path.addLine(to: CGPoint(
                x: CGFloat(index) * step - tileOrigin,
                y: baseline - CGFloat(samples[index][keyPath: value]) * amplitude
            ))
        }
        path.addLine(to: CGPoint(x: lastX, y: baseline))
        path.closeSubpath()
        return path
    }

}
