import SwiftUI
import VibePetCore

/// The interactive approval bubble for the `decide` state (technical design
/// §5.3.3). Three sections: a header (source + risk), a compact `ActionPreview`
/// body, and a footer (countdown + buttons). Risk drives coloring and the default
/// focus — `.high` focuses "拒绝" so allowing is always a deliberate click. The
/// card owns a visual countdown that fails open (`.defer`) at zero; the controller
/// keeps an authoritative backstop timer as well, and `onDecision` is idempotent
/// upstream so whichever fires first wins.
struct ApprovalCard: View {
    enum Field {
        case deny
        case allow
    }

    let content: ApprovalContent
    let source: SourceInfo
    var tailEdge: SpeechBubble.TailEdge = .bottom
    var tailOffsetX: CGFloat = 40
    let timeout: TimeInterval
    var onDecision: (BridgeResponse) -> Void = { _ in }

    @ObservedObject var presentation: ApprovalPresentation
    @State private var remaining: TimeInterval
    @FocusState private var focus: Field?

    init(
        content: ApprovalContent,
        source: SourceInfo,
        tailEdge: SpeechBubble.TailEdge = .bottom,
        tailOffsetX: CGFloat = 40,
        timeout: TimeInterval,
        presentation: ApprovalPresentation,
        onDecision: @escaping (BridgeResponse) -> Void = { _ in }
    ) {
        self.content = content
        self.source = source
        self.tailEdge = tailEdge
        self.tailOffsetX = tailOffsetX
        self.timeout = timeout
        self.presentation = presentation
        self.onDecision = onDecision
        _remaining = State(initialValue: timeout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            previewBody
            footer
        }
        .padding(BubbleTheme.padding)
        .padding(tailEdge == .bottom ? .bottom : .top, BubbleTheme.tailSize.height)
        .frame(minWidth: BubbleTheme.minWidth, maxWidth: BubbleTheme.maxWidth, alignment: .leading)
        .background(bubbleBackground)
        .task { await runCountdown() }
        .onAppear { focus = content.risk == .high ? .deny : .allow }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sourceLabel)：\(content.title)，\(BubbleTheme.riskLabel(content.risk))")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: toolIcon)
            Text(sourceLabel)
                .lineLimit(1)
            Spacer(minLength: 6)
            riskBadge
        }
        .font(BubbleTheme.headerFont)
        .foregroundStyle(BubbleTheme.headerText)
    }

    private var riskBadge: some View {
        Text(BubbleTheme.riskLabel(content.risk))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(BubbleTheme.riskAccent(content.risk).opacity(0.16), in: Capsule())
            .foregroundStyle(BubbleTheme.riskAccent(content.risk))
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

    // MARK: - Body (ActionPreview)

    @ViewBuilder
    private var previewBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .font(BubbleTheme.bodyFont.weight(.semibold))
                .foregroundStyle(BubbleTheme.bodyText)
            previewDetail
        }
    }

    @ViewBuilder
    private var previewDetail: some View {
        switch content.preview {
        case let .command(text):
            Text(truncatedCommand(text))
                .font(BubbleTheme.monoFont)
                .foregroundStyle(content.risk == .high ? BubbleTheme.errorAccent : BubbleTheme.bodyText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        case let .fileChange(path, added, removed):
            VStack(alignment: .leading, spacing: 2) {
                Text(path).font(BubbleTheme.monoFont).lineLimit(1).truncationMode(.middle)
                Text("+\(added) −\(removed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .fileRead(path):
            Text(path).font(BubbleTheme.monoFont).lineLimit(2).truncationMode(.middle)
        case let .network(target):
            Text(target).font(BubbleTheme.monoFont).lineLimit(2).truncationMode(.middle)
        case let .generic(summary):
            Text(summary).font(BubbleTheme.bodyFont).foregroundStyle(BubbleTheme.bodyText)
        }
    }

    /// Truncates a command body to 3 lines, eliding the remainder (§5.3.3).
    private func truncatedCommand(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 3 else { return text }
        return lines.prefix(3).joined(separator: "\n") + "\n…"
    }

    // MARK: - Footer (countdown + buttons)

    private var footer: some View {
        HStack(spacing: 8) {
            countdownLabel
            Spacer(minLength: 6)
            buttons
        }
    }

    private var countdownLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
            Text("\(Int(ceil(remaining)))s")
            if presentation.pendingCount > 0 {
                Text("· 还有 \(presentation.pendingCount) 个待处理")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button("拒绝") { decide(.approval(.deny(reason: nil))) }
                .keyboardShortcut(.cancelAction)
                .focused($focus, equals: .deny)
                .buttonStyle(.bordered)
                .tint(content.risk == .high ? .red : nil)

            if let always = content.alwaysAllow {
                Button(always.label) {
                    decide(.approval(.allowAlways(scopeHint: always.scopeHint)))
                }
                .buttonStyle(.bordered)
            }

            Button(content.allowLabel) { decide(.approval(.allowOnce)) }
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .allow)
                .buttonStyle(.borderedProminent)
                .tint(content.risk == .high ? .gray : .accentColor)
        }
        .font(.callout)
    }

    private func decide(_ response: BridgeResponse) {
        onDecision(response)
    }

    // MARK: - Countdown (visual; fails open at zero)

    private func runCountdown() async {
        let tick = 0.1
        while remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
            if Task.isCancelled { return }
            remaining = max(0, remaining - tick)
        }
        onDecision(.defer)
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
            .stroke(BubbleTheme.riskAccent(content.risk).opacity(0.5), lineWidth: 1)
        )
    }
}
