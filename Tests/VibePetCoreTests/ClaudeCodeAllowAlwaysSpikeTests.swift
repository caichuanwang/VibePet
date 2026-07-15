import XCTest
@testable import VibePetCore

/// Pins the Claude Code `PermissionRequest` allow-always contract.
/// VibePet exposes a session-scoped allow option and encodes it as
/// `decision.updatedPermissions`.
final class ClaudeCodeAllowAlwaysSpikeTests: XCTestCase {
    private let adapter = ClaudeCodeAdapter()

    func testParsedApprovalAdvertisesAlwaysAllowOption() throws {
        let envelope = try XCTUnwrap(adapter.parseEvent(stdin: fixtureData("permission-request-bash.json"), env: [:]))
        guard case let .approval(content) = envelope.content else {
            return XCTFail("Expected .approval")
        }
        XCTAssertEqual(content.alwaysAllow?.label, "始终允许 Bash")
        XCTAssertEqual(content.alwaysAllow?.scopeHint, "Bash")
    }

    func testAllowAlwaysEncodesSessionScopedPermissionRule() throws {
        let data = adapter.encodeResponse(
            .approval(.allowAlways(scopeHint: "Bash")),
            for: sampleEnvelope()
        )
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")

        let permissions = try XCTUnwrap(decision["updatedPermissions"] as? [[String: Any]])
        let update = try XCTUnwrap(permissions.first)
        XCTAssertEqual(update["type"] as? String, "addRules")
        XCTAssertEqual(update["destination"] as? String, "session")
        XCTAssertEqual(update["behavior"] as? String, "allow")
        let rules = try XCTUnwrap(update["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.first?["toolName"] as? String, "Bash")
    }

    // MARK: - Helpers

    private func sampleEnvelope() -> BridgeEnvelope {
        BridgeEnvelope(
            requestId: UUID(),
            source: SourceInfo(tool: .claudeCode, projectName: "VibePet", sessionShortId: "a1b2c3", cwd: nil),
            content: .approval(ApprovalContent(
                title: "运行命令",
                risk: .medium,
                preview: .command(text: "swift test"),
                alwaysAllow: nil,
                requiresTerminalApproval: false
            ))
        )
    }

    private func fixtureData(_ name: String) -> Data {
        (try? Data(contentsOf: URL(fileURLWithPath:
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/claude/\(name)")
                .path
        ))) ?? Data()
    }
}
