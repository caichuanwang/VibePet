import XCTest
@testable import VibePetApp
@testable import VibePetCore

/// M6-3: when an approval `requiresTerminalApproval` (Codex questions/plan-mode
/// that hooks cannot answer), `ApprovalCard` swaps its footer from Allow/Deny to a
/// single "回终端处理" affordance whose activation resolves as `.defer` (the user
/// handles it in the tool's native terminal). The header + `ActionPreview` body
/// still render — only the footer mode changes. SwiftUI rendering is verified by
/// manual demo; here we assert the pure footer-mode decision and the resolve value.
@MainActor
final class ApprovalCardTests: XCTestCase {
    func testFooterModeIsTerminalWhenRequiresTerminalApproval() {
        XCTAssertEqual(ApprovalCard.footerMode(for: approval(requiresTerminal: true)), .terminal)
    }

    func testFooterModeIsDecisionByDefault() {
        XCTAssertEqual(ApprovalCard.footerMode(for: approval(requiresTerminal: false)), .decision)
    }

    func testTerminalActivationResolvesAsDefer() {
        XCTAssertEqual(ApprovalCard.terminalResponse, .defer)
    }

    func testDecisionFooterProjectionShowsBackAndAvailableDecisionButtons() {
        let projection = ApprovalCard.footerProjection(
            for: approval(requiresTerminal: false, alwaysAllow: AlwaysAllowOption(label: "始终允许", scopeHint: "Bash")),
            source: source(jumpTarget: JumpTarget(terminalApp: "Terminal")),
            pendingCount: 2
        )

        XCTAssertEqual(projection.mode, .decision)
        XCTAssertTrue(projection.showsBackToTerminal)
        XCTAssertTrue(projection.showsDeny)
        XCTAssertTrue(projection.showsAllowOnce)
        XCTAssertTrue(projection.showsAlwaysAllow)
        XCTAssertEqual(projection.pendingCount, 2)
    }

    func testAlwaysAllowHiddenWhenAbsent() {
        let projection = ApprovalCard.footerProjection(
            for: approval(requiresTerminal: false, alwaysAllow: nil),
            source: source(jumpTarget: JumpTarget(terminalApp: "Terminal")),
            pendingCount: 0
        )

        XCTAssertFalse(projection.showsAlwaysAllow)
    }

    func testNormalBackToTerminalJumpsWithoutResolving() {
        let target = JumpTarget(terminalApp: "Terminal", terminalTTY: "/dev/ttys001")
        var jumped: [JumpTarget] = []

        let response = ApprovalCard.activateBackToTerminal(
            for: approval(requiresTerminal: false),
            source: source(jumpTarget: target),
            onJump: { jumped.append($0) }
        )

        XCTAssertEqual(jumped, [target])
        XCTAssertNil(response)
    }

    func testTerminalBackToTerminalJumpsAndDefers() {
        let target = JumpTarget(terminalApp: "Terminal", terminalTTY: "/dev/ttys001")
        var jumped: [JumpTarget] = []

        let response = ApprovalCard.activateBackToTerminal(
            for: approval(requiresTerminal: true),
            source: source(jumpTarget: target),
            onJump: { jumped.append($0) }
        )

        XCTAssertEqual(jumped, [target])
        XCTAssertEqual(response, .defer)
    }

    func testDecisionActionsResolveExactlyOnce() {
        var responses: [BridgeResponse] = []
        let content = approval(
            requiresTerminal: false,
            alwaysAllow: AlwaysAllowOption(label: "始终允许", scopeHint: "Bash")
        )

        ApprovalCard.performDecision(.deny, content: content) { responses.append($0) }
        ApprovalCard.performDecision(.allowOnce, content: content) { responses.append($0) }
        ApprovalCard.performDecision(.allowAlways, content: content) { responses.append($0) }

        XCTAssertEqual(responses, [
            .approval(.deny(reason: nil)),
            .approval(.allowOnce),
            .approval(.allowAlways(scopeHint: "Bash")),
        ])
    }

    func testUnavailableAlwaysAllowDoesNotResolve() {
        var responses: [BridgeResponse] = []

        ApprovalCard.performDecision(.allowAlways, content: approval(requiresTerminal: false, alwaysAllow: nil)) {
            responses.append($0)
        }

        XCTAssertTrue(responses.isEmpty)
    }

    func testLayoutProjectionOmitsConversationContextAndKeepsPreviewPrimary() {
        let content = approval(requiresTerminal: false)
        let projection = ApprovalCard.layoutProjection(for: content)

        XCTAssertFalse(projection.includesConversationContext)
        XCTAssertEqual(projection.primaryPreview, content.preview)
        XCTAssertEqual(projection.footerMode, .decision)
    }

    private func approval(
        requiresTerminal: Bool,
        alwaysAllow: AlwaysAllowOption? = nil,
        risk: RiskLevel = .medium
    ) -> ApprovalContent {
        ApprovalContent(
            title: "需在终端处理",
            risk: risk,
            preview: .generic(summary: "Pick a deployment target"),
            alwaysAllow: alwaysAllow,
            requiresTerminalApproval: requiresTerminal
        )
    }

    private func source(jumpTarget: JumpTarget?) -> SourceInfo {
        SourceInfo(
            tool: .claudeCode,
            projectName: "VibePet",
            sessionShortId: "a1b2c3",
            cwd: "/tmp/VibePet",
            jumpTarget: jumpTarget
        )
    }
}
