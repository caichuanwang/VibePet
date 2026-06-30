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

    enum DecisionAction: Equatable {
        case deny
        case allowOnce
        case allowAlways
    }

    struct FooterProjection: Equatable {
        let mode: FooterMode
        let showsBackToTerminal: Bool
        let showsDeny: Bool
        let showsAllowOnce: Bool
        let showsAlwaysAllow: Bool
        let pendingCount: Int
    }

    struct LayoutProjection: Equatable {
        let footerMode: FooterMode
        let includesConversationContext: Bool
        let primaryPreview: ActionPreview
    }

    /// Pure decision used by both the view and tests.
    static func footerMode(for content: ApprovalContent) -> FooterMode {
        content.requiresTerminalApproval ? .terminal : .decision
    }

    static func footerProjection(
        for content: ApprovalContent,
        source: SourceInfo,
        pendingCount: Int
    ) -> FooterProjection {
        let mode = footerMode(for: content)
        return FooterProjection(
            mode: mode,
            showsBackToTerminal: source.jumpTarget != nil || mode == .terminal,
            showsDeny: mode == .decision,
            showsAllowOnce: mode == .decision,
            showsAlwaysAllow: mode == .decision && content.alwaysAllow != nil,
            pendingCount: pendingCount
        )
    }

    static func layoutProjection(for content: ApprovalContent) -> LayoutProjection {
        LayoutProjection(
            footerMode: footerMode(for: content),
            includesConversationContext: false,
            primaryPreview: content.preview
        )
    }

    /// Activating "回终端处理" defers so the tool falls back to its native flow.
    static let terminalResponse: BridgeResponse = .defer

    static func jumpBack(from source: SourceInfo, onJump: (JumpTarget) -> Void) {
        if let jumpTarget = source.jumpTarget {
            onJump(jumpTarget)
        }
    }

    static func activateBackToTerminal(
        for content: ApprovalContent,
        source: SourceInfo,
        onJump: (JumpTarget) -> Void
    ) -> BridgeResponse? {
        jumpBack(from: source, onJump: onJump)
        return footerMode(for: content) == .terminal ? terminalResponse : nil
    }

    static func response(for action: DecisionAction, content: ApprovalContent) -> BridgeResponse? {
        switch action {
        case .deny:
            return .approval(.deny(reason: nil))
        case .allowOnce:
            return .approval(.allowOnce)
        case .allowAlways:
            guard let always = content.alwaysAllow else { return nil }
            return .approval(.allowAlways(scopeHint: always.scopeHint))
        }
    }

    static func performDecision(
        _ action: DecisionAction,
        content: ApprovalContent,
        onDecision: (BridgeResponse) -> Void
    ) {
        guard let response = response(for: action, content: content) else { return }
        onDecision(response)
    }

    let content: ApprovalContent
    let source: SourceInfo
    var tailEdge: SpeechBubble.TailEdge = .bottom
    var tailOffsetX: CGFloat = 40
    var localizer: AppLocalizer = AppLocalizer(language: .simplifiedChinese)
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
        localizer: AppLocalizer = AppLocalizer(language: .simplifiedChinese),
        onJump: @escaping (JumpTarget) -> Void = { _ in },
        onDecision: @escaping (BridgeResponse) -> Void = { _ in }
    ) {
        self.content = content
        self.source = source
        self.tailEdge = tailEdge
        self.tailOffsetX = tailOffsetX
        self.presentation = presentation
        self.localizer = localizer
        self.onJump = onJump
        self.onDecision = onDecision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            previewBody
            footer
        }
        .frame(minWidth: BubbleTheme.minWidth, maxWidth: BubbleTheme.maxWidth, alignment: .leading)
        .background(BubbleTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: BubbleTheme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: BubbleTheme.cornerRadius)
                .stroke(BubbleTheme.riskAccent(content.risk).opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 8)
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
        .accessibilityLabel("\(sourceLabel): \(content.title), \(BubbleTheme.riskLabel(content.risk, localizer: localizer))")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    toolMark
                    Text(source.projectName ?? toolName)
                        .font(BubbleTheme.bodyFont.weight(.semibold))
                        .foregroundStyle(BubbleTheme.bodyText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(BubbleTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            statusChip
        }
        .padding(.horizontal, BubbleTheme.padding)
        .padding(.top, BubbleTheme.padding)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BubbleTheme.separator).frame(height: 1)
        }
    }

    private var toolMark: some View {
        Text(toolMarkLetter)
            .font(.system(size: 11, weight: .heavy))
            .frame(width: 18, height: 18)
            .background(toolAccent.opacity(source.tool == .claudeCode ? 0.14 : 0.16), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(toolAccent)
            .accessibilityHidden(true)
    }

    private var toolMarkLetter: String {
        switch source.tool {
        case .claudeCode: "A"
        case .codex: "C"
        }
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle().fill(BubbleTheme.accentOrange).frame(width: 7, height: 7)
            Text(localizer.text(.approvalPending))
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .foregroundStyle(BubbleTheme.riskTextColor(.medium))
        .background(BubbleTheme.accentOrange.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(BubbleTheme.accentOrange.opacity(0.38), lineWidth: 1))
        .fixedSize()
    }

    private var toolAccent: Color {
        switch source.tool {
        case .claudeCode: BubbleTheme.accentOrange
        case .codex: BubbleTheme.accentBlue
        }
    }

    private var metaLine: String {
        [toolName, source.sessionShortId.map { "#\($0)" }, source.jumpTarget?.terminalApp]
            .compactMap { $0 }
            .joined(separator: " · ")
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

    private var previewBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(content.title)
                    .font(BubbleTheme.bodyFont.weight(.semibold))
                    .foregroundStyle(BubbleTheme.bodyText)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(BubbleTheme.riskLabel(content.risk, localizer: localizer))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BubbleTheme.riskTextColor(content.risk))
                    .fixedSize()
            }
            previewDetail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BubbleTheme.padding)
    }

    @ViewBuilder
    private var previewDetail: some View {
        switch content.preview {
        case let .command(text):
            Text(truncatedCommand(text))
                .font(BubbleTheme.monoFont)
                .foregroundStyle(BubbleTheme.bodyText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: BubbleTheme.innerCornerRadius)
                        .fill(BubbleTheme.riskAccent(content.risk).opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BubbleTheme.innerCornerRadius)
                        .stroke(BubbleTheme.riskAccent(content.risk).opacity(0.34), lineWidth: 1)
                )
        case let .fileChange(path, added, removed):
            codeBox {
                VStack(alignment: .leading, spacing: 2) {
                    Text(path).font(BubbleTheme.monoFont).lineLimit(1).truncationMode(.middle)
                    Text("+\(added) −\(removed)")
                        .font(.caption)
                        .foregroundStyle(BubbleTheme.mutedText)
                }
            }
        case let .fileRead(path):
            codeBox {
                Text(path).font(BubbleTheme.monoFont).lineLimit(2).truncationMode(.middle)
            }
        case let .network(target):
            codeBox {
                Text(target).font(BubbleTheme.monoFont).lineLimit(2).truncationMode(.middle)
            }
        case let .generic(summary):
            Text(summary)
                .font(BubbleTheme.bodyFont)
                .foregroundStyle(BubbleTheme.bodyText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func codeBox<Content: View>(@ViewBuilder _ inner: () -> Content) -> some View {
        inner()
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(BubbleTheme.bodyText)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: BubbleTheme.innerCornerRadius)
                    .fill(BubbleTheme.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BubbleTheme.innerCornerRadius)
                    .stroke(BubbleTheme.codeboxBorder, lineWidth: 1)
            )
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
            BubbleFooter {
                if source.jumpTarget != nil {
                    Button(localizer.text(.backToTerminal)) { handleBackToTerminal() }
                        .buttonStyle(BubbleActionButtonStyle(variant: .neutral))
                        .accessibilityLabel(localizer.text(.backToTerminal))
                }
            } trailing: {
                pendingLabel
                buttons
            }
        case .terminal:
            terminalFooter.bubbleFooterBar()
        }
    }

    /// Degraded footer for `requiresTerminalApproval`: a readable hint plus a single
    /// "回终端处理" button. MVP only copies the action summary and defers (real
    /// jump-back to the terminal is v1.1).
    private var terminalFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizer.text(.approvalTerminalRequired))
                .font(.caption)
                .foregroundStyle(BubbleTheme.mutedText)
            HStack(spacing: BubbleTheme.footerButtonSpacing) {
                pendingLabel
                Spacer(minLength: 8)
                Button(localizer.text(.handleInTerminal)) { handleInTerminal() }
                    .buttonStyle(BubbleActionButtonStyle(variant: .primary))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(localizer.text(.handleInTerminal))
            }
        }
    }

    private func handleBackToTerminal() {
        _ = Self.activateBackToTerminal(for: content, source: source, onJump: onJump)
    }

    private func handleInTerminal() {
        let response = Self.activateBackToTerminal(for: content, source: source, onJump: onJump)
        // Copy the action summary so the user can locate/paste it in the terminal,
        // then defer to the tool's native flow.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(previewText, forType: .string)
        decide(response ?? Self.terminalResponse)
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
            Text(localizer.text(.pendingCount, presentation.pendingCount))
                .font(.caption2)
                .foregroundStyle(BubbleTheme.mutedText)
        }
    }

    private var buttons: some View {
        HStack(spacing: BubbleTheme.footerButtonSpacing) {
            Button(content.denyLabel) { decide(.deny) }
                .buttonStyle(BubbleActionButtonStyle(variant: .danger))
                .keyboardShortcut(.cancelAction)
                .focused($focus, equals: .deny)
                .overlay { focusRing(.deny) }
                .accessibilityLabel(content.denyLabel)
            Button(content.allowLabel) { decide(.allowOnce) }
                .buttonStyle(BubbleActionButtonStyle(variant: .primary))
                .keyboardShortcut(.defaultAction)
                .focused($focus, equals: .allow)
                .overlay { focusRing(.allow) }
                .accessibilityLabel(content.allowLabel)
            if let always = content.alwaysAllow {
                Button(always.label) {
                    decide(.allowAlways)
                }
                .buttonStyle(BubbleActionButtonStyle(variant: .trust))
                .accessibilityLabel(always.label)
            }
        }
    }

    @ViewBuilder
    private func focusRing(_ field: Field) -> some View {
        if focus == field {
            RoundedRectangle(cornerRadius: 6)
                .stroke(BubbleTheme.accentBlue, lineWidth: 2)
        }
    }

    // MARK: - Decision

    private func decide(_ action: DecisionAction) {
        Self.performDecision(action, content: content, onDecision: onDecision)
    }

    private func decide(_ response: BridgeResponse) {
        onDecision(response)
    }
}
