import SwiftUI
import VibePetCore

/// The bubble UI for non-interactive notifications (technical design §5.3.1–5.3.2).
/// Renders `.status` (single line) and `.completion` (Markdown, scrolls past ~6
/// lines, error styling). Approval / question rendering lands in M4 / M5.
/// Positioning (quadrant anchoring, tail tracking, clamping) is done by the
/// controller via `BubbleAnchor`; this view draws the bubble and its tail and
/// owns the auto-dismiss timer (hover pauses it).
struct SpeechBubble: View {
    enum TailEdge {
        case top
        case bottom
    }

    let content: BubbleContent
    let source: SourceInfo
    var tailEdge: TailEdge = .bottom
    var tailOffsetX: CGFloat = 40
    var onDismiss: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            bodyContent
        }
        .padding(BubbleTheme.padding)
        .padding(tailEdge == .bottom ? .bottom : .top, BubbleTheme.tailSize.height)
        .frame(minWidth: BubbleTheme.minWidth, maxWidth: BubbleTheme.maxWidth, alignment: .leading)
        .background(bubbleBackground)
        .onHover { hovering = $0 }
        .task { await runAutoDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: toolIcon)
            Text(sourceLabel)
        }
        .font(BubbleTheme.headerFont)
        .foregroundStyle(BubbleTheme.headerText)
        .lineLimit(1)
    }

    private var toolIcon: String {
        switch source.tool {
        case .claudeCode: "sparkles"
        case .codex: "terminal"
        }
    }

    private var toolName: String {
        switch source.tool {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    private var sourceLabel: String {
        [toolName, source.projectName, source.sessionShortId]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        switch content {
        case let .status(status):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("💬")
                Text(status.text)
                    .font(BubbleTheme.bodyFont)
                    .foregroundStyle(BubbleTheme.bodyText)
                    .lineLimit(1)
            }
        case let .completion(completion):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: completion.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(completion.isError ? BubbleTheme.errorAccent : Color.accentColor)
                ScrollView {
                    Text(markdown(completion.markdownSummary))
                        .font(BubbleTheme.bodyFont)
                        .foregroundStyle(completion.isError ? BubbleTheme.errorAccent : BubbleTheme.bodyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: BubbleTheme.contentMaxHeight)
            }
        case .approval, .question:
            // Interactive cards land in M4 / M5.
            EmptyView()
        }
    }

    private func markdown(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string)) ?? AttributedString(string)
    }

    private var accessibilityLabel: String {
        switch content {
        case let .status(status): "\(sourceLabel): \(status.text)"
        case let .completion(completion): "\(sourceLabel): \(completion.markdownSummary)"
        case .approval, .question: sourceLabel
        }
    }

    // MARK: - Background + tail

    private var bubbleBackground: some View {
        BubbleShape(
            cornerRadius: BubbleTheme.cornerRadius,
            tailEdge: tailEdge,
            tailOffsetX: tailOffsetX,
            tailSize: BubbleTheme.tailSize
        )
        .fill(BubbleTheme.background)
        .overlay(
            BubbleShape(
                cornerRadius: BubbleTheme.cornerRadius,
                tailEdge: tailEdge,
                tailOffsetX: tailOffsetX,
                tailSize: BubbleTheme.tailSize
            )
            .stroke(BubbleTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Auto-dismiss

    private func runAutoDismiss() async {
        var remaining = autoDismissSeconds
        let tick = 0.1
        while remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
            if Task.isCancelled { return }
            if !hovering {
                remaining -= tick
            }
        }
        onDismiss()
    }

    private var autoDismissSeconds: Double {
        switch content {
        case .status: 7
        case .completion: 9
        case .approval, .question: 20
        }
    }
}

/// A rounded rectangle with a triangular tail on the pet-facing edge.
private struct BubbleShape: Shape {
    let cornerRadius: CGFloat
    let tailEdge: SpeechBubble.TailEdge
    let tailOffsetX: CGFloat
    let tailSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: bodyRect(in: rect), cornerRadius: cornerRadius)
        path.addPath(tailPath(in: rect))
        return path
    }

    private func bodyRect(in rect: CGRect) -> CGRect {
        switch tailEdge {
        case .bottom:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailSize.height)
        case .top:
            return CGRect(x: rect.minX, y: rect.minY + tailSize.height, width: rect.width, height: rect.height - tailSize.height)
        }
    }

    private func tailPath(in rect: CGRect) -> Path {
        var path = Path()
        let half = tailSize.width / 2
        let centerX = min(max(tailOffsetX, cornerRadius + half), rect.width - cornerRadius - half)

        switch tailEdge {
        case .bottom:
            let baseY = rect.maxY - tailSize.height
            path.move(to: CGPoint(x: centerX - half, y: baseY))
            path.addLine(to: CGPoint(x: centerX, y: rect.maxY))
            path.addLine(to: CGPoint(x: centerX + half, y: baseY))
        case .top:
            let baseY = rect.minY + tailSize.height
            path.move(to: CGPoint(x: centerX - half, y: baseY))
            path.addLine(to: CGPoint(x: centerX, y: rect.minY))
            path.addLine(to: CGPoint(x: centerX + half, y: baseY))
        }

        path.closeSubpath()
        return path
    }
}
