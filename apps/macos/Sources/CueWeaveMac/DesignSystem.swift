import SwiftUI

enum CueWeaveStyle {
    static let accent = Color(red: 0.22, green: 0.43, blue: 0.55)
    static let gemini = Color(red: 0.30, green: 0.49, blue: 0.61)
    static var lyricPlayingFill: Color { accent.opacity(0.14) }
    static var lyricSelectedFill: Color { accent.opacity(0.20) }
    static let ready = Color(red: 0.39, green: 0.52, blue: 0.48)
    static let warning = Color(red: 0.72, green: 0.47, blue: 0.18)
    static let lowBand = Color(red: 0.25, green: 0.48, blue: 0.64)
    static let midBand = Color(red: 0.72, green: 0.47, blue: 0.18)
    static let highBand = Color(red: 0.55, green: 0.36, blue: 0.64)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let workspace = Color(nsColor: .windowBackgroundColor)
}

struct SectionHeading: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatusPill: View {
    let text: String
    var tone: Color = .secondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tone.opacity(0.09))
            .overlay { Rectangle().stroke(tone.opacity(0.24), lineWidth: 1) }
    }
}

struct DataReadout: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

struct LayerReadout: View {
    let name: String
    let point: AlignmentPoint?
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tone)
                Spacer()
                Text(point?.confidence.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(cueTime(point?.timeMS))
                .font(.system(size: 14, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(8)
        .frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
        .overlay { Rectangle().stroke(tone.opacity(0.28), lineWidth: 1) }
    }
}

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CueWeaveStyle.panel)
            .overlay { Rectangle().stroke(.quaternary, lineWidth: 1) }
    }
}

struct EmptyWorkspaceState: View {
    let title: String
    let detail: String
    var icon = "square.dashed"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

func cueTime(_ milliseconds: UInt64?) -> String {
    guard let milliseconds else { return "—" }
    return String(
        format: "%02llu:%02llu.%03llu",
        milliseconds / 60_000,
        milliseconds / 1_000 % 60,
        milliseconds % 1_000
    )
}
