import SwiftUI

struct SegmentQueueRow: View {
    @ObservedObject private var l10n = L10n.shared
    let segment: LyricSegment
    let isPrimary: Bool
    let isPlaybackActive: Bool
    let isIncluded: Bool
    let onSelect: () -> Void
    let onJump: () -> Void
    let onToggle: () -> Void
    let onStamp: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isIncluded ? CueWeaveStyle.accent : Color.secondary.opacity(0.6))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(format: "%04llu", segment.id)).foregroundStyle(.tertiary)
                    Spacer()
                    Text(cueTime(segment.timing.finalPoint?.timeMS ?? segment.timing.gemini?.timeMS))
                }
                .font(.system(size: 8, design: .monospaced))
                Text(segment.text)
                    .lineLimit(1)
                    .foregroundStyle(isPlaybackActive ? CueWeaveStyle.accent : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isPlaybackActive {
                Rectangle().fill(CueWeaveStyle.accent).frame(width: 3)
            }
        }
        .clipped()
        .accessibilityAddTraits(isPrimary ? [.isSelected] : [])
        .accessibilityHint(l10n.t("row.hint"))
        .contextMenu {
            Button(l10n.t("row.select"), action: onSelect)
            Button(l10n.t("row.jump"), action: onJump)
            Button(l10n.t("row.stamp"), action: onStamp)
            Button(l10n.t("row.clear"), action: onClear).disabled(segment.timing.finalPoint == nil)
        }
    }

    private var rowBackground: Color {
        if isPrimary { return CueWeaveStyle.lyricSelectedFill }
        if isPlaybackActive { return CueWeaveStyle.lyricPlayingFill }
        return .clear
    }
}
