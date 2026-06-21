import XCTest
@testable import VibePetApp
@testable import VibePetCore

/// M6-3: when an approval `requiresTerminalApproval` (Codex questions/plan-mode
/// that hooks cannot answer), `ApprovalCard` swaps its footer from Allow/Deny to a
/// single "回终端处理" affordance whose activation resolves as `.defer` (the user
/// handles it in the tool's native terminal). The header + `ActionPreview` body
/// still render — only the footer mode changes. SwiftUI rendering is verified by
/// manual demo; here we assert the pure footer-mode decision and the resolve value.
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

    private func approval(requiresTerminal: Bool) -> ApprovalContent {
        ApprovalContent(
            title: "需在终端处理",
            risk: .medium,
            preview: .generic(summary: "Pick a deployment target"),
            alwaysAllow: nil,
            requiresTerminalApproval: requiresTerminal
        )
    }
}
