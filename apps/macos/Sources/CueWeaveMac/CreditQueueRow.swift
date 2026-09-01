import SwiftUI

struct CreditQueueRow: View {
    let text: String
    let timeMS: UInt64
    let isPrimary: Bool
    let onSelect: () -> Void
    let onStamp: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("C")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(CueWeaveStyle.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(cueTime(timeMS))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .background(isPrimary ? CueWeaveStyle.lyricSelectedFill : Color.clear)
        .contextMenu {
            Button("Mark", action: onStamp)
        }
    }
}
