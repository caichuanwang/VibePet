import AppKit
import SwiftUI
import VibePetCore

/// The interactive approval bubble for the `decide` state (technical design
/// §5.3.3). Three sections: a header (source + risk), a compact `ActionPreview`
/// body, and a footer with action buttons. Risk drives coloring and the default
/// focus — `.high` focuses "拒绝" so allowing is always a deliberate click. The
/// card waits for a user decision; dismissal/fail-open is owned by the surrounding
/// surface and hook runtime.
struct ApprovalCard: View {
    enum Field {
        case deny
        case allow
    }

    /// The footer's interaction mode. A normal approval shows the decision buttons;
    /// a `requiresTerminalApproval` request (Codex questions/plan-mode that hooks
    /// cannot answer, §5.3.3 末) shows only a "回终端处理" affordance.
    enum FooterMode: Equatable {
        case decision
        case terminal
    }

    /// Pure decision used by both the view and tests.
    static func footerMode(for content: ApprovalContent) -> FooterMode {
        content.requiresTerminalApproval ? .terminal : .decision
    }

    /// Activating "回终端处理" defers so the tool falls back to its native flow.
    static let terminalResponse: BridgeResponse = .defer

    static func jumpBack(from source: SourceInfo, onJump: (JumpTarget) -> Void) {
        if let jumpTarget = source.jumpTarget {
            onJump(jumpTarget)
        }
    }

    let content: ApprovalContent
    let source: SourceInfo
    var tailEdge: SpeechBubble.TailEdge = .bottom
    var tailOffsetX: CGFloat = 40
    var onJump: (JumpTarget) -> Void = { _ in }
    var onDecision: (BridgeResponse) -> Void = { _ in }

    @ObservedObject var presentation: ApprovalPresentation
    @FocusState private var focus: Field?

    init(
        content: ApprovalContent,
        source: SourceInfo,
        tailEdge: SpeechBubble.TailEdge = .bottom,
        tailOffsetX: CGFloat = 40,
        presentation: ApprovalPresentation,
        onJump: @escaping (JumpTarget) -> Void = { _ in },
        onDecision: @escaping (BridgeResponse) -> Void = { _ in }
    ) {
        self.content = content
        self.source = source
        self.tailEdge = tailEdge
        self.tailOffsetX = tailOffsetX
        self.presentation = presentation
        self.onJump = onJump
        self.onDecision = onDecision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider().overlay(BubbleTheme.separator)
            previewBody
            footer
        }
        .padding(BubbleTheme.padding)
        .frame(minWidth: BubbleTheme.minWidth, maxWidth: BubbleTheme.maxWidth, alignment: .leading)
        .background(bubbleBackground)
        .contentShape(
            BubbleShape(
                cornerRadius: BubbleTheme.cornerRadius,
                tailEdge: tailEdge,
                tailOffsetX: tailOffsetX,
                tailSize: BubbleTheme.tailSize
            )
        )
        .onTapGesture(count: 2) {
            Self.jumpBack(from: source, onJump: onJump)
        }
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
                .background(BubbleTheme.fieldBackground, in: RoundedRectangle(cornerRadius: BubbleTheme.innerCornerRadius))
        case let .fileChange(path, added, removed):
            VStack(alignment: .leading, spacing: 2) {
                Text(path).font(BubbleTheme.monoFont).lineLimit(1).truncationMode(.middle)
                Text("+\(added) −\(removed)")
                    .font(.caption)
                    .foregroundStyle(BubbleTheme.mutedText)
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

    // MARK: - Footer (buttons)

    @ViewBuilder
    private var footer: some View {
        switch Self.footerMode(for: content) {
        case .decision:
            HStack(spacing: 8) {
                pendingLabel
                Spacer(minLength: 6)
                buttons
            }
        case .terminal:
            terminalFooter
        }
    }

    /// Degraded footer for `requiresTerminalApproval`: a readable hint plus a single
    /// "回终端处理" button. MVP only copies the action summary and defers (real
    /// jump-back to the terminal is v1.1).
    private var terminalFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("此请求需在终端继续处理")
                .font(.caption)
                .foregroundStyle(BubbleTheme.mutedText)
            HStack(spacing: 8) {
                pendingLabel
                Spacer(minLength: 6)
                Button("回终端处理") { handleInTerminal() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func handleInTerminal() {
        Self.jumpBack(from: source, onJump: onJump)
        // Copy the action summary so the user can locate/paste it in the terminal,
        // then defer to the tool's native flow.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(previewText, forType: .string)
        decide(Self.terminalResponse)
    }

    private var previewText: String {
        switch content.preview {
        case let .command(text): text
        case let .fileChange(path, _, _): path
        case let .fileRead(path): path
        case let .network(target): target
        case let .generic(summary): summary
        }
    }

    @ViewBuilder
    private var pendingLabel: some View {
        if presentation.pendingCount > 0 {
            Text("还有 \(presentation.pendingCount) 个待处理")
                .font(.caption2)
                .foregroundStyle(BubbleTheme.mutedText)
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button("拒绝") { decide(.approval(.deny(reason: nil))) }
                .keyboardShortcut(.cancelAction)
                .focused($focus, equals: .deny)
                .buttonStyle(.bordered)
            Button(content.allowLabel) { decide(.approval(.allowOnce)) }
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .allow)
                .buttonStyle(.borderedProminent)
                .tint(content.risk == .high ? .gray : .accentColor)
            if let always = content.alwaysAllow {
                Button(always.label) {
                    decide(.approval(.allowAlways(scopeHint: always.scopeHint)))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Decision

    private func decide(_ response: BridgeResponse) {
        onDecision(response)
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
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 8)
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
